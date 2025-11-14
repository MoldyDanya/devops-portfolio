#!/bin/bash
# Generic provider for GitHub Runner Lifecycle Management
# Works on any Linux server without cloud-specific dependencies

# Provider initialization
provider_init() {
  log "Using generic provider (works on any Linux server)"
  
  # Get instance identifier (hostname by default)
  INSTANCE_ID=${INSTANCE_ID:-$(hostname)}
  REGION=${REGION:-"local"}
  
  log "Instance ID: $INSTANCE_ID"
  log "Region: $REGION"
}

# Stop instance - uses system shutdown command
provider_stop_instance() {
  local idle_minutes=$1
  local threshold=$2
  
  log "Idle timeout reached (${idle_minutes} minutes), stopping instance"
  
  # Use custom stop command if configured, otherwise use shutdown
  local stop_command=${STOP_COMMAND:-"shutdown -h now"}
  
  if [ -n "$STOP_COMMAND" ]; then
    log "Executing custom stop command: $stop_command"
    eval "$stop_command"
  else
    log "Executing system shutdown"
    shutdown -h now
  fi
}

# Publish lifecycle event - uses custom hook script if configured
provider_publish_event() {
  local event=$1
  local data=$2
  
  # If event hook script is configured, call it
  if [ -n "$EVENT_HOOK_SCRIPT" ] && [ -f "$EVENT_HOOK_SCRIPT" ]; then
    log "Publishing event via hook script: $event"
    if bash "$EVENT_HOOK_SCRIPT" "$event" "$data" "$INSTANCE_ID" "$RUNNER_NAME" "$REGION"; then
      log "Event hook executed successfully: $event"
    else
      log_error "Event hook failed: $event"
    fi
  else
    log "Event hook not configured, skipping event: $event"
  fi
}

# Get instance metadata (optional, returns defaults)
provider_get_instance_metadata() {
  echo "{\"instance_id\":\"$INSTANCE_ID\",\"region\":\"$REGION\",\"provider\":\"generic\"}"
}

