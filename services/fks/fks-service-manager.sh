#!/bin/bash
# =================================================================
# fks-service-manager.sh - FKS Multi-Server Deployment Manager
# =================================================================
# 
# Manages deployment of FKS Trading Systems across multiple servers
# Integrates with Tailscale and Cloudflare DNS automation
#
# Usage:
#   ./fks-service-manager.sh deploy --mode multi --auth-server auth.7gram.xyz --api-server api.7gram.xyz --web-server web.7gram.xyz
#   ./fks-service-manager.sh deploy --mode single --server fks.7gram.xyz

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTIONS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_DOMAIN="7gram.xyz"

# =================================================================
# LOGGING FUNCTIONS
# =================================================================
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} [$timestamp] $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} [$timestamp] $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} [$timestamp] $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} [$timestamp] $message"
            ;;
        "FKS")
            echo -e "${PURPLE}[FKS]${NC} [$timestamp] $message"
            ;;
    esac
}

# =================================================================
# UTILITY FUNCTIONS
# =================================================================
check_dependencies() {
    local missing=()
    
    for cmd in docker curl jq ssh; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log "ERROR" "Missing required dependencies: ${missing[*]}"
        exit 1
    fi
}

get_tailscale_ip() {
    local hostname="$1"
    
    if command -v tailscale &> /dev/null; then
        # Try to get IP from tailscale status
        local ip=$(tailscale status --peers | grep "$hostname" | awk '{print $1}' | head -1)
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Fallback: try SSH to get tailscale IP
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$hostname" "tailscale ip -4 2>/dev/null" 2>/dev/null; then
        return 0
    fi
    
    log "WARN" "Could not get Tailscale IP for $hostname"
    return 1
}

test_server_connectivity() {
    local server="$1"
    local service="${2:-fks_user}"
    
    log "INFO" "Testing connectivity to $server..."
    
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$service@$server" "echo 'Connection successful'" 2>/dev/null; then
        log "SUCCESS" "Connected to $server"
        return 0
    else
        log "ERROR" "Cannot connect to $server"
        return 1
    fi
}

# =================================================================
# DEPLOYMENT FUNCTIONS
# =================================================================
deploy_auth_server() {
    local server="$1"
    local user="${2:-fks_user}"
    
    log "FKS" "Deploying Auth server to $server..."
    
    # Create deployment script for auth server
    cat > /tmp/deploy-auth.sh << 'EOF'
#!/bin/bash
set -euo pipefail

SERVICE_DIR="/home/fks_user/fks"
cd "$SERVICE_DIR"

echo "🔐 Deploying Auth Server (Authentik + Nginx)..."

# Pull latest images for auth services
docker compose -f docker-compose.auth.yml pull

# Start auth services
docker compose -f docker-compose.auth.yml up -d

# Wait for services to be ready
echo "⏳ Waiting for auth services to be ready..."
sleep 30

# Check service health
echo "🔍 Checking service health..."
docker compose -f docker-compose.auth.yml ps

# Test Authentik endpoint
if curl -f http://localhost:9000/api/v3/ping/ >/dev/null 2>&1; then
    echo "✅ Authentik is responding"
else
    echo "⚠️ Authentik may not be ready yet"
fi

echo "✅ Auth server deployment complete"
EOF
    
    # Copy and execute deployment script
    scp /tmp/deploy-auth.sh "$user@$server:/tmp/"
    ssh "$user@$server" "chmod +x /tmp/deploy-auth.sh && /tmp/deploy-auth.sh"
    
    # Clean up
    rm /tmp/deploy-auth.sh
    
    log "SUCCESS" "Auth server deployed to $server"
}

deploy_api_server() {
    local server="$1"
    local user="${2:-fks_user}"
    local auth_server="${3:-}"
    
    log "FKS" "Deploying API server to $server..."
    
    # Create deployment script for API server
    cat > /tmp/deploy-api.sh << 'APIEOF'
#!/bin/bash
set -euo pipefail

SERVICE_DIR="/home/fks_user/fks"
cd "$SERVICE_DIR"

echo "🚀 Deploying API Server (API + Workers + Data)..."

# Set auth server URL if provided
if [ -n "AUTH_SERVER_PLACEHOLDER" ]; then
    export AUTHENTIK_URL="https://AUTH_SERVER_PLACEHOLDER"
    echo "🔗 Using auth server: $AUTHENTIK_URL"
fi

# Pull latest images for API services
docker compose -f docker-compose.api.yml pull

# Start API services
docker compose -f docker-compose.api.yml up -d

# Wait for services to be ready
echo "⏳ Waiting for API services to be ready..."
sleep 60

# Check service health
echo "🔍 Checking service health..."
docker compose -f docker-compose.api.yml ps

# Test API endpoints
if curl -f http://localhost:8000/health >/dev/null 2>&1; then
    echo "✅ API is responding"
else
    echo "⚠️ API may not be ready yet"
fi

if curl -f http://localhost:9001/health >/dev/null 2>&1; then
    echo "✅ Data service is responding"
else
    echo "⚠️ Data service may not be ready yet"
fi

echo "✅ API server deployment complete"
APIEOF
    
    # Replace placeholder with actual auth server
    if [ -n "$auth_server" ]; then
        sed -i "s/AUTH_SERVER_PLACEHOLDER/$auth_server/g" /tmp/deploy-api.sh
    else
        sed -i "s/AUTH_SERVER_PLACEHOLDER//g" /tmp/deploy-api.sh
    fi
    
    # Copy and execute deployment script
    scp /tmp/deploy-api.sh "$user@$server:/tmp/"
    ssh "$user@$server" "chmod +x /tmp/deploy-api.sh && /tmp/deploy-api.sh"
    
    # Clean up
    rm /tmp/deploy-api.sh
    
    log "SUCCESS" "API server deployed to $server"
}

deploy_web_server() {
    local server="$1"
    local user="${2:-fks_user}"
    local auth_server="${3:-}"
    local api_server="${4:-}"
    
    log "FKS" "Deploying Web server to $server..."
    
    # Create deployment script for web server
    cat > /tmp/deploy-web.sh << 'WEBEOF'
#!/bin/bash
set -euo pipefail

SERVICE_DIR="/home/fks_user/fks"
cd "$SERVICE_DIR"

echo "🌐 Deploying Web Server (React + Nginx)..."

# Pull latest images for web services
docker compose -f docker-compose.web.yml pull

# Start web services
docker compose -f docker-compose.web.yml up -d

# Wait for services to be ready
echo "⏳ Waiting for web services to be ready..."
sleep 30

# Check service health
echo "🔍 Checking service health..."
docker compose -f docker-compose.web.yml ps

# Test web server
if curl -f http://localhost/ >/dev/null 2>&1; then
    echo "✅ Web server is responding"
else
    echo "⚠️ Web server may not be ready yet"
fi

echo "✅ Web server deployment complete"
WEBEOF
    
    # Copy and execute deployment script
    scp /tmp/deploy-web.sh "$user@$server:/tmp/"
    ssh "$user@$server" "chmod +x /tmp/deploy-web.sh && /tmp/deploy-web.sh"
    
    # Clean up
    rm /tmp/deploy-web.sh
    
    log "SUCCESS" "Web server deployed to $server"
}

deploy_single_server() {
    local server="$1"
    local user="${2:-fks_user}"
    
    log "FKS" "Deploying single-server FKS to $server..."
    
    # Create deployment script for single server
    cat > /tmp/deploy-single.sh << 'EOF'
#!/bin/bash
set -euo pipefail

SERVICE_DIR="/home/fks_user/fks"
cd "$SERVICE_DIR"

echo "🚀 Deploying FKS Single Server (All Services)..."

# Pull latest images
docker compose pull

# Start all services
docker compose up -d

# Wait for services to be ready
echo "⏳ Waiting for all services to be ready..."
sleep 90

# Check service health
echo "🔍 Checking service health..."
docker compose ps

# Test key endpoints
echo "🧪 Testing service endpoints..."

if curl -f http://localhost:8000/health >/dev/null 2>&1; then
    echo "✅ API is responding"
else
    echo "⚠️ API may not be ready yet"
fi

if curl -f http://localhost:3000/ >/dev/null 2>&1; then
    echo "✅ Web frontend is responding"
else
    echo "⚠️ Web frontend may not be ready yet"
fi

if curl -f http://localhost:9000/api/v3/ping/ >/dev/null 2>&1; then
    echo "✅ Authentik is responding"
else
    echo "⚠️ Authentik may not be ready yet"
fi

echo "✅ Single server deployment complete"
EOF
    
    # Copy and execute deployment script
    scp /tmp/deploy-single.sh "$user@$server:/tmp/"
    ssh "$user@$server" "chmod +x /tmp/deploy-single.sh && /tmp/deploy-single.sh"
    
    # Clean up
    rm /tmp/deploy-single.sh
    
    log "SUCCESS" "Single server deployed to $server"
}

# =================================================================
# DNS INTEGRATION
# =================================================================
update_dns_records() {
    local mode="$1"
    shift
    
    if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] || [ -z "${CLOUDFLARE_ZONE_ID:-}" ]; then
        log "WARN" "Cloudflare credentials not available - skipping DNS updates"
        return 0
    fi
    
    local dns_script="$ACTIONS_ROOT/scripts/dns/cloudflare-updater.sh"
    if [ ! -x "$dns_script" ]; then
        log "WARN" "DNS updater script not found - skipping DNS updates"
        return 0
    fi
    
    case "$mode" in
        "multi")
            local auth_server="$1"
            local api_server="$2"
            local web_server="$3"
            
            log "INFO" "Updating DNS for multi-server deployment..."
            
            # Get Tailscale IPs
            local auth_ip=$(get_tailscale_ip "$auth_server" || echo "")
            local api_ip=$(get_tailscale_ip "$api_server" || echo "")
            local web_ip=$(get_tailscale_ip "$web_server" || echo "")
            
            if [ -n "$auth_ip" ] || [ -n "$api_ip" ] || [ -n "$web_ip" ]; then
                "$dns_script" update-multi-server \
                    ${auth_ip:+--auth-ip "$auth_ip"} \
                    ${api_ip:+--api-ip "$api_ip"} \
                    ${web_ip:+--web-ip "$web_ip"}
            fi
            ;;
        "single")
            local server="$1"
            
            log "INFO" "Updating DNS for single-server deployment..."
            
            local server_ip=$(get_tailscale_ip "$server" || echo "")
            if [ -n "$server_ip" ]; then
                "$dns_script" update-service --service fks --ip "$server_ip"
            fi
            ;;
    esac
}

# =================================================================
# MAIN DEPLOYMENT LOGIC
# =================================================================
deploy_multi_server() {
    local auth_server="$1"
    local api_server="$2"
    local web_server="$3"
    local user="${4:-fks_user}"
    
    log "FKS" "Starting multi-server FKS deployment..."
    log "INFO" "Auth server: $auth_server"
    log "INFO" "API server: $api_server"
    log "INFO" "Web server: $web_server"
    
    # Test connectivity to all servers
    local all_connected=true
    for server in "$auth_server" "$api_server" "$web_server"; do
        if ! test_server_connectivity "$server" "$user"; then
            all_connected=false
        fi
    done
    
    if [ "$all_connected" != "true" ]; then
        log "ERROR" "Cannot connect to all servers - aborting deployment"
        exit 1
    fi
    
    # Deploy in order: Auth -> API -> Web
    deploy_auth_server "$auth_server" "$user"
    deploy_api_server "$api_server" "$user" "$auth_server"
    deploy_web_server "$web_server" "$user" "$auth_server" "$api_server"
    
    # Update DNS records
    update_dns_records "multi" "$auth_server" "$api_server" "$web_server"
    
    log "SUCCESS" "Multi-server FKS deployment complete!"
    log "INFO" "Services available at:"
    log "INFO" "  • Auth: https://auth.$DEFAULT_DOMAIN"
    log "INFO" "  • API: https://api.$DEFAULT_DOMAIN"
    log "INFO" "  • Trading: https://trading.$DEFAULT_DOMAIN"
    log "INFO" "  • Web: https://fks.$DEFAULT_DOMAIN"
}

deploy_single_server_mode() {
    local server="$1"
    local user="${2:-fks_user}"
    
    log "FKS" "Starting single-server FKS deployment..."
    log "INFO" "Server: $server"
    
    # Test connectivity
    if ! test_server_connectivity "$server" "$user"; then
        log "ERROR" "Cannot connect to server - aborting deployment"
        exit 1
    fi
    
    # Deploy all services
    deploy_single_server "$server" "$user"
    
    # Update DNS records
    update_dns_records "single" "$server"
    
    log "SUCCESS" "Single-server FKS deployment complete!"
    log "INFO" "Services available at:"
    log "INFO" "  • Main app: https://fks.$DEFAULT_DOMAIN"
    log "INFO" "  • API: https://api.$DEFAULT_DOMAIN"
    log "INFO" "  • Auth: https://auth.$DEFAULT_DOMAIN"
}

# =================================================================
# HEALTH CHECK FUNCTIONS
# =================================================================
health_check() {
    local mode="$1"
    shift
    
    log "INFO" "Running health checks..."
    
    case "$mode" in
        "multi")
            local auth_server="$1"
            local api_server="$2"
            local web_server="$3"
            local user="${4:-fks_user}"
            
            # Check each server
            for server_info in "Auth:$auth_server:9000" "API:$api_server:8000" "Web:$web_server:80"; do
                IFS=':' read -r name server port <<< "$server_info"
                log "INFO" "Checking $name server ($server)..."
                
                if ssh "$user@$server" "curl -f http://localhost:$port/health 2>/dev/null || curl -f http://localhost:$port/ 2>/dev/null" >/dev/null 2>&1; then
                    log "SUCCESS" "$name server is healthy"
                else
                    log "WARN" "$name server health check failed"
                fi
            done
            ;;
        "single")
            local server="$1"
            local user="${2:-fks_user}"
            
            log "INFO" "Checking single server ($server)..."
            
            for service_info in "API:8000" "Web:3000" "Auth:9000"; do
                IFS=':' read -r name port <<< "$service_info"
                if ssh "$user@$server" "curl -f http://localhost:$port/health 2>/dev/null || curl -f http://localhost:$port/ 2>/dev/null" >/dev/null 2>&1; then
                    log "SUCCESS" "$name service is healthy"
                else
                    log "WARN" "$name service health check failed"
                fi
            done
            ;;
    esac
}

# =================================================================
# COMMAND LINE INTERFACE
# =================================================================
show_help() {
    cat << EOF
FKS Service Manager - Multi-Server Deployment Tool

Usage: $0 COMMAND [OPTIONS]

Commands:
  deploy              Deploy FKS services
  health-check        Check service health
  update-dns          Update DNS records only

Deploy Options:
  --mode MODE         Deployment mode: single|multi (required)
  --server SERVER     Server hostname (for single mode)
  --auth-server HOST  Auth server hostname (for multi mode)
  --api-server HOST   API server hostname (for multi mode)
  --web-server HOST   Web server hostname (for multi mode)
  --user USER         SSH user (default: fks_user)

Examples:
  # Single server deployment
  $0 deploy --mode single --server fks.7gram.xyz

  # Multi-server deployment
  $0 deploy --mode multi \\
    --auth-server auth.7gram.xyz \\
    --api-server api.7gram.xyz \\
    --web-server web.7gram.xyz

  # Health check
  $0 health-check --mode multi \\
    --auth-server auth.7gram.xyz \\
    --api-server api.7gram.xyz \\
    --web-server web.7gram.xyz

Environment Variables:
  CLOUDFLARE_API_TOKEN   Cloudflare API token (for DNS updates)
  CLOUDFLARE_ZONE_ID     Cloudflare zone ID (for DNS updates)

EOF
}

# Parse command line arguments
main() {
    local command=""
    local mode=""
    local server=""
    local auth_server=""
    local api_server=""
    local web_server=""
    local user="fks_user"
    
    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            deploy)
                command="deploy"
                shift
                ;;
            health-check)
                command="health-check"
                shift
                ;;
            update-dns)
                command="update-dns"
                shift
                ;;
            --mode)
                mode="$2"
                shift 2
                ;;
            --server)
                server="$2"
                shift 2
                ;;
            --auth-server)
                auth_server="$2"
                shift 2
                ;;
            --api-server)
                api_server="$2"
                shift 2
                ;;
            --web-server)
                web_server="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    check_dependencies
    
    case "$command" in
        "deploy")
            case "$mode" in
                "single")
                    if [ -z "$server" ]; then
                        log "ERROR" "Server hostname is required for single mode"
                        exit 1
                    fi
                    deploy_single_server_mode "$server" "$user"
                    ;;
                "multi")
                    if [ -z "$auth_server" ] || [ -z "$api_server" ] || [ -z "$web_server" ]; then
                        log "ERROR" "All three server hostnames are required for multi mode"
                        exit 1
                    fi
                    deploy_multi_server "$auth_server" "$api_server" "$web_server" "$user"
                    ;;
                *)
                    log "ERROR" "Mode must be 'single' or 'multi'"
                    exit 1
                    ;;
            esac
            ;;
        "health-check")
            case "$mode" in
                "single")
                    if [ -z "$server" ]; then
                        log "ERROR" "Server hostname is required for single mode"
                        exit 1
                    fi
                    health_check "single" "$server" "$user"
                    ;;
                "multi")
                    if [ -z "$auth_server" ] || [ -z "$api_server" ] || [ -z "$web_server" ]; then
                        log "ERROR" "All three server hostnames are required for multi mode"
                        exit 1
                    fi
                    health_check "multi" "$auth_server" "$api_server" "$web_server" "$user"
                    ;;
                *)
                    log "ERROR" "Mode must be 'single' or 'multi'"
                    exit 1
                    ;;
            esac
            ;;
        "update-dns")
            case "$mode" in
                "single")
                    if [ -z "$server" ]; then
                        log "ERROR" "Server hostname is required for single mode"
                        exit 1
                    fi
                    update_dns_records "single" "$server"
                    ;;
                "multi")
                    if [ -z "$auth_server" ] || [ -z "$api_server" ] || [ -z "$web_server" ]; then
                        log "ERROR" "All three server hostnames are required for multi mode"
                        exit 1
                    fi
                    update_dns_records "multi" "$auth_server" "$api_server" "$web_server"
                    ;;
                *)
                    log "ERROR" "Mode must be 'single' or 'multi'"
                    exit 1
                    ;;
            esac
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
