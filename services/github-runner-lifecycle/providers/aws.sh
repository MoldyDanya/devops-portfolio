#!/bin/bash
# AWS provider for GitHub Runner Lifecycle Management
# Provides AWS-specific functionality: EC2 stop, SNS events, CloudWatch metadata

# Provider initialization
provider_init() {
  log "Using AWS provider"
  
  # Try to get instance metadata from AWS
  if command -v curl &> /dev/null; then
    INSTANCE_ID=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "${INSTANCE_ID:-unknown}")
    REGION=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null | sed 's/[a-z]$//' || echo "${REGION:-us-east-1}")
  else
    INSTANCE_ID=${INSTANCE_ID:-"unknown"}
    REGION=${REGION:-"us-east-1"}
  fi
  
  # Check if AWS CLI is available
  if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. AWS provider requires AWS CLI to be installed."
    return 1
  fi
  
  log "Instance ID: $INSTANCE_ID"
  log "Region: $REGION"
}

# Stop instance - uses AWS EC2 API
provider_stop_instance() {
  local idle_minutes=$1
  local threshold=$2
  
  log "Idle timeout reached (${idle_minutes} minutes), stopping EC2 instance"
  
  # Try to stop via AWS CLI
  if [ "$INSTANCE_ID" != "unknown" ] && [ -n "$REGION" ]; then
    log "Stopping EC2 instance $INSTANCE_ID via AWS API"
    
    if aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION" &>/dev/null; then
      log "EC2 stop command sent successfully"
      
      # Give AWS time to process the stop request
      sleep 10
      
      # Check if this is a spot instance (don't force shutdown for spot)
      local instance_lifecycle=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-lifecycle 2>/dev/null || echo "normal")
      
      if [ "$instance_lifecycle" != "spot" ]; then
        log "Forcing shutdown as backup"
        shutdown -h now
      else
        log "Spot instance detected, waiting for termination"
      fi
    else
      log_error "Failed to stop instance via AWS CLI, forcing shutdown"
      shutdown -h now
    fi
  else
    log_error "Invalid instance ID or region, forcing shutdown"
    shutdown -h now
  fi
}

# Publish lifecycle event - uses AWS SNS
provider_publish_event() {
  local event=$1
  local data=$2
  
  if [ -z "$SNS_TOPIC_ARN" ]; then
    log "SNS Topic ARN not configured, skipping event: $event"
    return 0
  fi
  
  local message=$(cat << EOF
{
  "event": "$event",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "instance_id": "$INSTANCE_ID",
  "runner_name": "$RUNNER_NAME",
  "region": "$REGION",
  "data": $data
}
EOF
)
  
  log "Publishing event to SNS: $event"
  
  if aws sns publish \
    --topic-arn "$SNS_TOPIC_ARN" \
    --message "$message" \
    --region "$REGION" &>/dev/null; then
    log "Event published successfully to SNS: $event"
  else
    log_error "Failed to publish event to SNS: $event"
  fi
}

# Get instance metadata from AWS
provider_get_instance_metadata() {
  local metadata="{\"instance_id\":\"$INSTANCE_ID\",\"region\":\"$REGION\",\"provider\":\"aws\""
  
  # Try to get additional metadata
  if command -v curl &> /dev/null; then
    local instance_type=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "")
    local instance_lifecycle=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/instance-lifecycle 2>/dev/null || echo "normal")
    
    if [ -n "$instance_type" ]; then
      metadata="${metadata},\"instance_type\":\"$instance_type\""
    fi
    metadata="${metadata},\"instance_lifecycle\":\"$instance_lifecycle\""
  fi
  
  metadata="${metadata}}"
  echo "$metadata"
}

