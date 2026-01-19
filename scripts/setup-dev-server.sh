#!/bin/sh
# Multi-Distro Development Server Setup Script
# Supports: Ubuntu/Debian, Fedora/RHEL/CentOS, Arch Linux
#
# Usage:
#   chmod +x setup-dev-server.sh
#   sudo ./setup-dev-server.sh
#
# This script will:
# - Detect the Linux distribution
# - Install Docker and dependencies
# - Install Rust toolchain (rustup, cargo, clippy, rustfmt)
# - Install Protobuf compiler and tools
# - Install build essentials (cmake, make, gcc, clang)
# - Install testing and debugging tools (valgrind, gdb, strace)
# - Install Node.js and Python development tools
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
# Base Package Installation Functions
# =============================================================================
install_packages_debian() {
    log_info "Installing base packages using apt..."
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
        tmux \
        zsh \
        net-tools \
        openssh-server \
        openssl \
        sudo \
        unzip \
        zip \
        tree \
        openjdk-21-jdk

    # Set JAVA_HOME for all users
    echo 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64' > /etc/profile.d/java.sh
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/profile.d/java.sh
    chmod +x /etc/profile.d/java.sh
}

install_packages_fedora() {
    log_info "Installing base packages using $PKG_MANAGER..."
    $PKG_MANAGER install -y \
        curl \
        wget \
        git \
        ca-certificates \
        gnupg2 \
        jq \
        vim \
        htop \
        tmux \
        zsh \
        net-tools \
        openssh-server \
        openssl \
        sudo \
        unzip \
        zip \
        tree \
        dnf-plugins-core \
        java-21-openjdk-devel

    # Set JAVA_HOME for all users
    echo 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk' > /etc/profile.d/java.sh
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/profile.d/java.sh
    chmod +x /etc/profile.d/java.sh
}

install_packages_arch() {
    log_info "Installing base packages using pacman..."
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
        tmux \
        zsh \
        net-tools \
        openssh \
        openssl \
        sudo \
        unzip \
        zip \
        tree \
        base-devel \
        jdk21-openjdk

    # Set JAVA_HOME for all users
    echo 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk' > /etc/profile.d/java.sh
    echo 'export PATH=$JAVA_HOME/bin:$PATH' >> /etc/profile.d/java.sh
    chmod +x /etc/profile.d/java.sh
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
# Build Essentials Installation
# =============================================================================
install_build_essentials_debian() {
    log_info "Installing build essentials on Debian/Ubuntu..."
    apt-get install -y \
        build-essential \
        cmake \
        make \
        gcc \
        g++ \
        clang \
        llvm \
        lldb \
        lld \
        pkg-config \
        autoconf \
        automake \
        libtool \
        ninja-build \
        meson \
        ccache \
        libssl-dev \
        libffi-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncurses5-dev \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev
}

install_build_essentials_fedora() {
    log_info "Installing build essentials on Fedora/RHEL..."
    $PKG_MANAGER groupinstall -y "Development Tools"
    $PKG_MANAGER install -y \
        cmake \
        make \
        gcc \
        gcc-c++ \
        clang \
        llvm \
        lldb \
        lld \
        pkg-config \
        autoconf \
        automake \
        libtool \
        ninja-build \
        meson \
        ccache \
        openssl-devel \
        libffi-devel \
        zlib-devel \
        bzip2-devel \
        readline-devel \
        sqlite-devel \
        ncurses-devel \
        xz-devel \
        tk-devel \
        libxml2-devel \
        xmlsec1-devel
}

install_build_essentials_arch() {
    log_info "Installing build essentials on Arch Linux..."
    pacman -S --noconfirm --needed \
        base-devel \
        cmake \
        make \
        gcc \
        clang \
        llvm \
        lldb \
        lld \
        pkg-config \
        autoconf \
        automake \
        libtool \
        ninja \
        meson \
        ccache \
        openssl \
        libffi \
        zlib \
        bzip2 \
        readline \
        sqlite \
        ncurses \
        xz \
        tk \
        libxml2 \
        xmlsec
}

install_build_essentials() {
    case "$DISTRO_FAMILY" in
        debian) install_build_essentials_debian ;;
        fedora) install_build_essentials_fedora ;;
        arch) install_build_essentials_arch ;;
        *)
            log_error "Unsupported distribution for build essentials: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
}

# =============================================================================
# Rust Installation
# =============================================================================
install_rust() {
    log_info "Installing Rust toolchain..."

    # Install for root first (system-wide tools)
    if ! command -v rustup >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        . "$HOME/.cargo/env"
    else
        log_warn "Rust already installed for root"
    fi

    # Install common components
    if command -v rustup >/dev/null 2>&1; then
        rustup component add clippy rustfmt rust-analyzer rust-src
        rustup target add wasm32-unknown-unknown 2>/dev/null || true
        log_success "Rust components installed"
    fi

    # Install useful cargo tools
    if command -v cargo >/dev/null 2>&1; then
        cargo install cargo-watch cargo-edit cargo-audit cargo-outdated cargo-deny sccache 2>/dev/null || true
        log_success "Cargo tools installed"
    fi

    # Install Rust for actions user
    ACTIONS_HOME="/home/actions"
    if id "actions" >/dev/null 2>&1; then
        if [ ! -d "$ACTIONS_HOME/.cargo" ]; then
            sudo -u actions sh -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable'
            sudo -u actions sh -c '. "$HOME/.cargo/env" && rustup component add clippy rustfmt rust-analyzer rust-src'
            log_success "Rust installed for actions user"
        else
            log_warn "Rust already installed for actions user"
        fi
    fi
}

# =============================================================================
# Protobuf Installation
# =============================================================================
install_protobuf_debian() {
    log_info "Installing Protobuf on Debian/Ubuntu..."
    apt-get install -y \
        protobuf-compiler \
        libprotobuf-dev \
        libprotoc-dev

    # Install protoc-gen-grpc for gRPC
    if command -v cargo >/dev/null 2>&1; then
        cargo install protobuf-codegen 2>/dev/null || true
    fi
}

install_protobuf_fedora() {
    log_info "Installing Protobuf on Fedora/RHEL..."
    $PKG_MANAGER install -y \
        protobuf-compiler \
        protobuf-devel

    if command -v cargo >/dev/null 2>&1; then
        cargo install protobuf-codegen 2>/dev/null || true
    fi
}

install_protobuf_arch() {
    log_info "Installing Protobuf on Arch Linux..."
    pacman -S --noconfirm --needed \
        protobuf

    if command -v cargo >/dev/null 2>&1; then
        cargo install protobuf-codegen 2>/dev/null || true
    fi
}

install_protobuf() {
    case "$DISTRO_FAMILY" in
        debian) install_protobuf_debian ;;
        fedora) install_protobuf_fedora ;;
        arch) install_protobuf_arch ;;
        *)
            log_error "Unsupported distribution for Protobuf: $DISTRO_FAMILY"
            exit 1
            ;;
    esac

    # Install Buf CLI for modern protobuf management
    if ! command -v buf >/dev/null 2>&1; then
        curl -sSL "https://github.com/bufbuild/buf/releases/latest/download/buf-$(uname -s)-$(uname -m)" -o /usr/local/bin/buf
        chmod +x /usr/local/bin/buf
        log_success "Buf CLI installed"
    fi
}

# =============================================================================
# Testing & Debugging Tools Installation
# =============================================================================
install_testing_tools_debian() {
    log_info "Installing testing and debugging tools on Debian/Ubuntu..."
    apt-get install -y \
        valgrind \
        gdb \
        strace \
        ltrace \
        perf-tools-unstable 2>/dev/null || apt-get install -y linux-perf 2>/dev/null || true
    apt-get install -y \
        kcachegrind \
        lcov \
        gcovr \
        cppcheck \
        shellcheck \
        hyperfine 2>/dev/null || true
}

install_testing_tools_fedora() {
    log_info "Installing testing and debugging tools on Fedora/RHEL..."
    $PKG_MANAGER install -y \
        valgrind \
        gdb \
        strace \
        ltrace \
        perf \
        kcachegrind \
        lcov \
        gcovr \
        cppcheck \
        ShellCheck \
        hyperfine 2>/dev/null || true
}

install_testing_tools_arch() {
    log_info "Installing testing and debugging tools on Arch Linux..."
    pacman -S --noconfirm --needed \
        valgrind \
        gdb \
        strace \
        ltrace \
        perf \
        kcachegrind \
        lcov \
        gcovr \
        cppcheck \
        shellcheck \
        hyperfine 2>/dev/null || true
}

install_testing_tools() {
    case "$DISTRO_FAMILY" in
        debian) install_testing_tools_debian ;;
        fedora) install_testing_tools_fedora ;;
        arch) install_testing_tools_arch ;;
        *)
            log_error "Unsupported distribution for testing tools: $DISTRO_FAMILY"
            exit 1
            ;;
    esac

    # Install cargo testing tools
    if command -v cargo >/dev/null 2>&1; then
        cargo install cargo-nextest cargo-llvm-cov cargo-tarpaulin 2>/dev/null || true
        log_success "Cargo testing tools installed"
    fi
}

# =============================================================================
# Node.js Installation
# =============================================================================
install_nodejs() {
    log_info "Installing Node.js..."

    if command -v node >/dev/null 2>&1; then
        log_warn "Node.js already installed: $(node --version)"
        return
    fi

    # Install via NodeSource for latest LTS
    case "$DISTRO_FAMILY" in
        debian)
            curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
            apt-get install -y nodejs
            ;;
        fedora)
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
            $PKG_MANAGER install -y nodejs
            ;;
        arch)
            pacman -S --noconfirm --needed nodejs npm
            ;;
    esac

    # Install useful global npm packages
    if command -v npm >/dev/null 2>&1; then
        npm install -g pnpm yarn typescript ts-node eslint prettier
        log_success "Node.js global packages installed"
    fi
}

# =============================================================================
# Python Development Tools Installation
# =============================================================================
install_python_tools_debian() {
    log_info "Installing Python development tools on Debian/Ubuntu..."
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-setuptools \
        python3-wheel
}

install_python_tools_fedora() {
    log_info "Installing Python development tools on Fedora/RHEL..."
    $PKG_MANAGER install -y \
        python3 \
        python3-pip \
        python3-devel \
        python3-setuptools \
        python3-wheel
}

install_python_tools_arch() {
    log_info "Installing Python development tools on Arch Linux..."
    pacman -S --noconfirm --needed \
        python \
        python-pip \
        python-setuptools \
        python-wheel
}

install_python_tools() {
    case "$DISTRO_FAMILY" in
        debian) install_python_tools_debian ;;
        fedora) install_python_tools_fedora ;;
        arch) install_python_tools_arch ;;
        *)
            log_error "Unsupported distribution for Python tools: $DISTRO_FAMILY"
            exit 1
            ;;
    esac

    # Install useful Python packages globally
    pip3 install --break-system-packages pytest pytest-cov black ruff mypy pipx 2>/dev/null || \
    pip3 install pytest pytest-cov black ruff mypy pipx 2>/dev/null || true
    log_success "Python development tools installed"
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

    # For dev server, allow password login for convenience
    log_info "Password login enabled for 'actions' user (dev server)"
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
    sudo -u actions mkdir -p "$ACTIONS_HOME/projects"
    sudo -u actions mkdir -p "$ACTIONS_HOME/tools"

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
# Development Server Environment Variables
# Generated by setup-dev-server.sh
# Update these values as needed

# =============================================================================
# RUNTIME ENVIRONMENT
# =============================================================================
DEVELOPMENT_MODE=true
TZ=UTC

# =============================================================================
# PATHS
# =============================================================================
PROJECTS_PATH=/home/actions/projects
LOGS_PATH=/home/actions/logs
BACKUPS_PATH=/home/actions/backups
DATA_PATH=/home/actions/data
TOOLS_PATH=/home/actions/tools

# =============================================================================
# RUST
# =============================================================================
CARGO_HOME=/home/actions/.cargo
RUSTUP_HOME=/home/actions/.rustup

# =============================================================================
# DOCKER
# =============================================================================
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# =============================================================================
# DEVELOPMENT
# =============================================================================
# Enable debug features
RUST_BACKTRACE=1
RUST_LOG=debug
EOF

        chmod 600 "$ENV_FILE"
        chown actions:actions "$ENV_FILE"

        log_success ".env template created at $ENV_FILE"
    else
        log_warn ".env file already exists at $ENV_FILE"
    fi
}

# =============================================================================
# Shell Configuration for actions user
# =============================================================================
setup_shell_config() {
    log_info "Setting up shell configuration for actions user..."

    ACTIONS_HOME="/home/actions"
    BASHRC="$ACTIONS_HOME/.bashrc"

    # Add development environment to bashrc
    sudo -u actions tee -a "$BASHRC" > /dev/null <<'EOF'

# =============================================================================
# Development Environment Setup (added by setup-dev-server.sh)
# =============================================================================

# Rust
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# Go (if installed)
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

# Local binaries
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/tools:$PATH"

# Development aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'

# Cargo aliases
alias cb='cargo build'
alias cr='cargo run'
alias ct='cargo test'
alias cc='cargo check'
alias cf='cargo fmt'
alias ccl='cargo clippy'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'

# Enable colors
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagaced

# History settings
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTCONTROL=ignoreboth:erasedups

# Editor
export EDITOR=vim

# Rust development
export RUST_BACKTRACE=1
EOF

    log_success "Shell configuration updated for actions user"
}

# =============================================================================
# Main Setup Flow
# =============================================================================
main() {
    log_header "Multi-Distro Development Server Setup"

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

    # Step 1: Update system and install base packages
    log_info "Step 1/12: Installing base system packages..."
    install_packages
    log_success "Base packages installed"

    # Verify Java installation
    if command -v java >/dev/null 2>&1; then
        log_success "Java installed: $(java -version 2>&1 | head -1)"
    else
        log_warn "Java installation may require a shell restart"
    fi
    printf "\n"

    # Step 2: Install build essentials
    log_info "Step 2/12: Installing build essentials..."
    install_build_essentials
    log_success "Build essentials installed"
    printf "\n"

    # Step 3: Install Docker
    log_info "Step 3/12: Installing Docker..."
    install_docker
    docker --version
    docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
    printf "\n"

    # Step 4: Setup users (before installing user-specific tools)
    log_info "Step 4/12: Setting up users..."
    setup_users
    printf "\n"

    # Step 5: Install Rust
    log_info "Step 5/12: Installing Rust toolchain..."
    install_rust
    if command -v rustc >/dev/null 2>&1; then
        log_success "Rust installed: $(rustc --version)"
    fi
    printf "\n"

    # Step 6: Install Protobuf
    log_info "Step 6/12: Installing Protobuf..."
    install_protobuf
    if command -v protoc >/dev/null 2>&1; then
        log_success "Protobuf installed: $(protoc --version)"
    fi
    printf "\n"

    # Step 7: Install testing tools
    log_info "Step 7/12: Installing testing and debugging tools..."
    install_testing_tools
    log_success "Testing tools installed"
    printf "\n"

    # Step 8: Install Node.js
    log_info "Step 8/12: Installing Node.js..."
    install_nodejs
    if command -v node >/dev/null 2>&1; then
        log_success "Node.js installed: $(node --version)"
    fi
    printf "\n"

    # Step 9: Install Python tools
    log_info "Step 9/12: Installing Python development tools..."
    install_python_tools
    log_success "Python tools installed"
    printf "\n"

    # Step 10: Install Tailscale (if not present)
    log_info "Step 10/12: Checking Tailscale..."
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

    # Step 11: Setup SSH and directories
    log_info "Step 11/12: Setting up SSH and directories..."
    setup_ssh
    setup_directories
    printf "\n"

    # Step 12: Create env template and shell config
    log_info "Step 12/12: Creating environment and shell configuration..."
    create_env_template
    setup_shell_config
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
    log_header "Development Server Setup Complete!"

    log_info "System Information:"
    printf "  OS: %s\n" "$DISTRO_NAME"
    printf "  Architecture: %s\n" "$(uname -m)"
    printf "  Kernel: %s\n" "$(uname -r)"
    printf "  CPU: %s cores\n" "$(nproc)"
    printf "  RAM: %s\n" "$(free -h | awk '/^Mem:/ {print $2}')"
    printf "  Disk: %s available\n" "$(df -h / | awk 'NR==2 {print $4}')"
    printf "\n"

    log_info "Installed Development Tools:"
    printf "  Rust: %s\n" "$(rustc --version 2>/dev/null || echo 'Not in PATH')"
    printf "  Cargo: %s\n" "$(cargo --version 2>/dev/null || echo 'Not in PATH')"
    printf "  Protobuf: %s\n" "$(protoc --version 2>/dev/null || echo 'Not installed')"
    printf "  Node.js: %s\n" "$(node --version 2>/dev/null || echo 'Not installed')"
    printf "  Python: %s\n" "$(python3 --version 2>/dev/null || echo 'Not installed')"
    printf "  Docker: %s\n" "$(docker --version 2>/dev/null || echo 'Not installed')"
    printf "  GCC: %s\n" "$(gcc --version 2>/dev/null | head -1 || echo 'Not installed')"
    printf "  Clang: %s\n" "$(clang --version 2>/dev/null | head -1 || echo 'Not installed')"
    printf "\n"

    log_header "Next Steps"

    printf "${BOLD}${GREEN}1. Connect to Tailscale (if not already):${NC}\n"
    printf "   ${CYAN}sudo tailscale up${NC}\n\n"

    printf "${BOLD}${GREEN}2. Generate secrets (if not done):${NC}\n"
    printf "   ${CYAN}sudo %s${NC}\n\n" "$GENERATE_SECRETS_SCRIPT"

    printf "${BOLD}${GREEN}3. Test Docker:${NC}\n"
    printf "   ${CYAN}docker ps${NC}\n"
    printf "   ${YELLOW}Note: Log out and back in for docker group to take effect${NC}\n\n"

    printf "${BOLD}${GREEN}4. Test Rust:${NC}\n"
    printf "   ${CYAN}rustc --version && cargo --version${NC}\n\n"

    printf "${BOLD}${GREEN}5. Get Tailscale IP:${NC}\n"
    printf "   ${CYAN}tailscale ip -4${NC}\n\n"

    printf "${BOLD}${GREEN}6. Switch to actions user:${NC}\n"
    printf "   ${CYAN}sudo -u actions -i${NC}\n\n"

    log_success "Development server is ready!"
    printf "\n"
}

# Run main function
main "$@"
