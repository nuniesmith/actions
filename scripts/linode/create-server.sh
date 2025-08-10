#!/bin/bash
set -euo pipefail

# Linode server creation and management script
# Usage: ./create-server.sh <service_name> <server_type> <region> <overwrite>

SERVICE_NAME="${1:-unknown}"
SERVER_TYPE="${2:-g6-standard-2}"
TARGET_REGION="${3:-ca-central}"
OVERWRITE_SERVER="${4:-false}"

echo "🚀 Managing Linode server for $SERVICE_NAME..."

# Install and configure Linode CLI
pip install linode-cli
export LINODE_CLI_TOKEN="${LINODE_CLI_TOKEN}"
linode-cli --version

# If overwrite is enabled, check for and remove existing servers with the same name
if [[ "$OVERWRITE_SERVER" == "true" ]]; then
  echo "🔍 Checking for existing servers to overwrite..."
  EXISTING_SERVERS=$(linode-cli linodes list --text --no-headers | grep "$SERVICE_NAME" || true)
  
  if [[ -n "$EXISTING_SERVERS" ]]; then
    echo "🗑️ Found existing servers to remove:"
    echo "$EXISTING_SERVERS"
    
    # Remove each existing server
    echo "$EXISTING_SERVERS" | while IFS= read -r server_line; do
      if [[ -n "$server_line" ]]; then
        SERVER_ID=$(echo "$server_line" | cut -f1)
        SERVER_LABEL=$(echo "$server_line" | cut -f2)
        echo "🗑️ Removing existing server: $SERVER_ID ($SERVER_LABEL)"
        linode-cli linodes delete "$SERVER_ID" || echo "⚠️ Failed to remove server $SERVER_ID"
      fi
    done
    
    echo "⏳ Waiting for server deletion to complete..."
    sleep 30
  else
    echo "✅ No existing servers found with name pattern '$SERVICE_NAME'"
  fi
fi

# Check if server already exists (unless we just destroyed it or overwrite is enabled)
if [[ "$OVERWRITE_SERVER" != "true" ]]; then
  EXISTING_SERVER=$(linode-cli linodes list --text --no-headers | grep "$SERVICE_NAME" | head -1)
  if [[ -n "$EXISTING_SERVER" ]]; then
    echo "🔍 Debug - Found existing server:"
    echo "$EXISTING_SERVER"
    
    SERVER_ID=$(echo "$EXISTING_SERVER" | cut -f1)
    # Try different columns for IP address
    SERVER_IP_COL4=$(echo "$EXISTING_SERVER" | cut -f4)
    SERVER_IP_COL5=$(echo "$EXISTING_SERVER" | cut -f5)
    SERVER_IP_COL6=$(echo "$EXISTING_SERVER" | cut -f6)
    SERVER_IP_COL7=$(echo "$EXISTING_SERVER" | cut -f7)
    
    echo "IP candidates: Col4='$SERVER_IP_COL4', Col5='$SERVER_IP_COL5', Col6='$SERVER_IP_COL6', Col7='$SERVER_IP_COL7'"
    
    # Use the first valid IP address we find
    for IP in "$SERVER_IP_COL4" "$SERVER_IP_COL5" "$SERVER_IP_COL6" "$SERVER_IP_COL7"; do
      if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        SERVER_IP="$IP"
        break
      fi
    done
    
    if [[ -z "$SERVER_IP" ]]; then
      echo "❌ Could not extract IP address from server info"
      exit 1
    fi
    
    echo "✅ Using existing server: $SERVER_IP (ID: $SERVER_ID)"
    echo "server_ip=$SERVER_IP" >> $GITHUB_OUTPUT
    echo "server_id=$SERVER_ID" >> $GITHUB_OUTPUT
    
    # Create a placeholder SSH key for consistency (will use password auth for existing servers)
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/linode_deployment_key -N "" -C "github-actions-$SERVICE_NAME" 2>/dev/null || true
    SSH_PRIVATE_KEY=$(base64 -w 0 ~/.ssh/linode_deployment_key 2>/dev/null || echo "")
    echo "ssh_private_key=$SSH_PRIVATE_KEY" >> $GITHUB_OUTPUT
    
    exit 0
  fi
fi

# Create new server
SERVER_LABEL="$SERVICE_NAME"
echo "🆕 Creating new server: $SERVER_LABEL"

# Generate SSH key for this deployment
echo "🔑 Generating SSH key for server access..."
ssh-keygen -t ed25519 -a 64 -f ~/.ssh/linode_deployment_key -N "" -C "github-actions-$SERVICE_NAME"

# Get the public key content for server authorization
SSH_PUBLIC_KEY=$(base64 -w 0 ~/.ssh/linode_deployment_key.pub)
echo "🔑 SSH public key generated (ed25519)"

# Store the private key (base64 encoded for safe storage)
SSH_PRIVATE_KEY=$(base64 -w 0 ~/.ssh/linode_deployment_key)
echo "ssh_private_key=$SSH_PRIVATE_KEY" >> $GITHUB_OUTPUT

echo "🚀 Creating server with SSH key authentication..."
echo "Using server type: $SERVER_TYPE"
echo "Using region: $TARGET_REGION"

RESULT=$(linode-cli linodes create \
  --type "$SERVER_TYPE" \
  --region "$TARGET_REGION" \
  --image "linode/arch" \
  --label "$SERVER_LABEL" \
  --root_pass "$SERVICE_ROOT_PASSWORD" \
  --authorized_keys "$SSH_PUBLIC_KEY" \
  --backups_enabled=false \
  --text --no-headers)

echo "🔍 Server creation result:"
echo "$RESULT"

if [[ -z "$RESULT" ]] || [[ "$RESULT" == *"error"* ]] || [[ "$RESULT" == *"Error"* ]]; then
  echo "❌ Server creation failed!"
  echo "Result: $RESULT"
  exit 1
fi

SERVER_ID=$(echo "$RESULT" | cut -f1)

if [[ -z "$SERVER_ID" ]] || [[ ! "$SERVER_ID" =~ ^[0-9]+$ ]]; then
  echo "❌ Invalid server ID extracted: '$SERVER_ID'"
  echo "Full result: $RESULT"
  exit 1
fi

echo "🆔 Server created with ID: $SERVER_ID"

# Wait for server to be running
echo "⏳ Waiting for server to be ready..."
ATTEMPT=0
while true; do
  # Get server info and check status
  SERVER_INFO=$(linode-cli linodes view "$SERVER_ID" --text --no-headers)
  
  # Debug: show the full output on first few attempts
  if [[ $ATTEMPT -lt 3 ]]; then
    echo "🔍 Debug - Server info columns:"
    echo "$SERVER_INFO"
  fi
  
  # Status is in column 6 (ID|Label|Region|Type|Image|Status|IP|Backups)
  STATUS=$(echo "$SERVER_INFO" | cut -f6)
  
  echo "Attempt $((++ATTEMPT)): Status='$STATUS'"
  
  # Check if server is running
  if [[ "$STATUS" == "running" ]]; then
    echo "✅ Server is running!"
    break
  fi
  
  # Don't wait forever for server status
  if [[ $ATTEMPT -gt 15 ]]; then
    echo "⚠️ Server status check timeout - proceeding to SSH test"
    break
  fi
  
  sleep 5  # Check more frequently
done

# Get server IP
SERVER_INFO=$(linode-cli linodes view "$SERVER_ID" --text --no-headers)
echo "🔍 Debug - Server view output:"
echo "$SERVER_INFO"

# Try different columns for IP address
SERVER_IP_COL4=$(echo "$SERVER_INFO" | cut -f4)
SERVER_IP_COL5=$(echo "$SERVER_INFO" | cut -f5)
SERVER_IP_COL6=$(echo "$SERVER_INFO" | cut -f6)
SERVER_IP_COL7=$(echo "$SERVER_INFO" | cut -f7)

echo "IP candidates: Col4='$SERVER_IP_COL4', Col5='$SERVER_IP_COL5', Col6='$SERVER_IP_COL6', Col7='$SERVER_IP_COL7'"

# Use the first valid IP address we find
for IP in "$SERVER_IP_COL4" "$SERVER_IP_COL5" "$SERVER_IP_COL6" "$SERVER_IP_COL7"; do
  if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SERVER_IP="$IP"
    break
  fi
done

if [[ -z "$SERVER_IP" ]]; then
  echo "❌ Could not extract IP address from server info"
  exit 1
fi

echo "✅ Server ready: $SERVER_IP (ID: $SERVER_ID)"

echo "server_ip=$SERVER_IP" >> $GITHUB_OUTPUT
echo "server_id=$SERVER_ID" >> $GITHUB_OUTPUT
