#!/bin/bash
# GitHub Runner Lifecycle Monitoring Service
# Monitors runner idle time and stops instance when threshold is exceeded
# Supports multiple providers: generic (any server) and aws (AWS EC2)

set -e

# Configuration
CONFIG_FILE="/etc/github-runner/config.json"
LOG_FILE="/var/log/github-runner/lifecycle.log"
RUNNER_DIR=${RUNNER_DIR:-"/opt/actions-runner"}
PROVIDER_DIR="/usr/local/lib/github-runner-lifecycle/providers"

# Default values (will be overridden by config or provider)
INSTANCE_ID=""
REGION=""
PROVIDER="generic"
SNS_TOPIC_ARN=""
STOP_COMMAND=""
EVENT_HOOK_SCRIPT=""

# Initialize log file
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

log() {
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  echo "[$timestamp] $1" | tee -a $LOG_FILE
}

log_error() {
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  echo "[$timestamp] ERROR: $1" | tee -a $LOG_FILE >&2
}

# Load provider script
load_provider() {
  local provider=$1
  local provider_file="${PROVIDER_DIR}/${provider}.sh"
  
  if [ ! -f "$provider_file" ]; then
    log_error "Provider file not found: $provider_file"
    log_error "Available providers: generic, aws"
    return 1
  fi
  
  log "Loading provider: $provider"
  source "$provider_file"
  
  # Initialize provider
  if ! provider_init; then
    log_error "Failed to initialize provider: $provider"
    return 1
  fi
}

# Load configuration from JSON file
load_configuration() {
  if [ ! -f "$CONFIG_FILE" ]; then
    log "Configuration file not found at $CONFIG_FILE, using defaults"
    return 0
  fi
  
  log "Loading configuration from $CONFIG_FILE"
  
  # Validate JSON
  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    log_error "Invalid JSON in configuration file"
    return 1
  fi
  
  # Export variables from JSON
  export IDLE_TIMEOUT=$(jq -r '.IDLE_TIMEOUT // 30' $CONFIG_FILE)
  export CHECK_INTERVAL=$(jq -r '.CHECK_INTERVAL // 60' $CONFIG_FILE)
  export RUNNER_NAME=$(jq -r '.RUNNER_NAME // "'$(hostname)'"' $CONFIG_FILE)
  export PROVIDER=$(jq -r '.PROVIDER // "generic"' $CONFIG_FILE)
  export SNS_TOPIC_ARN=$(jq -r '.SNS_TOPIC_ARN // ""' $CONFIG_FILE)
  export STOP_COMMAND=$(jq -r '.STOP_COMMAND // ""' $CONFIG_FILE)
  export EVENT_HOOK_SCRIPT=$(jq -r '.EVENT_HOOK_SCRIPT // ""' $CONFIG_FILE)
  export INSTANCE_ID=$(jq -r '.INSTANCE_ID // ""' $CONFIG_FILE)
  export REGION=$(jq -r '.REGION // ""' $CONFIG_FILE)
  
  log "Configuration loaded: IDLE_TIMEOUT=${IDLE_TIMEOUT}m, CHECK_INTERVAL=${CHECK_INTERVAL}s, PROVIDER=${PROVIDER}"
}

# Report metrics to statsd (universal, works with any statsd server)
report_metric() {
  local metric=$1
  local value=$2
  local type=${3:-gauge}
  
  # Check if statsd is available
  if ! nc -zv 127.0.0.1 8125 &>/dev/null 2>&1; then
    # Statsd not available, skip silently (not an error)
    return 0
  fi
  
  if echo "$metric:$value|$type" | nc -u -w1 127.0.0.1 8125 2>/dev/null; then
    log "Reported metric: $metric = $value ($type)"
  else
    log_error "Failed to report metric: $metric"
  fi
}

# Publish lifecycle event (delegates to provider)
publish_event() {
  local event=$1
  local data=$2
  
  if type provider_publish_event &>/dev/null; then
    provider_publish_event "$event" "$data"
  else
    log "Provider publish_event not available, skipping event: $event"
  fi
}

# Get list of runner services
get_runner_services() {
  systemctl list-units 'actions.runner.*' --no-legend --no-pager 2>/dev/null | awk '{print $1}' || echo ""
}

# Check if runner is idle
is_runner_idle() {
  local runner_services=$(get_runner_services)
  
  if [ -z "$runner_services" ]; then
    log "No runner services found, assuming idle"
    return 0
  fi
  
  # Check if any service is running
  local running_count=0
  while IFS= read -r service; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
      ((running_count++))
      log "Runner service $service is active"
    fi
  done <<< "$runner_services"
  
  if [ $running_count -eq 0 ]; then
    log "No active runner services, assuming idle"
    return 0
  fi
  
  # Check diagnostic files for job status
  local diag_files=$(find ${RUNNER_DIR}/_diag -name "*.json" -type f -mmin -5 2>/dev/null | sort -r)
  
  if [ -z "$diag_files" ]; then
    log "No recent diagnostic files found, assuming idle"
    return 0
  fi
  
  local latest_diag=$(echo "$diag_files" | head -1)
  local worker_status=$(jq -r '.runnerStatus // "Unknown"' "$latest_diag" 2>/dev/null || echo "Unknown")
  
  if [ "$worker_status" = "idle" ] || [ "$worker_status" = "online" ]; then
    log "Runner status: $worker_status - Runner is idle"
    return 0
  else
    log "Runner status: $worker_status - Runner is busy"
    return 1
  fi
}

# Get idle time in minutes based on when runner became idle
get_idle_time() {
  # Check when the runner last transitioned to idle state
  local state_file="/var/run/github-runner/idle_since"
  
  if [ -f "$state_file" ]; then
    local idle_since=$(cat "$state_file" 2>/dev/null || echo "0")
    
    # Validate timestamp
    if ! [[ "$idle_since" =~ ^[0-9]+$ ]]; then
      log_error "Invalid timestamp in idle state file"
      idle_since=$(date +%s)
      echo "$idle_since" > "$state_file"
    fi
    
    local current_timestamp=$(date +%s)
    local idle_time_seconds=$((current_timestamp - idle_since))
    local idle_time_minutes=$((idle_time_seconds / 60))
    echo $idle_time_minutes
  else
    # First check - initialize idle state
    mkdir -p /var/run/github-runner
    date +%s > "$state_file"
    echo 0
  fi
}

# Stop the instance if idle for too long (delegates to provider)
handle_idle_timeout() {
  local idle_minutes=$1
  
  log "Runner has been idle for $idle_minutes minutes (threshold: $IDLE_TIMEOUT minutes)"
  report_metric "runner.idle_minutes" $idle_minutes
  
  if [ $idle_minutes -ge $IDLE_TIMEOUT ]; then
    log "Idle timeout reached, preparing to stop instance"
    
    # Send notification before stopping
    publish_event "idle_timeout_reached" "{\"idle_minutes\": $idle_minutes, \"threshold\": $IDLE_TIMEOUT}"
    
    # Record stopping event
    report_metric "runner.stopping" 1
    
    log "Stopping instance due to idle timeout"
    
    # Delegate to provider
    if type provider_stop_instance &>/dev/null; then
      provider_stop_instance $idle_minutes $IDLE_TIMEOUT
    else
      log_error "Provider stop_instance function not available, using fallback shutdown"
      shutdown -h now
    fi
  fi
}

# Graceful shutdown handler
shutdown_handler() {
  log "Received shutdown signal, cleaning up..."
  report_metric "runner.stopped" 1
  publish_event "lifecycle_service_stopped" "{}"
  exit 0
}

# Main monitoring loop
main() {
  log "========================================"
  log "GitHub Runner Lifecycle Monitor Started"
  log "========================================"
  
  # Load configuration first
  load_configuration
  
  # Load provider based on configuration
  if ! load_provider "$PROVIDER"; then
    log_error "Failed to load provider, exiting"
    exit 1
  fi
  
  log "Runner Name: $RUNNER_NAME"
  log "Instance ID: $INSTANCE_ID"
  log "Region: $REGION"
  log "Provider: $PROVIDER"
  log "Idle Timeout: $IDLE_TIMEOUT minutes"
  log "Check Interval: $CHECK_INTERVAL seconds"
  log ""
  
  # Set up signal handlers
  trap shutdown_handler SIGTERM SIGINT
  
  # Report initial state
  report_metric "runner.started" 1
  publish_event "lifecycle_service_started" "{}"
  
  # Main monitoring loop
  while true; do
    if is_runner_idle; then
      idle_minutes=$(get_idle_time)
      handle_idle_timeout $idle_minutes
    else
      # Report active state
      report_metric "runner.active" 1
      
      # Clear idle state when runner becomes active
      local state_file="/var/run/github-runner/idle_since"
      if [ -f "$state_file" ]; then
        rm -f "$state_file"
        log "Runner became active, cleared idle state"
      fi
    fi
    
    sleep $CHECK_INTERVAL
  done
}

# Run main function unless being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
