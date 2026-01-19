#!/bin/sh
# Multi-Distro Production Server Setup Script
# Supports: Ubuntu/Debian, Fedora/RHEL/CentOS, Arch Linux
#
# Usage:
#   chmod +x setup-prod-server.sh
#   sudo ./setup-prod-server.sh
#
# This script will:
# - Detect the Linux distribution
# - Install minimal production packages
# - Install Docker and container runtime only
# - Apply security hardening
# - Create/configure 'actions' user for CI/CD (SSH key only)
# - Setup SSH with secure configuration
# - Configure firewall basics
# - Optionally run generate-secrets.sh automatically
#
# NOTE: This is a PRODUCTION server setup - no development tools are installed.
#       For development tools (Rust, protobuf, testing), use setup-dev-server.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Log functions
log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*"; }
log_header() {
    printf "\n"
    printf "${BOLD}${CYAN}================================================================================${NC}\n"
    printf "${BOLD}${CYAN}  %s${NC}\n" "$*"
    printf "${BOLD}${CYAN}================================================================================${NC}\n"
    printf "\n"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "Please run this script with sudo"
    exit 1
fi

# =============================================================================
# Detect OS Distribution
# =============================================================================
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_NAME="$PRETTY_NAME"
        DISTRO_VERSION="$VERSION_ID"

        # Handle ID_LIKE for derivatives
        case "$ID" in
            ubuntu|debian|pop|linuxmint|elementary|zorin)
                DISTRO_FAMILY="debian"
                PKG_MANAGER="apt"
                ;;
            fedora|rhel|centos|rocky|alma|nobara)
                DISTRO_FAMILY="fedora"
                PKG_MANAGER="dnf"
                # CentOS 7 and older use yum
                if ! command -v dnf >/dev/null 2>&1; then
                    PKG_MANAGER="yum"
                fi
                ;;
            arch|manjaro|endeavouros|garuda|artix)
                DISTRO_FAMILY="arch"
                PKG_MANAGER="pacman"
                ;;
            opensuse*|suse*)
                DISTRO_FAMILY="suse"
                PKG_MANAGER="zypper"
                ;;
            *)
                # Try ID_LIKE as fallback
                case "$ID_LIKE" in
                    *debian*|*ubuntu*)
                        DISTRO_FAMILY="debian"
                        PKG_MANAGER="apt"
                        ;;
                    *fedora*|*rhel*)
                        DISTRO_FAMILY="fedora"
                        PKG_MANAGER="dnf"
                        ;;
                    *arch*)
                        DISTRO_FAMILY="arch"
                        PKG_MANAGER="pacman"
                        ;;
                    *)
                        DISTRO_FAMILY="unknown"
                        PKG_MANAGER="unknown"
                        ;;
                esac
                ;;
        esac
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
}

# =============================================================================
# Minimal Package Installation Functions (Production Only)
# =============================================================================
install_packages_debian() {
    log_info "Installing minimal production packages using apt..."
    apt-get update
    apt-get install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        jq \
        vim-tiny \
        htop \
        net-tools \
        openssh-server \
        openssl \
        sudo \
        fail2ban \
        ufw \
        logrotate \
        unattended-upgrades

    # Configure unattended upgrades for security
    dpkg-reconfigure -plow unattended-upgrades 2>/dev/null || true
}

install_packages_fedora() {
    log_info "Installing minimal production packages using $PKG_MANAGER..."
    $PKG_MANAGER install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg2 \
        jq \
        vim-minimal \
        htop \
        net-tools \
        openssh-server \
        openssl \
        sudo \
        fail2ban \
        firewalld \
        logrotate \
        dnf-automatic

    # Enable automatic security updates
    systemctl enable --now dnf-automatic-install.timer 2>/dev/null || true
}

install_packages_arch() {
    log_info "Installing minimal production packages using pacman..."
    pacman -Syu --noconfirm
    pacman -S --noconfirm --needed \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
        jq \
        vim \
        htop \
        net-tools \
        openssh \
        openssl \
        sudo \
        fail2ban \
        ufw \
        logrotate
}

install_packages() {
    case "$DISTRO_FAMILY" in
        debian) install_packages_debian ;;
        fedora) install_packages_fedora ;;
        arch) install_packages_arch ;;
        *)
            log_error "Unsupported distribution family: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
}

# =============================================================================
# Docker Installation Functions
# =============================================================================
install_docker_debian() {
    log_info "Installing Docker on Debian/Ubuntu..."

    if command -v docker >/dev/null 2>&1; then
        log_warn "Docker is already installed ($(docker --version))"
        return
    fi

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$DISTRO_ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Set up the repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO_ID \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    log_success "Docker installed successfully"
}

install_docker_fedora() {
    log_info "Installing Docker on Fedora/RHEL..."

    if command -v docker >/dev/null 2>&1; then
        log_warn "Docker is already installed ($(docker --version))"
        return
    fi

    # Add Docker repository
    $PKG_MANAGER config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
    $PKG_MANAGER config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
    true

    # For RHEL/CentOS, use centos repo
    if [ "$DISTRO_ID" = "rhel" ] || [ "$DISTRO_ID" = "centos" ] || [ "$DISTRO_ID" = "rocky" ] || [ "$DISTRO_ID" = "alma" ]; then
        $PKG_MANAGER config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || true
    fi

    # Install Docker
    $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    log_success "Docker installed successfully"
}

install_docker_arch() {
    log_info "Installing Docker on Arch Linux..."

    if command -v docker >/dev/null 2>&1; then
        log_warn "Docker is already installed ($(docker --version))"
        return
    fi

    # Install Docker from official repos
    pacman -S --noconfirm docker docker-compose docker-buildx

    systemctl enable docker
    systemctl start docker

    log_success "Docker installed successfully"
}

install_docker() {
    case "$DISTRO_FAMILY" in
        debian) install_docker_debian ;;
        fedora) install_docker_fedora ;;
        arch) install_docker_arch ;;
        *)
            log_error "Unsupported distribution for Docker: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
}

# =============================================================================
# Docker Security Hardening
# =============================================================================
harden_docker() {
    log_info "Applying Docker security hardening..."

    # Create daemon.json with security settings
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true,
    "icc": false,
    "storage-driver": "overlay2"
}
EOF

    # Restart Docker to apply settings
    systemctl restart docker 2>/dev/null || true

    log_success "Docker security hardening applied"
}

# =============================================================================
# Tailscale Installation
# =============================================================================
install_tailscale() {
    if command -v tailscale >/dev/null 2>&1; then
        log_warn "Tailscale is already installed"
        return
    fi

    log_info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    log_success "Tailscale installed"
}

# =============================================================================
# User Setup (Production - More Restrictive)
# =============================================================================
setup_users() {
    log_info "Setting up users with production security..."

    # Detect current user (who invoked sudo)
    REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"

    # Create actions user for CI/CD
    if id "actions" >/dev/null 2>&1; then
        log_warn "User 'actions' already exists"
    else
        useradd -m -s /bin/bash -c "GitHub Actions CI/CD User" actions
        log_success "User 'actions' created"
    fi

    # Add actions to docker group only
    usermod -aG docker actions
    log_success "User 'actions' added to docker group"

    # Configure the user who ran sudo
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        if id "$REAL_USER" >/dev/null 2>&1; then
            if ! groups "$REAL_USER" | grep -q docker; then
                usermod -aG docker "$REAL_USER"
                log_success "User '$REAL_USER' added to docker group"
            else
                log_info "User '$REAL_USER' already in docker group"
            fi
        fi
    fi

    # PRODUCTION: Disable password login for actions (SSH key only)
    passwd -l actions 2>/dev/null || true
    log_info "Password login disabled for 'actions' user (SSH key only)"

    # Set secure umask for actions user
    echo "umask 027" >> /home/actions/.bashrc
}

# =============================================================================
# SSH Security Hardening
# =============================================================================
setup_ssh() {
    log_info "Setting up SSH with production security..."

    ACTIONS_HOME="/home/actions"
    SSH_DIR="$ACTIONS_HOME/.ssh"

    # Create .ssh directory
    sudo -u actions mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    # Create authorized_keys file
    sudo -u actions touch "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"

    # Backup original sshd_config
    if [ ! -f /etc/ssh/sshd_config.bak ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    fi

    # Apply SSH hardening
    log_info "Applying SSH security hardening..."

    # Create drop-in config for hardening
    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/99-production-hardening.conf <<'EOF'
# Production SSH Hardening

# Disable root login
PermitRootLogin no

# Disable password authentication (use keys only)
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

# Disable empty passwords
PermitEmptyPasswords no

# Limit authentication attempts
MaxAuthTries 3
MaxSessions 3

# Set login grace time
LoginGraceTime 30

# Disable X11 forwarding
X11Forwarding no

# Disable TCP forwarding (uncomment if needed)
# AllowTcpForwarding no

# Use only Protocol 2
Protocol 2

# Strong ciphers only
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr

# Strong MACs only
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Strong key exchange algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Disable agent forwarding (uncomment if needed)
# AllowAgentForwarding no

# Log level
LogLevel VERBOSE

# Client alive settings
ClientAliveInterval 300
ClientAliveCountMax 2

# Allow only actions user via SSH (add more users as needed)
AllowUsers actions
EOF

    # Ensure SSH service is running
    case "$DISTRO_FAMILY" in
        debian|fedora)
            systemctl enable sshd 2>/dev/null || systemctl enable ssh 2>/dev/null || true
            systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
            ;;
        arch)
            systemctl enable sshd
            systemctl restart sshd
            ;;
    esac

    log_success "SSH hardening applied"
}

# =============================================================================
# Firewall Setup
# =============================================================================
setup_firewall() {
    log_info "Setting up firewall..."

    case "$DISTRO_FAMILY" in
        debian|arch)
            if command -v ufw >/dev/null 2>&1; then
                ufw --force reset
                ufw default deny incoming
                ufw default allow outgoing
                ufw allow ssh
                # Allow common ports (adjust as needed)
                ufw allow 80/tcp    # HTTP
                ufw allow 443/tcp   # HTTPS
                ufw --force enable
                log_success "UFW firewall configured"
            fi
            ;;
        fedora)
            if command -v firewall-cmd >/dev/null 2>&1; then
                systemctl enable firewalld
                systemctl start firewalld
                firewall-cmd --permanent --add-service=ssh
                firewall-cmd --permanent --add-service=http
                firewall-cmd --permanent --add-service=https
                firewall-cmd --reload
                log_success "Firewalld configured"
            fi
            ;;
    esac
}

# =============================================================================
# Fail2ban Setup
# =============================================================================
setup_fail2ban() {
    log_info "Configuring fail2ban..."

    if command -v fail2ban-client >/dev/null 2>&1; then
        # Create jail.local for SSH protection
        cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

        # Adjust log path for different distros
        if [ "$DISTRO_FAMILY" = "fedora" ]; then
            sed -i 's|/var/log/auth.log|/var/log/secure|g' /etc/fail2ban/jail.local
        fi

        systemctl enable fail2ban
        systemctl restart fail2ban

        log_success "Fail2ban configured"
    else
        log_warn "Fail2ban not installed"
    fi
}

# =============================================================================
# System Hardening
# =============================================================================
apply_system_hardening() {
    log_info "Applying system hardening..."

    # Kernel hardening via sysctl
    cat > /etc/sysctl.d/99-production-hardening.conf <<'EOF'
# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Disable IPv6 if not needed (uncomment if desired)
# net.ipv6.conf.all.disable_ipv6 = 1
# net.ipv6.conf.default.disable_ipv6 = 1

# Increase system file descriptor limit
fs.file-max = 65535

# Increase inotify limits for Docker
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512

# Virtual memory tuning
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2
EOF

    # Apply sysctl settings
    sysctl --system 2>/dev/null || sysctl -p /etc/sysctl.d/99-production-hardening.conf

    # Set secure permissions on sensitive files
    chmod 600 /etc/shadow 2>/dev/null || true
    chmod 600 /etc/gshadow 2>/dev/null || true
    chmod 644 /etc/passwd
    chmod 644 /etc/group

    # Disable core dumps
    echo "* hard core 0" >> /etc/security/limits.conf
    echo "fs.suid_dumpable = 0" >> /etc/sysctl.d/99-production-hardening.conf

    log_success "System hardening applied"
}

# =============================================================================
# Directory Setup
# =============================================================================
setup_directories() {
    log_info "Creating directories..."

    ACTIONS_HOME="/home/actions"

    # Main directories in /home/actions/
    # Repos will be cloned directly here: /home/actions/<repo-name>
    sudo -u actions mkdir -p "$ACTIONS_HOME/logs"
    sudo -u actions mkdir -p "$ACTIONS_HOME/backups"
    sudo -u actions mkdir -p "$ACTIONS_HOME/data"
    sudo -u actions mkdir -p "$ACTIONS_HOME/.config"

    # Set restrictive permissions
    chmod 750 "$ACTIONS_HOME"
    chmod 700 "$ACTIONS_HOME/logs"
    chmod 700 "$ACTIONS_HOME/backups"
    chmod 700 "$ACTIONS_HOME/data"
    chmod 700 "$ACTIONS_HOME/.config"

    log_success "Directories created with secure permissions"
    log_info "Repositories will be cloned to: /home/actions/<repo-name>"
}

# =============================================================================
# Environment Template
# =============================================================================
create_env_template() {
    log_info "Creating .env template..."

    ACTIONS_HOME="/home/actions"
    ENV_FILE="$ACTIONS_HOME/.config/server.env"

    if [ ! -f "$ENV_FILE" ]; then
        sudo -u actions tee "$ENV_FILE" > /dev/null <<'EOF'
# Production Server Environment Variables
# Generated by setup-prod-server.sh
# Update these values as needed

# =============================================================================
# RUNTIME ENVIRONMENT
# =============================================================================
PRODUCTION_MODE=true
TZ=UTC

# =============================================================================
# PATHS
# =============================================================================
PROJECTS_PATH=/home/actions/projects
LOGS_PATH=/home/actions/logs
BACKUPS_PATH=/home/actions/backups
DATA_PATH=/home/actions/data

# =============================================================================
# DOCKER
# =============================================================================
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# =============================================================================
# SECURITY
# =============================================================================
# Disable debug features in production
RUST_BACKTRACE=0
RUST_LOG=warn
EOF

        chmod 600 "$ENV_FILE"
        chown actions:actions "$ENV_FILE"

        log_success ".env template created at $ENV_FILE"
    else
        log_warn ".env file already exists at $ENV_FILE"
    fi
}

# =============================================================================
# Logrotate Configuration
# =============================================================================
setup_logrotate() {
    log_info "Configuring log rotation..."

    cat > /etc/logrotate.d/actions <<'EOF'
/home/actions/logs/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 actions actions
    sharedscripts
}
EOF

    log_success "Log rotation configured"
}

# =============================================================================
# Main Setup Flow
# =============================================================================
main() {
    log_header "Multi-Distro Production Server Setup"

    log_warn "This is a PRODUCTION server setup."
    log_warn "For development tools, use setup-dev-server.sh instead."
    printf "\n"

    # Detect distribution
    detect_distro

    log_info "Detected OS: $DISTRO_NAME"
    log_info "Distribution Family: $DISTRO_FAMILY"
    log_info "Package Manager: $PKG_MANAGER"
    log_info "Architecture: $(uname -m)"
    log_info "Kernel: $(uname -r)"
    printf "\n"

    # Check for supported distro
    if [ "$DISTRO_FAMILY" = "unknown" ]; then
        log_error "Unsupported distribution: $DISTRO_ID"
        log_error "Supported: Ubuntu, Debian, Fedora, RHEL, CentOS, Arch, Manjaro"
        exit 1
    fi

    # Step 1: Update system and install minimal packages
    log_info "Step 1/10: Installing minimal production packages..."
    install_packages
    log_success "Minimal packages installed"
    printf "\n"

    # Step 2: Install Docker
    log_info "Step 2/10: Installing Docker..."
    install_docker
    docker --version
    docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
    printf "\n"

    # Step 3: Harden Docker
    log_info "Step 3/10: Hardening Docker..."
    harden_docker
    printf "\n"

    # Step 4: Install Tailscale (if not present)
    log_info "Step 4/10: Checking Tailscale..."
    if command -v tailscale >/dev/null 2>&1; then
        log_success "Tailscale already installed"
        TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "Not connected")
        log_info "Tailscale IP: $TAILSCALE_IP"
    else
        log_warn "Tailscale not installed"
        printf "Install Tailscale? (Y/n) "
        read -r reply
        if [ "$reply" != "n" ] && [ "$reply" != "N" ]; then
            install_tailscale
        fi
    fi
    printf "\n"

    # Step 5: Setup users
    log_info "Step 5/10: Setting up users with production security..."
    setup_users
    printf "\n"

    # Step 6: Setup SSH with hardening
    log_info "Step 6/10: Setting up SSH with security hardening..."
    setup_ssh
    printf "\n"

    # Step 7: Setup firewall
    log_info "Step 7/10: Configuring firewall..."
    setup_firewall
    printf "\n"

    # Step 8: Setup fail2ban
    log_info "Step 8/10: Configuring fail2ban..."
    setup_fail2ban
    printf "\n"

    # Step 9: Apply system hardening
    log_info "Step 9/10: Applying system hardening..."
    apply_system_hardening
    printf "\n"

    # Step 10: Create directories and configuration
    log_info "Step 10/10: Creating directories and configuration..."
    setup_directories
    create_env_template
    setup_logrotate
    printf "\n"

    # Run generate-secrets.sh if available
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    GENERATE_SECRETS_SCRIPT="$SCRIPT_DIR/generate-secrets.sh"

    if [ -f "$GENERATE_SECRETS_SCRIPT" ]; then
        printf "Generate secrets now? (Y/n) "
        read -r reply
        if [ "$reply" != "n" ] && [ "$reply" != "N" ]; then
            log_info "Running generate-secrets.sh..."
            chmod +x "$GENERATE_SECRETS_SCRIPT"
            "$GENERATE_SECRETS_SCRIPT"
        fi
    fi

    # =============================================================================
    # Summary
    # =============================================================================
    log_header "Production Server Setup Complete!"

    log_info "System Information:"
    printf "  OS: %s\n" "$DISTRO_NAME"
    printf "  Architecture: %s\n" "$(uname -m)"
    printf "  Kernel: %s\n" "$(uname -r)"
    printf "  CPU: %s cores\n" "$(nproc)"
    printf "  RAM: %s\n" "$(free -h | awk '/^Mem:/ {print $2}')"
    printf "  Disk: %s available\n" "$(df -h / | awk 'NR==2 {print $4}')"
    printf "\n"

    log_info "Security Features Applied:"
    printf "  ✓ SSH hardened (key-only authentication)\n"
    printf "  ✓ Firewall configured\n"
    printf "  ✓ Fail2ban protecting SSH\n"
    printf "  ✓ Docker security hardened\n"
    printf "  ✓ Kernel security parameters set\n"
    printf "  ✓ Automatic security updates enabled\n"
    printf "\n"

    log_header "Next Steps"

    printf "${BOLD}${GREEN}1. Connect to Tailscale (if not already):${NC}\n"
    printf "   ${CYAN}sudo tailscale up${NC}\n\n"

    printf "${BOLD}${GREEN}2. Generate secrets (if not done):${NC}\n"
    printf "   ${CYAN}sudo %s${NC}\n\n" "$GENERATE_SECRETS_SCRIPT"

    printf "${BOLD}${GREEN}3. Add your SSH public key:${NC}\n"
    printf "   ${CYAN}echo 'your-public-key' >> /home/actions/.ssh/authorized_keys${NC}\n\n"

    printf "${BOLD}${GREEN}4. Test SSH connection (from remote):${NC}\n"
    printf "   ${CYAN}ssh actions@YOUR_TAILSCALE_IP${NC}\n\n"

    printf "${BOLD}${GREEN}5. Test Docker:${NC}\n"
    printf "   ${CYAN}docker ps${NC}\n"
    printf "   ${YELLOW}Note: Log out and back in for docker group to take effect${NC}\n\n"

    printf "${BOLD}${GREEN}6. Get Tailscale IP:${NC}\n"
    printf "   ${CYAN}tailscale ip -4${NC}\n\n"

    log_header "Security Reminders"

    printf "${YELLOW}⚠  Password authentication is DISABLED for SSH${NC}\n"
    printf "${YELLOW}⚠  Only the 'actions' user can SSH (key-only)${NC}\n"
    printf "${YELLOW}⚠  Firewall allows: SSH, HTTP (80), HTTPS (443)${NC}\n"
    printf "${YELLOW}⚠  Review /etc/ssh/sshd_config.d/99-production-hardening.conf${NC}\n"
    printf "${YELLOW}⚠  Review /etc/sysctl.d/99-production-hardening.conf${NC}\n"
    printf "\n"

    log_success "Production server is ready and hardened!"
    printf "\n"
}

# Run main function
main "$@"
