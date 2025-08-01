#!/bin/bash
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

# Validate that placeholders were replaced, or try environment variables as fallback
if [[ "$AUTH_KEY" == "TAILSCALE_AUTH_KEY_PLACEHOLDER" ]]; then
  echo "⚠️ TAILSCALE_AUTH_KEY placeholder was not replaced by workflow"
  if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    echo "🔄 Using TAILSCALE_AUTH_KEY from environment variable"
    AUTH_KEY="$TAILSCALE_AUTH_KEY"
  else
    echo "❌ TAILSCALE_AUTH_KEY not available in environment either!"
    echo "🔍 Available environment variables starting with TAILSCALE:"
    env | grep -i tailscale || echo "None found"
    echo "🔍 Checking for auth key file..."
    if [[ -f "/root/tailscale_auth_key" ]]; then
      AUTH_KEY=$(cat /root/tailscale_auth_key)
      echo "✅ Found auth key in file"
    else
      echo "❌ No auth key file found either"
      exit 1
    fi
  fi
fi

if [[ "$SERVICE_NAME" == "SERVICE_NAME_PLACEHOLDER" ]]; then
  echo "⚠️ SERVICE_NAME placeholder was not replaced by workflow"
  if [[ -n "${SERVICE_NAME_ENV:-}" ]]; then
    echo "🔄 Using SERVICE_NAME_ENV from environment variable"
    SERVICE_NAME="$SERVICE_NAME_ENV"
  else
    # Try to get from hostname as fallback
    SERVICE_NAME=$(hostname)
    echo "🔄 Using hostname as service name: $SERVICE_NAME"
  fi
fi

if [[ -z "$AUTH_KEY" ]]; then
  echo "❌ TAILSCALE_AUTH_KEY is empty"
  exit 1
fi

echo "🔗 Authenticating with Tailscale..."
echo "Using hostname: $SERVICE_NAME"

TAILSCALE_CONNECTED=false
DOCKER_SUBNETS="172.17.0.0/16,172.20.0.0/16,172.21.0.0/16,172.22.0.0/16"

# Enhanced connection attempts with better error handling
CONNECTION_METHODS=(
  "full-with-reset"
  "full-no-reset" 
  "basic-with-reset"
  "basic-no-reset"
  "minimal"
)

for method in "${CONNECTION_METHODS[@]}"; do
  echo "🌐 Attempting Tailscale connection method: $method"
  
  case "$method" in
    "full-with-reset")
      if timeout 300 tailscale up --authkey="$AUTH_KEY" --hostname="$SERVICE_NAME" --accept-routes --advertise-routes="$DOCKER_SUBNETS" --reset; then
        TAILSCALE_CONNECTED=true
        echo "✅ Tailscale connected with full configuration and reset"
        break
      fi
      ;;
    "full-no-reset")
      if timeout 300 tailscale up --authkey="$AUTH_KEY" --hostname="$SERVICE_NAME" --accept-routes --advertise-routes="$DOCKER_SUBNETS"; then
        TAILSCALE_CONNECTED=true
        echo "✅ Tailscale connected with full configuration"
        break
      fi
      ;;
    "basic-with-reset")
      if timeout 300 tailscale up --authkey="$AUTH_KEY" --hostname="$SERVICE_NAME" --accept-routes --reset; then
        TAILSCALE_CONNECTED=true
        echo "✅ Tailscale connected with basic configuration and reset"
        
        # Try to add subnet advertisement after connection
        echo "🔄 Attempting to add Docker subnet advertisement..."
        sleep 10
        timeout 60 tailscale up --advertise-routes="$DOCKER_SUBNETS" || echo "⚠️ Failed to advertise subnets, but connection established"
        break
      fi
      ;;
    "basic-no-reset")
      if timeout 300 tailscale up --authkey="$AUTH_KEY" --hostname="$SERVICE_NAME" --accept-routes; then
        TAILSCALE_CONNECTED=true
        echo "✅ Tailscale connected with basic configuration"
        
        # Try to add subnet advertisement after connection
        echo "🔄 Attempting to add Docker subnet advertisement..."
        sleep 10
        timeout 60 tailscale up --advertise-routes="$DOCKER_SUBNETS" || echo "⚠️ Failed to advertise subnets, but connection established"
        break
      fi
      ;;
    "minimal")
      if timeout 300 tailscale up --authkey="$AUTH_KEY"; then
        TAILSCALE_CONNECTED=true
        echo "✅ Tailscale connected with minimal configuration"
        echo "⚠️ No route acceptance or subnet advertisement - manual configuration may be needed"
        break
      fi
      ;;
  esac
  
  echo "⚠️ Method $method failed, trying next approach..."
  sleep 10
done

if [[ "$TAILSCALE_CONNECTED" != "true" ]]; then
  echo "❌ All Tailscale connection methods failed"
  echo "🔍 Checking tailscale logs..."
  journalctl -u tailscaled --no-pager -l --since="10 minutes ago" || true
  echo "🔍 Tailscale status output:"
  tailscale status || true
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
    
    # Validate that placeholders were replaced (allow empty for optional Cloudflare config)
    CLOUDFLARE_CONFIGURED="false"
    if [[ "$CLOUDFLARE_EMAIL" != "CLOUDFLARE_EMAIL_PLACEHOLDER" && "$CLOUDFLARE_API_TOKEN" != "CLOUDFLARE_API_TOKEN_PLACEHOLDER" && "$FULL_DOMAIN_NAME" != "DOMAIN_NAME_PLACEHOLDER" ]]; then
      if [[ -n "$CLOUDFLARE_EMAIL" && -n "$CLOUDFLARE_API_TOKEN" && -n "$FULL_DOMAIN_NAME" ]]; then
        CLOUDFLARE_CONFIGURED="true"
        echo "✅ Cloudflare DNS configuration detected"
      else
        echo "⚠️ Cloudflare secrets present but some are empty"
      fi
    else
      echo "ℹ️ Cloudflare DNS not configured - skipping DNS updates"
    fi
    
    if [[ "$CLOUDFLARE_CONFIGURED" == "true" ]]; then
      # Extract base domain (e.g., from "nginx.example.com" get "example.com")
      DOMAIN_NAME=$(echo "$FULL_DOMAIN_NAME" | awk -F. '{if(NF>=2) print $(NF-1)"."$NF; else print $0}')
      
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
        
        # Function to update a single DNS record
        update_dns_record() {
          local record_name="$1"
          local ip_address="$2"
          
          echo "🔄 Updating DNS record for $record_name..."
          
          # Check if record exists
          local record_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$record_name&type=A" \
            -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json")
          
          local record_id=$(echo "$record_response" | jq -r '.result[0].id // empty' 2>/dev/null || echo "")
          
          if [[ -n "$record_id" && "$record_id" != "null" && "$record_id" != "empty" ]]; then
            # Update existing record
            local update_response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
              -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
              -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
              -H "Content-Type: application/json" \
              --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip_address\",\"ttl\":120}")
            
            if echo "$update_response" | jq -e '.success' >/dev/null 2>&1; then
              echo "✅ Updated DNS record $record_name -> $ip_address"
              return 0
            else
              echo "⚠️ Failed to update DNS record for $record_name"
              echo "Response: $(echo "$update_response" | jq '.errors // empty' 2>/dev/null || echo "$update_response")"
              return 1
            fi
          else
            # Create new record
            local create_response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
              -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
              -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
              -H "Content-Type: application/json" \
              --data "{\"type\":\"A\",\"name\":\"$record_name\",\"content\":\"$ip_address\",\"ttl\":120}")
            
            if echo "$create_response" | jq -e '.success' >/dev/null 2>&1; then
              echo "✅ Created DNS record $record_name -> $ip_address"
              return 0
            else
              echo "⚠️ Failed to create DNS record for $record_name"
              echo "Response: $(echo "$create_response" | jq '.errors // empty' 2>/dev/null || echo "$create_response")"
              return 1
            fi
          fi
        }
        
        # Define DNS records to update based on service
        declare -a dns_records
        
        if [[ "$SERVICE_NAME" == "nginx" ]]; then
          # Nginx service - update all proxy-related records (excluding ATS and server-specific records)
          dns_records=(
            # Core nginx service
            "$FULL_DOMAIN_NAME"           # nginx.7gram.xyz
            
            # Root domain and www
            "$DOMAIN_NAME"                # 7gram.xyz (root domain)
            "www.$DOMAIN_NAME"            # www.7gram.xyz
            
            # Wildcard and admin
            "*.$DOMAIN_NAME"              # *.7gram.xyz (wildcard)
            "admin.$DOMAIN_NAME"          # admin.7gram.xyz
            
            # Authentication & API
            "auth.$DOMAIN_NAME"           # auth.7gram.xyz
            "api.$DOMAIN_NAME"            # api.7gram.xyz
            
            # Media streaming services
            "emby.$DOMAIN_NAME"           # emby.7gram.xyz
            "jellyfin.$DOMAIN_NAME"       # jellyfin.7gram.xyz
            "plex.$DOMAIN_NAME"           # plex.7gram.xyz
            "music.$DOMAIN_NAME"          # music.7gram.xyz
            "youtube.$DOMAIN_NAME"        # youtube.7gram.xyz
            
            # File management & productivity
            "nc.$DOMAIN_NAME"             # nc.7gram.xyz (nextcloud)
            "calibre.$DOMAIN_NAME"        # calibre.7gram.xyz
            "calibreweb.$DOMAIN_NAME"     # calibreweb.7gram.xyz
            "abs.$DOMAIN_NAME"            # abs.7gram.xyz (audiobookshelf)
            "audiobooks.$DOMAIN_NAME"     # audiobooks.7gram.xyz
            "ebooks.$DOMAIN_NAME"         # ebooks.7gram.xyz
            "duplicati.$DOMAIN_NAME"      # duplicati.7gram.xyz
            "filebot.$DOMAIN_NAME"        # filebot.7gram.xyz
            
            # Home management
            "mealie.$DOMAIN_NAME"         # mealie.7gram.xyz
            "grocy.$DOMAIN_NAME"          # grocy.7gram.xyz
            "wiki.$DOMAIN_NAME"           # wiki.7gram.xyz
            "home.$DOMAIN_NAME"           # home.7gram.xyz
            
            # AI & development
            "ai.$DOMAIN_NAME"             # ai.7gram.xyz
            "chat.$DOMAIN_NAME"           # chat.7gram.xyz
            "ollama.$DOMAIN_NAME"         # ollama.7gram.xyz
            "sd.$DOMAIN_NAME"             # sd.7gram.xyz (stable diffusion)
            "comfy.$DOMAIN_NAME"          # comfy.7gram.xyz
            "whisper.$DOMAIN_NAME"        # whisper.7gram.xyz
            "code.$DOMAIN_NAME"           # code.7gram.xyz
            
            # Media management (*arr stack)
            "sonarr.$DOMAIN_NAME"         # sonarr.7gram.xyz
            "radarr.$DOMAIN_NAME"         # radarr.7gram.xyz
            "lidarr.$DOMAIN_NAME"         # lidarr.7gram.xyz
            "jackett.$DOMAIN_NAME"        # jackett.7gram.xyz
            "qbt.$DOMAIN_NAME"            # qbt.7gram.xyz (qbittorrent)
            
            # Infrastructure & monitoring
            "pihole.$DOMAIN_NAME"         # pihole.7gram.xyz
            "dns.$DOMAIN_NAME"            # dns.7gram.xyz
            "grafana.$DOMAIN_NAME"        # grafana.7gram.xyz
            "prometheus.$DOMAIN_NAME"     # prometheus.7gram.xyz
            "uptime.$DOMAIN_NAME"         # uptime.7gram.xyz
            "watchtower.$DOMAIN_NAME"     # watchtower.7gram.xyz
            "monitor.$DOMAIN_NAME"        # monitor.7gram.xyz
            "nodes.$DOMAIN_NAME"          # nodes.7gram.xyz
            
            # Container management
            "portainer.$DOMAIN_NAME"      # portainer.7gram.xyz
            "portainer-freddy.$DOMAIN_NAME"   # portainer-freddy.7gram.xyz
            "portainer-sullivan.$DOMAIN_NAME" # portainer-sullivan.7gram.xyz
            
            # Mail services
            "mail.$DOMAIN_NAME"           # mail.7gram.xyz
            "smtp.$DOMAIN_NAME"           # smtp.7gram.xyz
            "imap.$DOMAIN_NAME"           # imap.7gram.xyz
            
            # Sync services
            "sync-desktop.$DOMAIN_NAME"   # sync-desktop.7gram.xyz
            "sync-freddy.$DOMAIN_NAME"    # sync-freddy.7gram.xyz
            "sync-oryx.$DOMAIN_NAME"      # sync-oryx.7gram.xyz
            "sync-sullivan.$DOMAIN_NAME"  # sync-sullivan.7gram.xyz
            
            # Utility & status
            "status.$DOMAIN_NAME"         # status.7gram.xyz
            "vpn.$DOMAIN_NAME"            # vpn.7gram.xyz
            "remote.$DOMAIN_NAME"         # remote.7gram.xyz
            
            # FKS Trading (legacy support)
            "fkstrading.xyz.$DOMAIN_NAME" # fkstrading.xyz.7gram.xyz
          )
          echo "🌐 Updating ${#dns_records[@]} DNS records for nginx service..."
          echo "ℹ️ Excluded from updates:"
          echo "   - ats.7gram.xyz (ATS Game Server)"
          echo "   - api.ats.7gram.xyz (ATS API)"
          echo "   - www.ats.7gram.xyz (ATS Web)"
          echo "   - freddy.7gram.xyz (Home automation server)"
          echo "   - sullivan.7gram.xyz (Main media server)"
        elif [[ "$SERVICE_NAME" == "fks" ]]; then
          # FKS service - update FKS-related records
          dns_records=(
            "$FULL_DOMAIN_NAME"           # fks.7gram.xyz
            "api.$DOMAIN_NAME"            # api.7gram.xyz
            "auth.$DOMAIN_NAME"           # auth.7gram.xyz
            "trading.$DOMAIN_NAME"        # trading.7gram.xyz
            "data.$DOMAIN_NAME"           # data.7gram.xyz
          )
          echo "🌐 Updating ${#dns_records[@]} DNS records for FKS service..."
        else
          # Other services - just update the main record
          dns_records=("$FULL_DOMAIN_NAME")
          echo "🌐 Updating main DNS record for $SERVICE_NAME service..."
        fi
        
        # Update all defined DNS records
        local success_count=0
        local total_count=${#dns_records[@]}
        
        for record in "${dns_records[@]}"; do
          if update_dns_record "$record" "$TAILSCALE_IP"; then
            success_count=$((success_count + 1))
          fi
          sleep 1  # Rate limiting for Cloudflare API
        done
        
        echo "📊 DNS update summary: $success_count/$total_count records updated successfully"
        
        # Verify and update server-specific records if needed
        echo "🔍 Verifying server-specific DNS records..."
        
        # Verify and update server-specific records if needed
        echo "🔍 Verifying server-specific DNS records..."
        
        # Function to get Tailscale IP for a hostname
        get_tailscale_peer_ip() {
          local hostname="$1"
          # Try to get the IP from tailscale status
          local peer_ip=$(tailscale status --json 2>/dev/null | jq -r --arg hostname "$hostname" '.Peer[] | select(.HostName == $hostname) | .TailscaleIPs[0] // empty' 2>/dev/null || echo "")
          
          if [[ -n "$peer_ip" && "$peer_ip" != "empty" && "$peer_ip" != "null" ]]; then
            echo "$peer_ip"
          else
            # Fallback to known static IPs if peer is not currently online
            case "$hostname" in
              "freddy")
                echo "100.121.199.80"
                ;;
              "sullivan")
                echo "100.86.22.59"
                ;;
              *)
                echo ""
                ;;
            esac
          fi
        }
        
        # Function to check and update server DNS if needed
        check_server_dns() {
          local server_name="$1"
          local record_name="${server_name}.$DOMAIN_NAME"
          
          echo "🔍 Checking $record_name..."
          
          # Get expected IP (from Tailscale network or fallback)
          local expected_ip=$(get_tailscale_peer_ip "$server_name")
          
          if [[ -z "$expected_ip" ]]; then
            echo "⚠️ Could not determine expected IP for $server_name"
            return
          fi
          
          # Get current DNS record
          local current_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$record_name&type=A" \
            -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json")
          
          local current_ip=$(echo "$current_record" | jq -r '.result[0].content // empty' 2>/dev/null || echo "")
          
          if [[ -n "$current_ip" && "$current_ip" != "empty" ]]; then
            if [[ "$current_ip" == "$expected_ip" ]]; then
              echo "✅ $record_name correctly points to $current_ip"
            else
              echo "⚠️ $record_name points to $current_ip but should point to $expected_ip"
              echo "🔄 Updating $record_name to correct Tailscale IP..."
              if update_dns_record "$record_name" "$expected_ip"; then
                echo "✅ Updated $record_name to correct IP: $expected_ip"
              else
                echo "❌ Failed to update $record_name"
              fi
            fi
          else
            echo "⚠️ $record_name not found in DNS"
            echo "🔄 Creating $record_name with Tailscale IP..."
            if update_dns_record "$record_name" "$expected_ip"; then
              echo "✅ Created $record_name with IP: $expected_ip"
            else
              echo "❌ Failed to create $record_name"
            fi
          fi
        }
        
        # Check freddy server (Home automation server)
        check_server_dns "freddy"
        
        # Check sullivan server (Main media server)  
        check_server_dns "sullivan"
        
        echo "✅ Server DNS verification completed"
        
        # Final DNS verification summary
        echo "📋 DNS Status Summary:"
        echo "======================"
        
        # Check key records for a final summary
        key_records=("$FULL_DOMAIN_NAME" "www.$DOMAIN_NAME" "$DOMAIN_NAME" "freddy.$DOMAIN_NAME" "sullivan.$DOMAIN_NAME")
        
        for record in "${key_records[@]}"; do
          local record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$record&type=A" \
            -H "X-Auth-Email: $CLOUDFLARE_EMAIL" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json")
          
          local record_ip=$(echo "$record_info" | jq -r '.result[0].content // "NOT_FOUND"' 2>/dev/null || echo "ERROR")
          printf "%-25s -> %s\n" "$record" "$record_ip"
        done
        
        echo "======================"
        echo "✅ Cloudflare DNS update completed"
      else
        echo "⚠️ Could not find Cloudflare zone for domain: $DOMAIN_NAME"
        echo "Zone response: $ZONE_RESPONSE"
      fi
    else
      echo "ℹ️ Cloudflare DNS updates skipped - not configured or missing credentials"
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
