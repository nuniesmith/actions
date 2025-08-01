#!/biecho "📦 I#!/bin/bash
set -euo pipefail

echo "🚀 Stage 2: Post-reboot setup starting..."

echo "📦 Installing firewall packages after reboot..."
# First, remove old iptables if it exists to avoid conflicts
echo "🔧 Resolving iptables conflicts..."
pacman -Rdd --noconfirm iptables 2>/dev/null || true

# Now install iptables-nft, ufw, and jq (for DNS updates)
if ! pacman -S --noconfirm iptables-nft ufw jq; then
  echo "⚠️ First attempt failed, trying individually..."
  pacman -S --noconfirm iptables-nft || echo "Failed to install iptables-nft"
  pacman -S --noconfirm ufw || echo "Failed to install ufw"
  pacman -S --noconfirm jq || echo "Failed to install jq"
fiirewall packages after reboot..."
# First, remove old iptables if it exists to avoid conflicts
echo "� Resolving iptables conflicts..."
pacman -Rdd --noconfirm iptables 2>/dev/null || true

# Now install iptables-nft, ufw, and jq (for DNS updates)
if ! pacman -S --noconfirm iptables-nft ufw jq; then
  echo "⚠️ First attempt failed, trying individually..."
  pacman -S --noconfirm iptables-nft || echo "Failed to install iptables-nft"
  pacman -S --noconfirm ufw || echo "Failed to install ufw"
  pacman -S --noconfirm jq || echo "Failed to install jq"
fi-euo pipefail

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
for i in {1..15}; do
  if systemctl is-active tailscaled >/dev/null 2>&1; then
    echo "✅ Tailscaled daemon is active"
    break
  fi
  echo "Attempt $i/15: Waiting for tailscaled..."
  sleep 3
done

# Get the auth key (should be replaced by the workflow)
AUTH_KEY="TAILSCALE_AUTH_KEY_PLACEHOLDER"
SERVICE_NAME="SERVICE_NAME_PLACEHOLDER"

# Validate that placeholders were replaced
if [[ "$AUTH_KEY" == "TAILSCALE_AUTH_KEY_PLACEHOLDER" ]]; then
  echo "❌ TAILSCALE_AUTH_KEY placeholder was not replaced!"
  exit 1
fi

if [[ "$SERVICE_NAME" == "SERVICE_NAME_PLACEHOLDER" ]]; then
  echo "❌ SERVICE_NAME placeholder was not replaced!"
  exit 1
fi

if [[ -z "$AUTH_KEY" ]]; then
  echo "❌ TAILSCALE_AUTH_KEY is empty"
  exit 1
fi

echo "🔗 Authenticating with Tailscale..."
echo "Using hostname: $SERVICE_NAME"

TAILSCALE_CONNECTED=false
DOCKER_SUBNETS="172.17.0.0/16,172.20.0.0/16,172.21.0.0/16,172.22.0.0/16"

# First attempt: Full configuration with Docker subnets
echo "🌐 Attempting Tailscale connection with Docker subnet advertisement..."
if timeout 300 tailscale up --authkey="$AUTH_KEY" --hostname="$SERVICE_NAME" --accept-routes --advertise-routes="$DOCKER_SUBNETS" --reset; then
  TAILSCALE_CONNECTED=true
  echo "✅ Tailscale connected with Docker subnets advertised"
else
  echo "⚠️ Full configuration failed, trying basic connection..."
  # Second attempt: Basic connection without subnet advertisement
  if timeout 300 tailscale up --authkey="$AUTH_KEY" --hostname="$SERVICE_NAME" --accept-routes --reset; then
    TAILSCALE_CONNECTED=true
    echo "✅ Tailscale connected with basic configuration"
    
    # Try to add subnet advertisement after connection
    echo "🔄 Attempting to add Docker subnet advertisement..."
    sleep 10
    if timeout 60 tailscale up --advertise-routes="$DOCKER_SUBNETS"; then
      echo "✅ Docker subnets advertised successfully"
    else
      echo "⚠️ Failed to advertise Docker subnets, but connection is established"
    fi
  else
    echo "❌ Tailscale connection failed completely"
    echo "🔍 Checking tailscale logs..."
    journalctl -u tailscaled --no-pager -l --since="5 minutes ago" || true
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
  
  # Update Cloudflare DNS records with Tailscale IP
  if [[ "$TAILSCALE_IP" != "pending" && -n "$TAILSCALE_IP" ]]; then
    echo "🌐 Updating Cloudflare DNS records with Tailscale IP..."
    
    # These will be replaced by the workflow
    CLOUDFLARE_EMAIL="CLOUDFLARE_EMAIL_PLACEHOLDER"
    CLOUDFLARE_API_TOKEN="CLOUDFLARE_API_TOKEN_PLACEHOLDER"
    FULL_DOMAIN_NAME="DOMAIN_NAME_PLACEHOLDER"
    
    # Extract base domain (e.g., from "nginx.example.com" get "example.com")
    DOMAIN_NAME=$(echo "$FULL_DOMAIN_NAME" | awk -F. '{if(NF>=2) print $(NF-1)"."$NF; else print $0}')
    
    # Validate that placeholders were replaced
    if [[ "$CLOUDFLARE_EMAIL" != "CLOUDFLARE_EMAIL_PLACEHOLDER" && "$CLOUDFLARE_API_TOKEN" != "CLOUDFLARE_API_TOKEN_PLACEHOLDER" && "$FULL_DOMAIN_NAME" != "DOMAIN_NAME_PLACEHOLDER" ]]; then
      
      echo "🔍 Using domain: $DOMAIN_NAME for zone lookup"
      echo "🔍 Full domain to update: $FULL_DOMAIN_NAME"
      
      # Get the zone ID for the domain
      ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN_NAME" \
        -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")
      
      ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r '.result[0].id // empty' 2>/dev/null || echo "")
      
      if [[ -n "$ZONE_ID" && "$ZONE_ID" != "null" && "$ZONE_ID" != "empty" ]]; then
        echo "✅ Found Cloudflare zone ID: $ZONE_ID"
        
        # Update A record for the full domain (e.g., nginx.example.com)
        RECORD_NAME="$FULL_DOMAIN_NAME"
        
        echo "🔄 Updating DNS record for $RECORD_NAME..."
        
        # Check if record exists
        RECORD_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$RECORD_NAME&type=A" \
          -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
          -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
          -H "Content-Type: application/json")
        
        RECORD_ID=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].id // empty' 2>/dev/null || echo "")
        
        if [[ -n "$RECORD_ID" && "$RECORD_ID" != "null" && "$RECORD_ID" != "empty" ]]; then
          # Update existing record
          UPDATE_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
            -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$TAILSCALE_IP\",\"ttl\":120}")
          
          if echo "$UPDATE_RESPONSE" | jq -e '.success' >/dev/null 2>&1; then
            echo "✅ Updated DNS record $RECORD_NAME -> $TAILSCALE_IP"
          else
            echo "⚠️ Failed to update DNS record for $RECORD_NAME"
            echo "Response: $(echo "$UPDATE_RESPONSE" | jq '.errors // empty' 2>/dev/null || echo "$UPDATE_RESPONSE")"
          fi
        else
          # Create new record
          CREATE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"$RECORD_NAME\",\"content\":\"$TAILSCALE_IP\",\"ttl\":120}")
          
          if echo "$CREATE_RESPONSE" | jq -e '.success' >/dev/null 2>&1; then
            echo "✅ Created DNS record $RECORD_NAME -> $TAILSCALE_IP"
          else
            echo "⚠️ Failed to create DNS record for $RECORD_NAME"
            echo "Response: $(echo "$CREATE_RESPONSE" | jq '.errors // empty' 2>/dev/null || echo "$CREATE_RESPONSE")"
          fi
        fi
        
        echo "✅ Cloudflare DNS update completed"
      else
        echo "⚠️ Could not find Cloudflare zone for domain: $DOMAIN_NAME"
        echo "Zone response: $ZONE_RESPONSE"
      fi
    else
      echo "ℹ️ Cloudflare credentials not configured - skipping DNS update"
      echo "Email configured: $([[ "$CLOUDFLARE_EMAIL" != "CLOUDFLARE_EMAIL_PLACEHOLDER" ]] && echo "YES" || echo "NO")"
      echo "Token configured: $([[ "$CLOUDFLARE_API_TOKEN" != "CLOUDFLARE_API_TOKEN_PLACEHOLDER" ]] && echo "YES" || echo "NO")"
      echo "Domain configured: $([[ "$FULL_DOMAIN_NAME" != "DOMAIN_NAME_PLACEHOLDER" ]] && echo "YES ($FULL_DOMAIN_NAME)" || echo "NO")"
    fi
  else
    echo "⚠️ Tailscale IP not available - skipping DNS update"
  fi
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
id "${SERVICE_NAME}_user" || echo "⚠️ Service user ${SERVICE_NAME}_user not found"

echo "📊 Tailscale status summary..."
if [[ "$TAILSCALE_CONNECTED" == "true" ]]; then
  echo "🔗 Tailscale Status:"
  tailscale status --self || echo "⚠️ Could not get tailscale status"
  echo ""
  echo "🌐 Advertised Routes:"
  tailscale status --peers=false --self | grep -E "(advertised|routes)" || echo "⚠️ No route information available"
fi

echo "✅ Stage 2 complete - server ready for service deployment"
