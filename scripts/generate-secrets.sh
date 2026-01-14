#!/bin/sh
# Multi-Distro Secrets Generation Script
# Supports: Ubuntu/Debian, Fedora/RHEL/CentOS, Arch Linux
#
# Usage:
#   chmod +x generate-secrets.sh
#   sudo ./generate-secrets.sh [--ci-output]
#
# Options:
#   --ci-output    Output secrets in CI-friendly format for GitHub Actions
#
# This script will:
# - Generate SSH keys for the actions user
# - Detect Tailscale IP address
# - Generate secure passwords and API keys
# - Create a credentials file for GitHub Secrets
# - Output in CI-friendly format when --ci-output is used

set -e

# Parse arguments
CI_OUTPUT=false
for arg in "$@"; do
    case "$arg" in
        --ci-output)
            CI_OUTPUT=true
            ;;
    esac
done

# Colors for output (disabled in CI mode)
if [ "$CI_OUTPUT" = true ]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
fi

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

# Function to generate secure password
generate_password() {
    openssl rand -base64 24 | tr -d "=+/" | cut -c1-24
}

# Function to generate hex secret (for JWT, encryption keys, etc.)
generate_hex_secret() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

# Function to generate base64 secret
generate_base64_secret() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | head -c "$length"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log_error "Please run this script with sudo"
    exit 1
fi

# Check if openssl is available
if ! command -v openssl >/dev/null 2>&1; then
    log_error "OpenSSL is not installed. Please install it first."
    exit 1
fi

ACTIONS_HOME="/home/actions"

# Check if actions user exists
if ! id "actions" >/dev/null 2>&1; then
    log_error "User 'actions' does not exist. Please run setup-server.sh first."
    exit 1
fi

log_header "Secrets Generation"

log_info "Generating secure credentials..."
printf "\n"

# =============================================================================
# Step 1: Detect Server Information
# =============================================================================
log_info "Step 1/4: Detecting server information..."

# Get server IP
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")
log_info "Server IP: $SERVER_IP"

# Detect Tailscale IP if available
TAILSCALE_IP=""
if command -v tailscale >/dev/null 2>&1; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    if [ -n "$TAILSCALE_IP" ]; then
        log_success "Tailscale IP detected: $TAILSCALE_IP"
    else
        log_warn "Tailscale is installed but not connected"
        log_warn "Run 'sudo tailscale up' to connect to your tailnet"
    fi
else
    log_warn "Tailscale not installed"
fi

# Detect SSH port
SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
if [ -z "$SSH_PORT" ]; then
    SSH_PORT=22
fi
log_info "SSH Port: $SSH_PORT"

# Detect hostname
HOSTNAME=$(hostname 2>/dev/null || echo "server")
log_info "Hostname: $HOSTNAME"

printf "\n"

# =============================================================================
# Step 2: Generate SSH Keys for Actions User
# =============================================================================
log_info "Step 2/4: Generating SSH keys for 'actions' user..."

SSH_DIR="$ACTIONS_HOME/.ssh"

# Ensure .ssh directory exists
sudo -u actions mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

REGENERATE_KEY=false
if [ -f "$SSH_DIR/id_ed25519" ]; then
    if [ "$CI_OUTPUT" = true ]; then
        log_info "Using existing SSH key"
    else
        log_warn "SSH key already exists for actions user"
        printf "Do you want to regenerate it? This will invalidate the old key. (y/N) "
        read -r reply
        if [ "$reply" = "y" ] || [ "$reply" = "Y" ]; then
            REGENERATE_KEY=true
            sudo -u actions rm -f "$SSH_DIR/id_ed25519" "$SSH_DIR/id_ed25519.pub"
        else
            log_info "Using existing SSH key"
        fi
    fi
fi

if [ ! -f "$SSH_DIR/id_ed25519" ]; then
    sudo -u actions ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -C "actions@$HOSTNAME-$(date +%Y%m%d)"
    chmod 600 "$SSH_DIR/id_ed25519"
    chmod 644 "$SSH_DIR/id_ed25519.pub"
    log_success "SSH key generated"
fi

# Add public key to authorized_keys
if [ ! -f "$SSH_DIR/authorized_keys" ]; then
    sudo -u actions touch "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"
fi

# Add key to authorized_keys if not already present
PUB_KEY=$(cat "$SSH_DIR/id_ed25519.pub")
if ! grep -qF "$PUB_KEY" "$SSH_DIR/authorized_keys" 2>/dev/null; then
    echo "$PUB_KEY" >> "$SSH_DIR/authorized_keys"
    log_success "Public key added to authorized_keys"
else
    log_info "Public key already in authorized_keys"
fi

printf "\n"

# =============================================================================
# Step 3: Generate Application Secrets
# =============================================================================
log_info "Step 3/4: Generating application secrets..."

# Generate various secrets
JWT_SECRET=$(generate_hex_secret 64)
ENCRYPTION_KEY=$(generate_hex_secret 32)
API_KEY=$(generate_base64_secret 32)
DB_PASSWORD=$(generate_password)
SESSION_SECRET=$(generate_hex_secret 32)
WEBHOOK_SECRET=$(generate_hex_secret 32)
ADMIN_PASSWORD=$(generate_password)

log_success "Application secrets generated"
printf "\n"

# =============================================================================
# Step 4: Output Credentials
# =============================================================================
log_info "Step 4/4: Saving credentials..."

# Read SSH private key
SSH_PRIVATE_KEY=$(cat "$SSH_DIR/id_ed25519")
SSH_PUBLIC_KEY=$(cat "$SSH_DIR/id_ed25519.pub")

# Create credentials file
CREDENTIALS_FILE="/tmp/server_credentials_$(date +%s).txt"
touch "$CREDENTIALS_FILE"
chmod 600 "$CREDENTIALS_FILE"

cat > "$CREDENTIALS_FILE" <<EOF
# =============================================================================
# Server Credentials
# Generated: $(date)
# Hostname: $HOSTNAME
# Server IP: $SERVER_IP
# Tailscale IP: ${TAILSCALE_IP:-Not configured}
# SSH Port: $SSH_PORT
# =============================================================================

# =============================================================================
# SSH & DEPLOYMENT SECRETS
# =============================================================================

# Tailscale IP address (use this for SSH connections)
TAILSCALE_IP=${TAILSCALE_IP:-CONFIGURE_TAILSCALE_FIRST}

# SSH port
SSH_PORT=$SSH_PORT

# SSH Private Key (copy entire block including BEGIN and END lines)
SSH_PRIVATE_KEY:
$SSH_PRIVATE_KEY

# SSH Public Key (add to any servers you need to access FROM this server)
SSH_PUBLIC_KEY:
$SSH_PUBLIC_KEY

# =============================================================================
# APPLICATION SECRETS
# =============================================================================

JWT_SECRET=$JWT_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY
API_KEY=$API_KEY
DB_PASSWORD=$DB_PASSWORD
SESSION_SECRET=$SESSION_SECRET
WEBHOOK_SECRET=$WEBHOOK_SECRET
ADMIN_PASSWORD=$ADMIN_PASSWORD

# =============================================================================
# GITHUB SECRETS FORMAT
# =============================================================================
# Copy these to your GitHub repository secrets:
# https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions
#
# SECRET NAME          | VALUE
# ---------------------|--------------------------------------------------
# PROD_SSH_KEY         | (entire SSH_PRIVATE_KEY above)
# PROD_SSH_PORT        | $SSH_PORT
# PROD_HOST            | ${TAILSCALE_IP:-YOUR_TAILSCALE_IP}
# PROD_USER            | actions
# =============================================================================

EOF

log_success "Credentials saved to: $CREDENTIALS_FILE"
printf "\n"

# =============================================================================
# CI Output Mode - Machine Readable Format
# =============================================================================
if [ "$CI_OUTPUT" = true ]; then
    log_header "CI OUTPUT - Copy Below This Line"

    printf "::group::GitHub Secrets (Add these to your repository)\n"

    printf "\n=== PROD_SSH_KEY (copy entire key including BEGIN/END lines) ===\n"
    printf "%s\n" "$SSH_PRIVATE_KEY"

    printf "\n=== PROD_SSH_PORT ===\n"
    printf "%s\n" "$SSH_PORT"

    printf "\n=== PROD_HOST ===\n"
    printf "%s\n" "${TAILSCALE_IP:-CONFIGURE_TAILSCALE_FIRST}"

    printf "\n=== PROD_USER ===\n"
    printf "actions\n"

    printf "\n=== SSH_PUBLIC_KEY (for reference) ===\n"
    printf "%s\n" "$SSH_PUBLIC_KEY"

    printf "::endgroup::\n"

    printf "\n::group::Application Secrets\n"
    printf "JWT_SECRET=%s\n" "$JWT_SECRET"
    printf "ENCRYPTION_KEY=%s\n" "$ENCRYPTION_KEY"
    printf "API_KEY=%s\n" "$API_KEY"
    printf "DB_PASSWORD=%s\n" "$DB_PASSWORD"
    printf "SESSION_SECRET=%s\n" "$SESSION_SECRET"
    printf "WEBHOOK_SECRET=%s\n" "$WEBHOOK_SECRET"
    printf "ADMIN_PASSWORD=%s\n" "$ADMIN_PASSWORD"
    printf "::endgroup::\n"

    # Output for GitHub Actions environment
    printf "\n::group::GitHub Actions Environment Variables\n"
    printf "TAILSCALE_IP=%s\n" "${TAILSCALE_IP:-NOT_CONFIGURED}"
    printf "SSH_PORT=%s\n" "$SSH_PORT"
    printf "HOSTNAME=%s\n" "$HOSTNAME"
    printf "SERVER_IP=%s\n" "$SERVER_IP"
    printf "::endgroup::\n"

    # Create summary file for GitHub Actions
    SUMMARY_FILE="/tmp/setup_summary.txt"
    cat > "$SUMMARY_FILE" <<EOF
## Server Setup Complete

| Property | Value |
|----------|-------|
| Hostname | $HOSTNAME |
| Server IP | $SERVER_IP |
| Tailscale IP | ${TAILSCALE_IP:-Not configured} |
| SSH Port | $SSH_PORT |
| SSH User | actions |

### Required GitHub Secrets

| Secret Name | Description |
|-------------|-------------|
| PROD_SSH_KEY | SSH private key for 'actions' user |
| PROD_SSH_PORT | $SSH_PORT |
| PROD_HOST | ${TAILSCALE_IP:-Your Tailscale IP} |
| PROD_USER | actions |

### Generated Application Secrets

These have been saved to \`$CREDENTIALS_FILE\` on the server.

### SSH Public Key

\`\`\`
$SSH_PUBLIC_KEY
\`\`\`

Add this public key to any servers you need to access FROM this server.
EOF

    printf "\n::set-output name=tailscale_ip::%s\n" "${TAILSCALE_IP:-NOT_CONFIGURED}"
    printf "::set-output name=ssh_port::%s\n" "$SSH_PORT"
    printf "::set-output name=hostname::%s\n" "$HOSTNAME"
    printf "::set-output name=credentials_file::%s\n" "$CREDENTIALS_FILE"
    printf "::set-output name=summary_file::%s\n" "$SUMMARY_FILE"

else
    # =============================================================================
    # Interactive Output Mode
    # =============================================================================
    log_header "Credentials Generated Successfully!"

    printf "${BOLD}${YELLOW}⚠  IMPORTANT: Secure the credentials file${NC}\n"
    printf "   Location: ${CYAN}%s${NC}\n\n" "$CREDENTIALS_FILE"

    printf "${BOLD}${GREEN}View credentials:${NC}\n"
    printf "   ${CYAN}cat %s${NC}\n\n" "$CREDENTIALS_FILE"

    log_header "GitHub Secrets Setup"

    printf "${BOLD}1. Go to your GitHub repository settings:${NC}\n"
    printf "   ${CYAN}https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions${NC}\n\n"

    printf "${BOLD}2. Add these REQUIRED secrets:${NC}\n\n"

    printf "   ${YELLOW}PROD_HOST${NC}\n"
    printf "   Value: ${CYAN}%s${NC}\n\n" "${TAILSCALE_IP:-⚠️ CONFIGURE TAILSCALE FIRST}"

    printf "   ${YELLOW}PROD_SSH_KEY${NC}\n"
    printf "   Value: (entire private key from credentials file)\n\n"

    printf "   ${YELLOW}PROD_SSH_PORT${NC}\n"
    printf "   Value: ${CYAN}%s${NC}\n\n" "$SSH_PORT"

    printf "   ${YELLOW}PROD_USER${NC}\n"
    printf "   Value: ${CYAN}actions${NC}\n\n"

    log_header "Quick Commands"

    printf "View full credentials file:\n"
    printf "   ${CYAN}cat %s${NC}\n\n" "$CREDENTIALS_FILE"

    printf "View SSH private key for GitHub:\n"
    printf "   ${CYAN}cat %s/.ssh/id_ed25519${NC}\n\n" "$ACTIONS_HOME"

    printf "View SSH public key:\n"
    printf "   ${CYAN}cat %s/.ssh/id_ed25519.pub${NC}\n\n" "$ACTIONS_HOME"

    printf "Get Tailscale IP:\n"
    printf "   ${CYAN}tailscale ip -4${NC}\n\n"

    printf "Test SSH connection (from another machine via Tailscale):\n"
    printf "   ${CYAN}ssh -p %s actions@%s${NC}\n\n" "$SSH_PORT" "${TAILSCALE_IP:-TAILSCALE_IP}"

    log_header "Security Best Practices"

    printf "${YELLOW}✓${NC} Keep the credentials file secure\n"
    printf "${YELLOW}✓${NC} Delete the credentials file after copying to GitHub Secrets:\n"
    printf "   ${CYAN}sudo rm %s${NC}\n" "$CREDENTIALS_FILE"
    printf "${YELLOW}✓${NC} Never commit secrets to version control\n"
    printf "${YELLOW}✓${NC} Rotate secrets periodically\n"
    printf "\n"
fi

log_success "Secrets generation complete!"
printf "\n"

exit 0
