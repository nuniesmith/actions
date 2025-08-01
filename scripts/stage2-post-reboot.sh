#!/bin/bash
set -euo pipefail

echo "🚀 Stage 2: Post-reboot setup starting..."

echo "📦 Installing firewall packages after reboot..."
# First, remove old iptables if it exists to avoid conflicts
echo "� Resolving iptables conflicts..."
pacman -Rdd --noconfirm iptables 2>/dev/null || true

# Now install iptables-nft and ufw
if ! pacman -S --noconfirm iptables-nft ufw; then
  echo "⚠️ First attempt failed, trying individually..."
  pacman -S --noconfirm iptables-nft || echo "Failed to install iptables-nft"
  pacman -S --noconfirm ufw || echo "Failed to install ufw"
fi

echo "✅ Firewall packages installed successfully"

echo "🔥 Configuring firewall before starting services..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh

echo "🔧 Initializing iptables chains for Docker..."
iptables -t nat -N DOCKER 2>/dev/null || true
iptables -t filter -N DOCKER 2>/dev/null || true
iptables -t filter -N DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
iptables -t filter -N DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
iptables -t filter -N DOCKER-USER 2>/dev/null || true

iptables -t nat -C PREROUTING -m addrtype --dst-type LOCAL -j DOCKER 2>/dev/null || \
  iptables -t nat -I PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
iptables -t nat -C OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER 2>/dev/null || \
  iptables -t nat -I OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER
iptables -t filter -C FORWARD -j DOCKER-USER 2>/dev/null || \
  iptables -t filter -I FORWARD -j DOCKER-USER
iptables -t filter -C FORWARD -j DOCKER-ISOLATION-STAGE-1 2>/dev/null || \
  iptables -t filter -I FORWARD -j DOCKER-ISOLATION-STAGE-1
iptables -t filter -C DOCKER-USER -j RETURN 2>/dev/null || \
  iptables -t filter -A DOCKER-USER -j RETURN

echo "🐳 Starting Docker service..."
systemctl start docker

echo "⏳ Waiting for Docker to be ready..."
for i in {1..10}; do
  if docker info >/dev/null 2>&1; then
    echo "✅ Docker is ready"
    break
  fi
  echo "Attempt $i/10: Waiting for Docker..."
  sleep 5
done

echo "🌐 Recreating Docker networks with static IPs..."
docker network rm fks-network ats-network nginx-network 2>/dev/null || true

docker network create --driver bridge --subnet=172.20.0.0/16 --ip-range=172.20.1.0/24 --gateway=172.20.0.1 fks-network
docker network create --driver bridge --subnet=172.21.0.0/16 --ip-range=172.21.1.0/24 --gateway=172.21.0.1 ats-network
docker network create --driver bridge --subnet=172.22.0.0/16 --ip-range=172.22.1.0/24 --gateway=172.22.0.1 nginx-network

echo "🔧 Configuring iptables rules for Docker networks..."
iptables -I DOCKER-USER -s 172.20.0.0/16 -d 172.21.0.0/16 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -s 172.20.0.0/16 -d 172.22.0.0/16 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -s 172.21.0.0/16 -d 172.20.0.0/16 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -s 172.21.0.0/16 -d 172.22.0.0/16 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -s 172.22.0.0/16 -d 172.20.0.0/16 -j ACCEPT 2>/dev/null || true
iptables -I DOCKER-USER -s 172.22.0.0/16 -d 172.21.0.0/16 -j ACCEPT 2>/dev/null || true

echo "✅ Docker networks configured with static IP ranges"

cat > /opt/docker-networks.conf << 'NETWORKS_EOF'
FKS_NETWORK_NAME="fks-network"
FKS_NETWORK_SUBNET="172.20.0.0/16"
ATS_NETWORK_NAME="ats-network"
ATS_NETWORK_SUBNET="172.21.0.0/16"
NGINX_NETWORK_NAME="nginx-network"
NGINX_NETWORK_SUBNET="172.22.0.0/16"
ALL_DOCKER_SUBNETS="172.17.0.0/16,172.20.0.0/16,172.21.0.0/16,172.22.0.0/16"
NETWORKS_EOF
chmod 644 /opt/docker-networks.conf

echo "🔗 Starting and authenticating Tailscale..."
systemctl start tailscaled

echo "⏳ Waiting for tailscaled daemon to start..."
for i in {1..10}; do
  if systemctl is-active tailscaled >/dev/null 2>&1; then
    echo "✅ Tailscaled daemon is active"
    break
  fi
  echo "Attempt $i/10: Waiting for tailscaled..."
  sleep 3
done

AUTH_KEY="TAILSCALE_AUTH_KEY_PLACEHOLDER"
if [[ -z "$AUTH_KEY" ]]; then
  echo "❌ TAILSCALE_AUTH_KEY is empty"
  exit 1
fi

echo "🔗 Authenticating with Tailscale..."
TAILSCALE_CONNECTED=false
DOCKER_SUBNETS="172.17.0.0/16,172.20.0.0/16,172.21.0.0/16,172.22.0.0/16"

if tailscale up --authkey="$AUTH_KEY" --hostname="SERVICE_NAME_PLACEHOLDER" --accept-routes --advertise-routes="$DOCKER_SUBNETS" --timeout=180s; then
  TAILSCALE_CONNECTED=true
  echo "✅ Tailscale connected with Docker subnets"
else
  echo "⚠️ First attempt failed, trying basic connection..."
  if tailscale up --authkey="$AUTH_KEY" --accept-routes --timeout=180s; then
    TAILSCALE_CONNECTED=true
    echo "✅ Tailscale connected with basic configuration"
  else
    echo "❌ Tailscale connection failed"
  fi
fi

if [[ "$TAILSCALE_CONNECTED" == "true" ]]; then
  echo "⏳ Waiting for Tailscale network to be ready..."
  TAILSCALE_IP="pending"
  
  for i in {1..30}; do
    if tailscale status | grep -q "Logged in"; then
      CURRENT_IP=$(tailscale ip -4 2>/dev/null || echo "")
      if [[ -n "$CURRENT_IP" && "$CURRENT_IP" != "" ]]; then
        TAILSCALE_IP="$CURRENT_IP"
        echo "✅ Tailscale fully connected - IP: $TAILSCALE_IP"
        break
      fi
    fi
    echo "Attempt $i/30: Waiting for Tailscale IP assignment..."
    sleep 10
  done
  
  echo "$TAILSCALE_IP" > /tmp/tailscale_ip
else
  echo "pending" > /tmp/tailscale_ip
fi

echo "🔥 Completing firewall configuration..."
ufw allow in on tailscale0
ufw --force enable

echo "🔐 Configuring SSH for service access..."
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

echo "🔍 Verifying service user configuration..."
id SERVICE_NAME_PLACEHOLDER_user || echo "⚠️ Service user not found"

echo "✅ Stage 2 complete - server ready for service deployment"
