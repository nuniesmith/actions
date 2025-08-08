#!/bin/bash
set -euo pipefail

echo "🏗️ Starting Stage 1 complete setup..."

# Arch Linux package update and installation
echo "📦 Updating package database..."
pacman -Sy

echo "📦 Installing essential packages..."
# Install core packages first (without iptables to avoid conflicts)
CORE_PACKAGES="curl wget git openssh docker docker-compose tailscale base-devel"

for attempt in {1..3}; do
  echo "Package install attempt $attempt..."
  if timeout 300 pacman -S --noconfirm $CORE_PACKAGES; then
    echo "✅ Essential packages installed successfully"
    INSTALL_SUCCESS=true
    break
  else
    echo "⚠️ Package install attempt $attempt failed, retrying..."
    rm -f /var/lib/pacman/db.lck || true
    sleep 10
  fi
done

if [[ "${INSTALL_SUCCESS:-false}" != "true" ]]; then
  echo "❌ Failed to install essential packages after 3 attempts"
  echo "🔄 Trying to install packages individually..."
  for pkg in $CORE_PACKAGES; do
    echo "Installing $pkg..."
    timeout 120 pacman -S --noconfirm "$pkg" || echo "⚠️ Failed to install $pkg, continuing..."
  done
fi

echo "🔥 Handling iptables conflict (will be resolved in Stage 2 after reboot)..."
# Remove conflicting iptables package and install iptables-nft after reboot
# This avoids the interactive prompt during stage1
echo "ℹ️ Deferring iptables-nft and ufw installation to Stage 2 (post-reboot)"

echo "🐳 Setting up Docker and networks..."
systemctl enable docker
systemctl start docker
sleep 5

echo "🔧 Applying Docker iptables fix for Arch Linux..."
# Create the fix-docker-iptables.sh script inline
cat > /tmp/fix-docker-iptables.sh << 'DOCKERFIX_EOF'
#!/bin/bash
set -euo pipefail

echo "🔧 Docker iptables Fix for Arch Linux"
echo "======================================"

# Function to stop Docker safely
stop_docker() {
    echo "🛑 Stopping Docker services..."
    systemctl stop docker.socket || true
    systemctl stop docker.service || true
    sleep 3
}

# Function to clean up existing iptables rules
cleanup_iptables() {
    echo "🧹 Cleaning up existing Docker iptables rules..."
    
    # Remove Docker chains if they exist
    iptables -t nat -F DOCKER 2>/dev/null || true
    iptables -t filter -F DOCKER 2>/dev/null || true
    iptables -t filter -F DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
    iptables -t filter -F DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
    iptables -t filter -F DOCKER-USER 2>/dev/null || true
    iptables -t filter -F DOCKER-CT 2>/dev/null || true
    
    # Delete Docker chains
    iptables -t nat -X DOCKER 2>/dev/null || true
    iptables -t filter -X DOCKER 2>/dev/null || true
    iptables -t filter -X DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
    iptables -t filter -X DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
    iptables -t filter -X DOCKER-USER 2>/dev/null || true
    iptables -t filter -X DOCKER-CT 2>/dev/null || true
    
    echo "✅ iptables cleanup completed"
}

# Function to create required iptables chains
create_docker_chains() {
    echo "🔗 Creating required Docker iptables chains..."
    
    # Create NAT chains
    iptables -t nat -N DOCKER 2>/dev/null || true
    
    # Create FILTER chains
    iptables -t filter -N DOCKER 2>/dev/null || true
    iptables -t filter -N DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
    iptables -t filter -N DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
    iptables -t filter -N DOCKER-USER 2>/dev/null || true
    
    # Create the DOCKER-CT chain that was missing
    iptables -t filter -N DOCKER-CT 2>/dev/null || true
    
    # Set up basic rules for Docker chains
    iptables -t filter -A DOCKER-USER -j RETURN 2>/dev/null || true
    iptables -t filter -A DOCKER-ISOLATION-STAGE-1 -j RETURN 2>/dev/null || true
    iptables -t filter -A DOCKER-ISOLATION-STAGE-2 -j RETURN 2>/dev/null || true
    
    echo "✅ Docker iptables chains created"
}

# Function to set up Docker forwarding rules
setup_docker_forwarding() {
    echo "📡 Setting up Docker forwarding rules..."
    
    # Set up the chain rules that Docker expects
    iptables -t nat -C PREROUTING -m addrtype --dst-type LOCAL -j DOCKER 2>/dev/null || \
      iptables -t nat -I PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
    
    iptables -t nat -C OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER 2>/dev/null || \
      iptables -t nat -I OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER
    
    iptables -t filter -C FORWARD -j DOCKER-USER 2>/dev/null || \
      iptables -t filter -I FORWARD -j DOCKER-USER
    
    iptables -t filter -C FORWARD -j DOCKER-ISOLATION-STAGE-1 2>/dev/null || \
      iptables -t filter -I FORWARD -j DOCKER-ISOLATION-STAGE-1
    
    echo "✅ Docker forwarding rules configured"
}

# Function to restart Docker
restart_docker() {
    echo "🐳 Starting Docker services..."
    systemctl start docker.service
    
    # Wait for Docker to be ready
    echo "⏳ Waiting for Docker to be ready..."
    for i in {1..15}; do
        if docker info >/dev/null 2>&1; then
            echo "✅ Docker is ready"
            return 0
        fi
        sleep 2
    done
    
    echo "⚠️ Docker may not be fully ready yet"
}

# Function to test Docker networking
test_docker_networking() {
    echo "🧪 Testing Docker networking..."
    
    # Try to create a test network
    TEST_NETWORK="test-fix-$(date +%s)"
    if docker network create "$TEST_NETWORK" >/dev/null 2>&1; then
        echo "✅ Docker network creation successful"
        docker network rm "$TEST_NETWORK" >/dev/null 2>&1
    else
        echo "⚠️ Docker network creation still has issues"
        return 1
    fi
}

# Main execution for stage1
echo "🚀 Applying Docker iptables fix during stage1..."
stop_docker
cleanup_iptables
create_docker_chains  
setup_docker_forwarding
restart_docker

if test_docker_networking; then
    echo "✅ Docker iptables fix applied successfully during stage1"
else
    echo "⚠️ Docker networking test failed - may need reboot to complete"
fi
DOCKERFIX_EOF

chmod +x /tmp/fix-docker-iptables.sh
/tmp/fix-docker-iptables.sh || echo "⚠️ Docker fix script completed with warnings - will retry after reboot"

# Docker networks will be created in stage2 post-reboot
echo "🔧 Docker network creation deferred to stage2 post-reboot..."

systemctl stop docker

echo "👥 Creating users..."
useradd -m -s /bin/bash jordan || true
echo "jordan:JORDAN_PASSWORD_PLACEHOLDER" | chpasswd
usermod -aG wheel,docker jordan

useradd -m -s /bin/bash actions_user || true
echo "actions_user:ACTIONS_USER_PASSWORD_PLACEHOLDER" | chpasswd
usermod -aG wheel,docker actions_user

useradd -m -s /bin/bash SERVICE_NAME_PLACEHOLDER_user || true
usermod -aG docker SERVICE_NAME_PLACEHOLDER_user
echo "SERVICE_NAME_PLACEHOLDER_user:ACTIONS_USER_PASSWORD_PLACEHOLDER" | chpasswd

mkdir -p /home/SERVICE_NAME_PLACEHOLDER_user/.ssh
chmod 700 /home/SERVICE_NAME_PLACEHOLDER_user/.ssh
chown SERVICE_NAME_PLACEHOLDER_user:SERVICE_NAME_PLACEHOLDER_user /home/SERVICE_NAME_PLACEHOLDER_user/.ssh

echo "🔐 Configuring SSH..."
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

echo "🏷️ Setting hostname..."
hostnamectl set-hostname "SERVICE_NAME_PLACEHOLDER"

echo "⚙️ Enabling services for post-reboot..."
systemctl enable docker
systemctl enable tailscaled

echo "📝 Creating systemd service for post-reboot setup..."
# Note: The stage2-post-reboot.sh script is uploaded by the workflow with placeholders already replaced
cat > /etc/systemd/system/stage2-setup.service << 'SERVICEEOF'
[Unit]
Description=Stage 2 Post-Reboot Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/stage2-post-reboot.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl enable stage2-setup.service

echo "🔑 Creating backup auth key file for Stage 2..."
# This will be replaced by the workflow with the actual auth key
echo "TAILSCALE_AUTH_KEY_PLACEHOLDER" > /root/tailscale_auth_key
chmod 600 /root/tailscale_auth_key

echo "✅ Stage 1 complete - system ready for reboot"
echo "NEEDS_REBOOT" > /tmp/stage1_status
