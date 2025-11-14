#!/bin/bash
# GitHub Runner Monitoring Setup Script
# Run once during instance provisioning to install and configure monitoring infrastructure
# Supports multiple providers: generic (any server) and aws (AWS EC2)

set -e

# Configuration
CONFIG_FILE="/etc/github-runner/config.json"
LOG_FILE="/var/log/github-runner/setup.log"
RUNNER_DIR=${RUNNER_DIR:-"/opt/actions-runner"}
PROVIDER_DIR="/usr/local/lib/github-runner-lifecycle/providers"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Initialize log file
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

log() {
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  echo -e "${GREEN}[${timestamp}]${NC} $1" | tee -a $LOG_FILE
}

log_warn() {
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  echo -e "${YELLOW}[${timestamp}] WARNING:${NC} $1" | tee -a $LOG_FILE
}

log_error() {
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
  echo -e "${RED}[${timestamp}] ERROR:${NC} $1" | tee -a $LOG_FILE
}

# Check if running as root
check_root() {
  if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root"
    exit 1
  fi
  log "Root access confirmed"
}

# Check dependencies
check_dependencies() {
  log "Checking required dependencies..."
  
  local missing_deps=()
  local required_commands=("curl" "jq" "systemctl" "nc")
  
  for cmd in "${required_commands[@]}"; do
    if ! command -v $cmd &> /dev/null; then
      missing_deps+=($cmd)
    fi
  done
  
  if [ ${#missing_deps[@]} -ne 0 ]; then
    log_error "Missing required dependencies: ${missing_deps[*]}"
    log "Please install: sudo apt-get install -y ${missing_deps[*]}"
    exit 1
  fi
  
  log "All dependencies satisfied"
}

# Install providers
install_providers() {
  log "Installing provider scripts..."
  
  mkdir -p "$PROVIDER_DIR"
  
  # Copy provider scripts
  if [ -d "${SCRIPT_DIR}/providers" ]; then
    cp -r "${SCRIPT_DIR}/providers/"* "$PROVIDER_DIR/"
    chmod +x "$PROVIDER_DIR"/*.sh
    log "Provider scripts installed to $PROVIDER_DIR"
  else
    log_error "Provider directory not found: ${SCRIPT_DIR}/providers"
    return 1
  fi
}

# Install CloudWatch Agent (AWS only, optional)
install_cloudwatch_agent() {
  local provider=$1
  
  if [ "$provider" != "aws" ]; then
    log "CloudWatch Agent not needed for provider: $provider"
    return 0
  fi
  
  log "Installing CloudWatch Agent (AWS provider)..."
  
  if command -v amazon-cloudwatch-agent-ctl &> /dev/null; then
    log "CloudWatch Agent already installed, skipping"
    return 0
  fi
  
  # Check for unzip (needed for AWS CLI installation)
  if ! command -v unzip &> /dev/null; then
    log_warn "unzip not found, installing..."
    apt-get update -qq && apt-get install -y -qq unzip
  fi
  
  # Download and install
  local cw_agent_url="https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
  local temp_file="/tmp/amazon-cloudwatch-agent.deb"
  
  if ! curl -sSf -o "$temp_file" "$cw_agent_url"; then
    log_error "Failed to download CloudWatch Agent"
    return 1
  fi
  
  if ! dpkg -i -E "$temp_file" 2>&1 | tee -a $LOG_FILE; then
    log_error "Failed to install CloudWatch Agent"
    rm -f "$temp_file"
    return 1
  fi
  
  rm -f "$temp_file"
  log "CloudWatch Agent installed successfully"
}

# Configure CloudWatch Agent (AWS only, optional)
configure_cloudwatch_agent() {
  local provider=$1
  
  if [ "$provider" != "aws" ]; then
    log "CloudWatch Agent configuration not needed for provider: $provider"
    return 0
  fi
  
  log "Configuring CloudWatch Agent..."
  
  # Try to get instance ID from AWS metadata or config
  local instance_id="unknown"
  if command -v curl &> /dev/null; then
    instance_id=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
  fi
  
  # Load runner name from config or use hostname
  local runner_name=$(hostname)
  if [ -f "$CONFIG_FILE" ]; then
    runner_name=$(jq -r '.RUNNER_NAME // "'$runner_name'"' $CONFIG_FILE 2>/dev/null || echo "$runner_name")
  fi
  
  local config_dir="/opt/aws/amazon-cloudwatch-agent/etc"
  mkdir -p $config_dir
  
  cat > ${config_dir}/amazon-cloudwatch-agent.json << EOF
{
  "metrics": {
    "namespace": "GitHub/Runners",
    "metrics_collected": {
      "statsd": {
        "service_address": ":8125",
        "metrics_collection_interval": 60,
        "metrics_aggregation_interval": 60
      }
    },
    "append_dimensions": {
      "InstanceId": "${instance_id}",
      "RunnerName": "${runner_name}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/github-runner/lifecycle.log",
            "log_group_name": "/github/runner/lifecycle",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          },
          {
            "file_path": "${RUNNER_DIR}/_diag/Runner_*.log",
            "log_group_name": "/github/runner/diagnostic",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 14
          }
        ]
      }
    }
  }
}
EOF
  
  # Start CloudWatch Agent
  if ! amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:${config_dir}/amazon-cloudwatch-agent.json 2>&1 | tee -a $LOG_FILE; then
    log_error "Failed to start CloudWatch Agent"
    return 1
  fi
  
  log "CloudWatch Agent configured and started"
}

# Install systemd service
install_systemd_service() {
  log "Installing lifecycle monitoring systemd service..."
  
  local service_file="/etc/systemd/system/github-runner-lifecycle.service"
  local script_path="/usr/local/bin/runner-lifecycle-monitor.sh"
  
  # Check if monitor script exists
  if [ ! -f "$script_path" ]; then
    log_error "Monitor script not found at $script_path"
    log "Please ensure runner-lifecycle-monitor.sh is installed first"
    return 1
  fi
  
  # Determine if CloudWatch Agent should be a dependency
  local provider="generic"
  if [ -f "$CONFIG_FILE" ]; then
    provider=$(jq -r '.PROVIDER // "generic"' $CONFIG_FILE 2>/dev/null || echo "generic")
  fi
  
  local after_deps="network.target"
  local wants_deps=""
  if [ "$provider" = "aws" ] && command -v amazon-cloudwatch-agent-ctl &> /dev/null; then
    after_deps="network.target amazon-cloudwatch-agent.service"
    wants_deps="Wants=amazon-cloudwatch-agent.service"
  fi
  
  cat > $service_file << EOF
[Unit]
Description=GitHub Runner Lifecycle Monitoring Service
After=${after_deps}
${wants_deps}

[Service]
Type=simple
User=root
ExecStart=/bin/bash ${script_path}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  
  systemctl daemon-reload
  systemctl enable github-runner-lifecycle.service
  
  log "Systemd service installed and enabled"
}

# Create configuration directory
setup_config() {
  log "Setting up configuration directory..."
  
  local config_dir="/etc/github-runner"
  mkdir -p $config_dir
  
  # Create example config if not exists
  if [ ! -f "$CONFIG_FILE" ]; then
    # Try to detect provider (check if AWS metadata is available)
    local provider="generic"
    if command -v curl &> /dev/null; then
      if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-id &>/dev/null; then
        provider="aws"
        log "Detected AWS environment, using 'aws' provider"
      fi
    fi
    
    cat > $CONFIG_FILE << EOF
{
  "IDLE_TIMEOUT": 30,
  "CHECK_INTERVAL": 60,
  "RUNNER_NAME": "$(hostname)",
  "PROVIDER": "${provider}",
  "RUNNER_DIR": "${RUNNER_DIR}",
  "STOP_COMMAND": "",
  "EVENT_HOOK_SCRIPT": "",
  "INSTANCE_ID": "",
  "REGION": "",
  "SNS_TOPIC_ARN": ""
}
EOF
    log "Created default configuration at $CONFIG_FILE with provider: $provider"
  else
    log "Configuration already exists at $CONFIG_FILE"
  fi
  
  # Set permissions
  chmod 644 $CONFIG_FILE
}

# Main setup function
main() {
  log "========================================"
  log "GitHub Runner Monitoring Setup"
  log "========================================"
  log "Runner Directory: $RUNNER_DIR"
  log ""
  
  check_root
  check_dependencies
  setup_config
  
  # Determine provider from config
  local provider="generic"
  if [ -f "$CONFIG_FILE" ]; then
    provider=$(jq -r '.PROVIDER // "generic"' $CONFIG_FILE 2>/dev/null || echo "generic")
  fi
  
  log "Provider: $provider"
  log ""
  
  install_providers
  install_cloudwatch_agent "$provider"
  configure_cloudwatch_agent "$provider"
  install_systemd_service
  
  log ""
  log "========================================"
  log "Setup completed successfully!"
  log "========================================"
  log "Next steps:"
  log "1. Review configuration at $CONFIG_FILE"
  log "2. Configure provider-specific settings if needed"
  log "3. Start the lifecycle service: systemctl start github-runner-lifecycle"
  log "4. Check status: systemctl status github-runner-lifecycle"
  log ""
}

# Run main function
main
