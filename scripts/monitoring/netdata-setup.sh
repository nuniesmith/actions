#!/bin/bash
# netdata-setup.sh - Standardized Netdata monitoring setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }

# Configuration
SERVICE_NAME="${1:-unknown}"
NETDATA_CLAIM_TOKEN="${NETDATA_CLAIM_TOKEN:-}"
NETDATA_CLAIM_ROOM="${NETDATA_CLAIM_ROOM:-}"

# Help function
show_help() {
    cat << EOF
Netdata Setup Script - Standardized Monitoring Configuration

Usage: $0 <service_name> [options]

Arguments:
  service_name            Name of the service being monitored

Options:
  --claim-token <token>   Netdata Cloud claim token
  --claim-room <room>     Netdata Cloud room ID
  --hostname <name>       Custom hostname for monitoring
  --help                  Show this help

Environment Variables:
  NETDATA_CLAIM_TOKEN     Netdata Cloud claim token
  NETDATA_CLAIM_ROOM      Netdata Cloud room ID

Examples:
  $0 fks --claim-token abc123 --claim-room myroom
  $0 nginx
  NETDATA_CLAIM_TOKEN=abc123 $0 ats
EOF
}

# Install Netdata
install_netdata() {
    info "Installing Netdata..."
    
    # Check if already installed
    if systemctl is-active --quiet netdata 2>/dev/null; then
        success "Netdata is already installed and running"
        return 0
    fi
    
    # Install via package manager (Arch Linux)
    if command -v pacman &> /dev/null; then
        pacman -S --noconfirm netdata
    else
        # Fallback to official installer
        bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait
    fi
    
    success "Netdata installed"
}

# Configure Netdata
configure_netdata() {
    info "Configuring Netdata for service: $SERVICE_NAME"
    
    local config_file="/etc/netdata/netdata.conf"
    local hostname="${SERVICE_NAME}.7gram.xyz"
    
    # Backup original config
    if [[ -f "$config_file" && ! -f "$config_file.backup" ]]; then
        cp "$config_file" "$config_file.backup"
    fi
    
    # Create basic configuration
    cat > "$config_file" << EOF
[global]
    run as user = netdata
    web files owner = root
    web files group = root
    
    # Set hostname for identification
    hostname = $hostname
    
    # Allow connections from Tailscale network
    bind socket to IP = 0.0.0.0
    default port = 19999
    
    # Enable cloud features
    cloud enabled = yes
    
[web]
    mode = static-threaded
    listen backlog = 4096
    accept a streaming request every seconds = 0
    respect do not track policy = no
    x-frame-options response header = 
    allow connections from = localhost 127.* 10.* 192.168.* 172.16.* 172.17.* 172.18.* 172.19.* 172.20.* 172.21.* 172.22.* 172.23.* 172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.* 172.30.* 172.31.* 100.*
    allow dashboard from = localhost 127.* 10.* 192.168.* 172.16.* 172.17.* 172.18.* 172.19.* 172.20.* 172.21.* 172.22.* 172.23.* 172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.* 172.30.* 172.31.* 100.*
    allow badges from = *
    allow streaming from = localhost 127.* 10.* 192.168.* 172.16.* 172.17.* 172.18.* 172.19.* 172.20.* 172.21.* 172.22.* 172.23.* 172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.* 172.30.* 172.31.* 100.*
    allow netdata.conf from = localhost 127.* 10.* 192.168.* 172.16.* 172.17.* 172.18.* 172.19.* 172.20.* 172.21.* 172.22.* 172.23.* 172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.* 172.30.* 172.31.* 100.*
    allow management from = localhost 127.* 10.* 192.168.* 172.16.* 172.17.* 172.18.* 172.19.* 172.20.* 172.21.* 172.22.* 172.23.* 172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.* 172.30.* 172.31.* 100.*

[plugins]
    cgroups = yes
    tc = no
    idlejitter = yes
    proc = yes
    diskspace = yes
    timex = yes
    apps = yes
    fping = yes
    go.d = yes
    python.d = yes
    charts.d = yes
    node.d = yes
    
EOF
    
    success "Netdata configuration updated"
}

# Configure service-specific monitoring
configure_service_monitoring() {
    local service_type="$1"
    
    info "Setting up $service_type specific monitoring..."
    
    case "$service_type" in
        "container"|"fks"|"ats")
            # Docker monitoring
            cat > /etc/netdata/go.d/docker.conf << 'EOF'
jobs:
  - name: local
    url: unix:///var/run/docker.sock
    timeout: 1
    collect_container_size: yes
EOF
            success "Docker monitoring configured"
            ;;
        
        "reverse-proxy"|"nginx")
            # NGINX monitoring
            cat > /etc/netdata/go.d/nginx.conf << 'EOF'
jobs:
  - name: local
    url: http://127.0.0.1/stub_status
    timeout: 1
EOF
            success "NGINX monitoring configured"
            ;;
        
        "game-server")
            # Game server specific monitoring
            cat > /etc/netdata/go.d/portcheck.conf << 'EOF'
jobs:
  - name: game_server_ports
    host: 127.0.0.1
    ports:
      - 27015
      - 3000
    timeout: 1
EOF
            success "Game server monitoring configured"
            ;;
    esac
}

# Setup firewall rules
setup_firewall() {
    info "Configuring firewall for Netdata..."
    
    # Allow Netdata on Tailscale interface
    ufw allow in on tailscale0 to any port 19999
    
    success "Firewall configured for Netdata"
}

# Start and enable Netdata
start_netdata() {
    info "Starting Netdata service..."
    
    systemctl enable netdata
    systemctl start netdata
    
    # Wait for service to start
    sleep 5
    
    if systemctl is-active --quiet netdata; then
        success "Netdata is running"
    else
        error "Failed to start Netdata"
        journalctl -u netdata --no-pager -n 20
        return 1
    fi
}

# Claim to Netdata Cloud
claim_to_cloud() {
    local claim_token="$1"
    local claim_room="$2"
    local hostname="${SERVICE_NAME}.7gram.xyz"
    
    if [[ -z "$claim_token" ]]; then
        warning "No claim token provided - skipping cloud integration"
        return 0
    fi
    
    info "Claiming Netdata to cloud..."
    
    # Find claim script
    local claim_script=""
    for script_path in "/opt/netdata/bin/netdata-claim.sh" "/opt/netdata/usr/libexec/netdata/netdata-claim.sh" "/usr/libexec/netdata/netdata-claim.sh"; do
        if [[ -f "$script_path" ]]; then
            claim_script="$script_path"
            break
        fi
    done
    
    if [[ -z "$claim_script" ]]; then
        error "Netdata claim script not found"
        return 1
    fi
    
    # Attempt to claim with retries
    for attempt in 1 2 3; do
        info "Claim attempt $attempt/3..."
        
        if timeout 90 "$claim_script" \
           -token="$claim_token" \
           -rooms="$claim_room" \
           -url=https://app.netdata.cloud \
           -hostname="$hostname"; then
            success "Successfully claimed to Netdata Cloud"
            return 0
        fi
        
        warning "Claim attempt $attempt failed, retrying..."
        sleep 10
    done
    
    error "Failed to claim to Netdata Cloud after 3 attempts"
    return 1
}

# Health check
health_check() {
    info "Performing Netdata health check..."
    
    # Check if service is running
    if ! systemctl is-active --quiet netdata; then
        error "Netdata service is not running"
        return 1
    fi
    
    # Check if API is responding
    if curl -f -s http://localhost:19999/api/v1/info >/dev/null; then
        success "Netdata API is responding"
    else
        error "Netdata API is not responding"
        return 1
    fi
    
    # Check if claimed to cloud
    if [[ -f /var/lib/netdata/cloud.d/claimed_id ]]; then
        success "Netdata is claimed to cloud"
        local claimed_id
        claimed_id=$(cat /var/lib/netdata/cloud.d/claimed_id 2>/dev/null || echo "unknown")
        info "Claimed ID: $claimed_id"
    else
        warning "Netdata is not claimed to cloud"
    fi
    
    success "Netdata health check complete"
}

# Main function
main() {
    if [[ $# -eq 0 ]]; then
        show_help
        exit 1
    fi
    
    local service_name="$1"
    shift
    
    # Parse arguments
    local claim_token="$NETDATA_CLAIM_TOKEN"
    local claim_room="$NETDATA_CLAIM_ROOM"
    local hostname="${service_name}.7gram.xyz"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --claim-token)
                claim_token="$2"
                shift 2
                ;;
            --claim-room)
                claim_room="$2"
                shift 2
                ;;
            --hostname)
                hostname="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    info "Setting up Netdata monitoring for: $service_name"
    echo
    
    # Main setup sequence
    install_netdata
    configure_netdata
    
    # Determine service type for specific monitoring
    local service_type="container"
    if [[ "$service_name" == "nginx" ]]; then
        service_type="reverse-proxy"
    elif [[ "$service_name" == "ats" ]]; then
        service_type="game-server"
    fi
    
    configure_service_monitoring "$service_type"
    setup_firewall
    start_netdata
    
    if [[ -n "$claim_token" ]]; then
        claim_to_cloud "$claim_token" "$claim_room"
    fi
    
    health_check
    
    echo
    success "Netdata setup complete for $service_name!"
    info "Access dashboard at: http://$hostname:19999 (via Tailscale)"
    
    if [[ -n "$claim_token" ]]; then
        info "Also available in Netdata Cloud: https://app.netdata.cloud"
    fi
}

# Run main function
main "$@"
