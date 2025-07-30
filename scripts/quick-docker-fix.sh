#!/bin/bash

# Quick Docker Network Fix - Run this on the ATS server as root

echo "🔧 Quick Docker Network Fix"
echo "=========================="

# Step 1: Stop Docker
echo "🛑 Stopping Docker service..."
systemctl stop docker
sleep 3

# Step 2: Clean up iptables
echo "🧹 Cleaning up iptables Docker chains..."
iptables -t nat -F DOCKER 2>/dev/null || true
iptables -t filter -F DOCKER 2>/dev/null || true
iptables -t filter -F DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
iptables -t filter -F DOCKER-ISOLATION-STAGE-2 2>/dev/null || true

# Remove chains
iptables -t nat -X DOCKER 2>/dev/null || true
iptables -t filter -X DOCKER 2>/dev/null || true
iptables -t filter -X DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
iptables -t filter -X DOCKER-ISOLATION-STAGE-2 2>/dev/null || true

# Step 3: Remove bridge interfaces
echo "🧹 Removing Docker bridge interfaces..."
for interface in $(ip link show | grep br- | cut -d: -f2 | tr -d ' '); do
    echo "  Removing: $interface"
    ip link delete "$interface" 2>/dev/null || true
done

# Step 4: Clean Docker network data
echo "🧹 Cleaning Docker network data..."
rm -rf /var/lib/docker/network/* 2>/dev/null || true

# Step 5: Restart Docker
echo "🚀 Starting Docker service..."
systemctl start docker
sleep 10

# Step 6: Test
echo "🧪 Testing Docker..."
if docker info >/dev/null 2>&1; then
    echo "✅ Docker is working!"
    
    # Test network creation
    if docker network create test-net >/dev/null 2>&1; then
        echo "✅ Network creation works!"
        docker network rm test-net >/dev/null 2>&1
    else
        echo "❌ Network creation still fails"
    fi
else
    echo "❌ Docker still not working"
fi

echo ""
echo "🎯 Now try: cd /home/ats_user/ats && docker compose up -d"
