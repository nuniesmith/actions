#!/bin/bash
set -euo pipefail

# SSH connection waiting script
# Usage: ./wait-for-ssh.sh <server_ip>

SERVER_IP="${1:-}"

if [[ -z "$SERVER_IP" ]]; then
  echo "❌ Server IP not provided"
  exit 1
fi

echo "⏳ Waiting for SSH access to $SERVER_IP..."

SSH_READY=false

# First, test basic connectivity
echo "🔍 Testing basic connectivity to port 22..."
for i in {1..10}; do
  if timeout 5 nc -zv $SERVER_IP 22 2>/dev/null; then
    echo "✅ Port 22 is reachable on attempt $i"
    break
  fi
  echo "Port 22 not ready, waiting 10 seconds..."
  sleep 10
done

# Test SSH with detailed error output
echo "🔑 Testing SSH connection with private key..."

for i in {1..15}; do
  echo "Attempt $i/15: Testing SSH connection..."
  
  # Use the generated private key for authentication
  SSH_OUTPUT=$(timeout 10 ssh -i ~/.ssh/linode_deployment_key -v -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o ConnectionAttempts=1 \
     root@$SERVER_IP "echo 'SSH ready'" 2>&1 || echo "SSH_FAILED")
  
  if echo "$SSH_OUTPUT" | grep -q "SSH ready"; then
    echo "✅ SSH ready after $i attempts"
    SSH_READY=true
    break
  else
    echo "SSH failed. Last few lines of output:"
    echo "$SSH_OUTPUT" | tail -3
  fi
  
  echo "Waiting 15 seconds before next attempt..."
  sleep 15
done

if [[ "$SSH_READY" != "true" ]]; then
  echo "❌ SSH failed to become ready after 15 attempts (3.75 minutes)"
  echo "🔍 Debugging SSH connection..."
  
  # Try to get more info about why SSH is failing
  echo "Testing basic connectivity..."
  timeout 5 nc -zv $SERVER_IP 22 || echo "Port 22 not reachable"
  
  exit 1
fi

echo "✅ SSH connection established successfully"
