#!/bin/bash
#
# SSL Deployment Setup Checker
# =============================
# Validates that all prerequisites are in place for automated SSL certificate deployment
#
# Usage: ./check-ssl-setup.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN++))
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if running as root or with sudo
check_permissions() {
    if [ "$EUID" -eq 0 ]; then
        print_pass "Running as root"
        SUDO_CMD=""
    elif sudo -n true 2>/dev/null; then
        print_pass "Sudo access available (passwordless)"
        SUDO_CMD="sudo"
    else
        print_warn "Not running as root and sudo not available"
        print_info "Some checks may be limited"
        SUDO_CMD="sudo"
    fi
}

# Check Docker volume
check_docker_volume() {
    print_header "DOCKER VOLUME CHECK"

    if $SUDO_CMD docker volume inspect ssl-certs >/dev/null 2>&1; then
        print_pass "ssl-certs volume exists"

        # Check volume contents
        CERT_FILES=$($SUDO_CMD docker run --rm -v ssl-certs:/certs:ro busybox ls /certs/live/7gram.xyz/ 2>/dev/null | wc -l || echo "0")

        if [ "$CERT_FILES" -gt 0 ]; then
            print_pass "Certificate files found in volume ($CERT_FILES files)"

            # Check if fullchain.pem exists
            if $SUDO_CMD docker run --rm -v ssl-certs:/certs:ro busybox test -f /certs/live/7gram.xyz/fullchain.pem 2>/dev/null; then
                print_pass "fullchain.pem exists"

                # Check certificate issuer
                ISSUER=$($SUDO_CMD docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -issuer 2>/dev/null | grep -o "O=[^,]*" | cut -d= -f2)

                if [[ "$ISSUER" == *"Let's Encrypt"* ]]; then
                    print_pass "Certificate issued by: $ISSUER"
                else
                    print_warn "Certificate issued by: $ISSUER (expected Let's Encrypt)"
                fi

                # Check expiry
                EXPIRY=$($SUDO_CMD docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -enddate 2>/dev/null | cut -d= -f2)
                print_info "Certificate expires: $EXPIRY"
            else
                print_fail "fullchain.pem not found in volume"
            fi

            # Check if privkey.pem exists
            if $SUDO_CMD docker run --rm -v ssl-certs:/certs:ro busybox test -f /certs/live/7gram.xyz/privkey.pem 2>/dev/null; then
                print_pass "privkey.pem exists"
            else
                print_fail "privkey.pem not found in volume"
            fi
        else
            print_fail "No certificate files in volume"
            print_info "Volume exists but is empty - run CI/CD with force_ssl_regen"
        fi
    else
        print_fail "ssl-certs volume does not exist"
        print_info "Volume will be created during first deployment"
    fi
}

# Check nginx container
check_nginx_container() {
    print_header "NGINX CONTAINER CHECK"

    if $SUDO_CMD docker ps --format '{{.Names}}' | grep -q "^nginx$"; then
        print_pass "nginx container is running"

        # Check volume mount
        MOUNT_CHECK=$($SUDO_CMD docker inspect nginx --format '{{range .Mounts}}{{if eq .Destination "/etc/letsencrypt-volume"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)

        if [ -n "$MOUNT_CHECK" ]; then
            print_pass "ssl-certs volume mounted at /etc/letsencrypt-volume"
        else
            print_fail "ssl-certs volume not mounted to nginx container"
            print_info "Check docker-compose.yml volume configuration"
        fi

        # Check certificate files inside nginx
        if $SUDO_CMD docker exec nginx test -f /etc/nginx/ssl/fullchain.pem 2>/dev/null; then
            print_pass "Certificate copied to /etc/nginx/ssl/fullchain.pem"

            # Check what nginx is serving
            NGINX_ISSUER=$($SUDO_CMD docker exec nginx openssl x509 -in /etc/nginx/ssl/fullchain.pem -noout -issuer 2>/dev/null | grep -o "O=[^,]*" | cut -d= -f2 || echo "unknown")

            if [[ "$NGINX_ISSUER" == *"Let's Encrypt"* ]]; then
                print_pass "Nginx using Let's Encrypt certificate"
            else
                print_warn "Nginx using certificate from: $NGINX_ISSUER"
                if [[ "$NGINX_ISSUER" == *"Freddy"* ]]; then
                    print_info "Self-signed certificate detected - need to deploy real certs"
                fi
            fi
        else
            print_fail "No certificate file at /etc/nginx/ssl/fullchain.pem"
        fi

        # Check nginx logs for SSL setup
        print_info "Recent SSL-related nginx logs:"
        $SUDO_CMD docker logs nginx --tail 100 2>&1 | grep -i "ssl\|certificate" | tail -5 | sed 's/^/  /'
    else
        print_fail "nginx container is not running"
        print_info "Start with: cd ~/freddy && docker compose up -d nginx"
    fi
}

# Check what certificate is being served to clients
check_served_certificate() {
    print_header "CERTIFICATE BEING SERVED"

    if command -v openssl >/dev/null 2>&1; then
        SERVED_ISSUER=$(timeout 5 openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | grep -o "O=[^,]*" | cut -d= -f2 || echo "")

        if [ -n "$SERVED_ISSUER" ]; then
            if [[ "$SERVED_ISSUER" == *"Let's Encrypt"* ]]; then
                print_pass "7gram.xyz serves Let's Encrypt certificate"
            else
                print_warn "7gram.xyz serves certificate from: $SERVED_ISSUER"
                if [[ "$SERVED_ISSUER" == *"Freddy"* ]]; then
                    print_info "Self-signed certificate detected"
                fi
            fi

            # Check expiry of served cert
            SERVED_EXPIRY=$(timeout 5 openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
            if [ -n "$SERVED_EXPIRY" ]; then
                print_info "Certificate expires: $SERVED_EXPIRY"
            fi
        else
            print_fail "Could not retrieve certificate from 7gram.xyz:443"
            print_info "Check if port 443 is accessible"
        fi
    else
        print_warn "openssl command not found - cannot check served certificate"
    fi
}

# Check SSH access
check_ssh_access() {
    print_header "SSH ACCESS CHECK"

    if [ -f ~/.ssh/id_rsa ] || [ -f ~/.ssh/id_ed25519 ]; then
        print_pass "SSH private key found in ~/.ssh/"
    else
        print_warn "No SSH private key found in ~/.ssh/"
        print_info "GitHub Actions will use SSH_KEY secret"
    fi

    # Check if running on Freddy server
    if [ -d ~/freddy ]; then
        print_pass "Found ~/freddy directory (running on Freddy server)"

        if [ -f ~/freddy/docker-compose.yml ]; then
            print_pass "docker-compose.yml exists"
        else
            print_fail "docker-compose.yml not found in ~/freddy"
        fi
    else
        print_info "Not running on Freddy server (running locally or in CI)"
    fi
}

# Check required commands
check_commands() {
    print_header "REQUIRED COMMANDS"

    local required_commands=("docker" "openssl")

    for cmd in "${required_commands[@]}"; do
        if command -v $cmd >/dev/null 2>&1; then
            print_pass "$cmd is installed"
        else
            print_fail "$cmd is not installed"
        fi
    done
}

# Check GitHub secrets (if running in GitHub Actions)
check_github_secrets() {
    print_header "GITHUB ACTIONS ENVIRONMENT"

    if [ -n "$GITHUB_ACTIONS" ]; then
        print_pass "Running in GitHub Actions"

        # Check for required secrets (can't actually see values, but can check if they exist)
        local secrets=("SSH_KEY" "ROOT_SSH_KEY" "CLOUDFLARE_API_TOKEN" "SSL_EMAIL" "FREDDY_TAILSCALE_IP")

        for secret in "${secrets[@]}"; do
            if [ -n "${!secret}" ]; then
                print_pass "$secret is set"
            else
                print_warn "$secret is not set or empty"
            fi
        done
    else
        print_info "Not running in GitHub Actions"
        print_info "GitHub secrets will be checked during CI/CD run"
    fi
}

# Main execution
main() {
    clear
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║          SSL Certificate Deployment Setup Checker               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"

    check_permissions
    check_commands
    check_ssh_access
    check_docker_volume
    check_nginx_container
    check_served_certificate
    check_github_secrets

    # Summary
    print_header "SUMMARY"

    TOTAL=$((PASS + FAIL + WARN))

    echo ""
    echo "Results:"
    echo -e "  ${GREEN}✓ Passed:${NC} $PASS"
    echo -e "  ${RED}✗ Failed:${NC} $FAIL"
    echo -e "  ${YELLOW}⚠ Warnings:${NC} $WARN"
    echo -e "  Total Checks: $TOTAL"
    echo ""

    if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}All checks passed! SSL setup is ready for deployment.${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
        exit 0
    elif [ $FAIL -eq 0 ]; then
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}Setup is functional but has warnings. Review above.${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
        exit 0
    else
        echo -e "${RED}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}Setup has failures. Please address the issues above.${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Common fixes:"
        echo "  • Missing certificates: Run CI/CD workflow with force_ssl_regen=true"
        echo "  • Container not running: cd ~/freddy && docker compose up -d"
        echo "  • Permission errors: Ensure ROOT_SSH_KEY secret is configured"
        echo ""
        exit 1
    fi
}

# Run main function
main
