#!/bin/sh
# Multi-Distro Production Server Setup Script
# Supports: Ubuntu/Debian, Fedora/RHEL/CentOS, Arch Linux
#
# Usage:
#   chmod +x setup-server.sh
#   sudo ./setup-server.sh
#
# This script will:
# - Detect the Linux distribution
# - Install Docker and dependencies
# - Create/configure 'actions' user for CI/CD
# - Setup SSH for actions user
# - Optionally run generate-secrets.sh automatically

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
# Package Installation Functions
# =============================================================================
install_packages_debian() {
    log_info "Installing packages using apt..."
    apt-get update
    apt-get install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        jq \
        vim \
        htop \
        net-tools \
        openssh-server \
        openssl \
        sudo
}

install_packages_fedora() {
    log_info "Installing packages using $PKG_MANAGER..."
    $PKG_MANAGER install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg2 \
        jq \
        vim \
        htop \
        net-tools \
        openssh-server \
        openssl \
        sudo \
        dnf-plugins-core
}

install_packages_arch() {
    log_info "Installing packages using pacman..."
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
        base-devel
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
# User Setup
# =============================================================================
setup_users() {
    log_info "Setting up users..."

    # Detect current user (who invoked sudo)
    REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"

    # Create actions user for CI/CD
    if id "actions" >/dev/null 2>&1; then
        log_warn "User 'actions' already exists"
    else
        useradd -m -s /bin/bash -c "GitHub Actions CI/CD User" actions
        log_success "User 'actions' created"
    fi

    # Add actions to docker group
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

    # Disable password login for actions (SSH key only)
    passwd -l actions 2>/dev/null || true
    log_info "Password login disabled for 'actions' user (SSH key only)"
}

# =============================================================================
# SSH Setup
# =============================================================================
setup_ssh() {
    log_info "Setting up SSH for 'actions' user..."

    ACTIONS_HOME="/home/actions"
    SSH_DIR="$ACTIONS_HOME/.ssh"

    # Create .ssh directory
    sudo -u actions mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    # Create authorized_keys file
    sudo -u actions touch "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"

    # Ensure SSH service is running
    case "$DISTRO_FAMILY" in
        debian|fedora)
            systemctl enable sshd 2>/dev/null || systemctl enable ssh 2>/dev/null || true
            systemctl start sshd 2>/dev/null || systemctl start ssh 2>/dev/null || true
            ;;
        arch)
            systemctl enable sshd
            systemctl start sshd
            ;;
    esac

    log_success "SSH directory created for actions user"
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

    log_success "Directories created"
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
# Server Environment Variables
# Generated by setup-server.sh
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
EOF

        chmod 600 "$ENV_FILE"
        chown actions:actions "$ENV_FILE"

        log_success ".env template created at $ENV_FILE"
    else
        log_warn ".env file already exists at $ENV_FILE"
    fi
}

# =============================================================================
# Main Setup Flow
# =============================================================================
main() {
    log_header "Multi-Distro Server Setup"

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

    # Step 1: Update system and install packages
    log_info "Step 1/7: Installing system packages..."
    install_packages
    log_success "System packages installed"
    printf "\n"

    # Step 2: Install Docker
    log_info "Step 2/7: Installing Docker..."
    install_docker
    docker --version
    docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
    printf "\n"

    # Step 3: Install Tailscale (if not present)
    log_info "Step 3/7: Checking Tailscale..."
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

    # Step 4: Setup users
    log_info "Step 4/7: Setting up users..."
    setup_users
    printf "\n"

    # Step 5: Setup SSH
    log_info "Step 5/7: Setting up SSH..."
    setup_ssh
    printf "\n"

    # Step 6: Create directories
    log_info "Step 6/7: Creating directories..."
    setup_directories
    printf "\n"

    # Step 7: Create env template
    log_info "Step 7/7: Creating environment template..."
    create_env_template
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
    log_header "Setup Complete!"

    log_info "System Information:"
    printf "  OS: %s\n" "$DISTRO_NAME"
    printf "  Architecture: %s\n" "$(uname -m)"
    printf "  Kernel: %s\n" "$(uname -r)"
    printf "  CPU: %s cores\n" "$(nproc)"
    printf "  RAM: %s\n" "$(free -h | awk '/^Mem:/ {print $2}')"
    printf "  Disk: %s available\n" "$(df -h / | awk 'NR==2 {print $4}')"
    printf "\n"

    log_header "Next Steps"

    printf "${BOLD}${GREEN}1. Connect to Tailscale (if not already):${NC}\n"
    printf "   ${CYAN}sudo tailscale up${NC}\n\n"

    printf "${BOLD}${GREEN}2. Generate secrets (if not done):${NC}\n"
    printf "   ${CYAN}sudo %s${NC}\n\n" "$GENERATE_SECRETS_SCRIPT"

    printf "${BOLD}${GREEN}3. Test Docker:${NC}\n"
    printf "   ${CYAN}docker ps${NC}\n"
    printf "   ${YELLOW}Note: Log out and back in for docker group to take effect${NC}\n\n"

    printf "${BOLD}${GREEN}4. Get Tailscale IP:${NC}\n"
    printf "   ${CYAN}tailscale ip -4${NC}\n\n"

    log_success "Server is ready!"
    printf "\n"
}

# Run main function
main "$@"
