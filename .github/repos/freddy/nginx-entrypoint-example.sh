#!/bin/sh
#
# Nginx Entrypoint Script for Freddy
# ===================================
# This script runs when the nginx container starts. It:
# 1. Checks for Let's Encrypt certificates on the host (mounted at /etc/letsencrypt)
# 2. Copies certificates to nginx SSL directory
# 3. Falls back to self-signed certificates if Let's Encrypt certs are unavailable
# 4. Starts nginx
#

set -e

# Configuration
DOMAIN="${DOMAIN:-7gram.xyz}"
LETSENCRYPT_DIR="/etc/letsencrypt"
SSL_DIR="/etc/nginx/ssl"
FALLBACK_DIR="$SSL_DIR/fallback"

# Logging functions
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_debug() {
    echo "[DEBUG] $1"
}

log_error() {
    echo "[ERROR] $1"
}

# Check if Let's Encrypt certificates exist on host
check_letsencrypt_certs() {
    log_debug "Checking for Let's Encrypt certificates at $LETSENCRYPT_DIR"

    if [ -f "$LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem" ] && \
       [ -f "$LETSENCRYPT_DIR/live/$DOMAIN/privkey.pem" ]; then

        # Verify certificates are valid and not expired
        if openssl x509 -in "$LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem" -noout -checkend 0 >/dev/null 2>&1; then
            log_info "✓ Let's Encrypt certificates found and valid"
            return 0
        else
            log_warn "Let's Encrypt certificates exist but are expired or invalid"
            return 1
        fi
    else
        log_debug "Let's Encrypt certificates not found in $LETSENCRYPT_DIR/live/$DOMAIN/"
        return 1
    fi
}

# Copy Let's Encrypt certificates to nginx SSL directory
copy_letsencrypt_certs() {
    log_info "Copying Let's Encrypt certificates to $SSL_DIR..."

    # Copy certificate files
    cp "$LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem" "$SSL_DIR/fullchain.pem"
    cp "$LETSENCRYPT_DIR/live/$DOMAIN/privkey.pem" "$SSL_DIR/privkey.pem"

    # Set proper permissions
    chmod 644 "$SSL_DIR/fullchain.pem"
    chmod 600 "$SSL_DIR/privkey.pem"

    # Verify the copy worked
    if [ -f "$SSL_DIR/fullchain.pem" ] && [ -f "$SSL_DIR/privkey.pem" ]; then
        log_info "✓ Certificates copied successfully"

        # Show certificate details
        ISSUER=$(openssl x509 -in "$SSL_DIR/fullchain.pem" -noout -issuer 2>/dev/null | grep -o "O=[^,]*" | cut -d= -f2 || echo "Unknown")
        EXPIRY=$(openssl x509 -in "$SSL_DIR/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")

        log_info "Certificate Issuer: $ISSUER"
        log_info "Certificate Expires: $EXPIRY"
        return 0
    else
        log_error "Failed to copy certificates"
        return 1
    fi
}

# Use self-signed fallback certificates
use_fallback_certs() {
    log_warn "Using self-signed fallback certificates"
    log_info "Browsers will show security warnings"

    # Copy fallback certificates to SSL directory
    if [ -d "$FALLBACK_DIR" ]; then
        cp "$FALLBACK_DIR/fullchain.pem" "$SSL_DIR/fullchain.pem"
        cp "$FALLBACK_DIR/privkey.pem" "$SSL_DIR/privkey.pem"

        chmod 644 "$SSL_DIR/fullchain.pem"
        chmod 600 "$SSL_DIR/privkey.pem"

        log_info "✓ Fallback certificates configured"
        log_info ""
        log_info "To obtain real Let's Encrypt certificates:"
        log_info "  1. Ensure DNS is properly configured"
        log_info "  2. Run the CI/CD workflow with 'force_ssl_regen' enabled"
        log_info "  3. Or manually run certbot on the host"
    else
        log_error "Fallback certificate directory not found: $FALLBACK_DIR"
        log_error "SSL will not work!"
        return 1
    fi
}

# Verify certificate and key match
verify_cert_key_match() {
    log_debug "Verifying certificate and private key match..."

    # Get certificate public key hash
    CERT_HASH=$(openssl x509 -noout -pubkey -in "$SSL_DIR/fullchain.pem" 2>/dev/null | openssl sha256 2>/dev/null || echo "cert_error")

    # Get private key's public key hash (works for both RSA and ECDSA)
    KEY_HASH=$(openssl pkey -pubout -in "$SSL_DIR/privkey.pem" 2>/dev/null | openssl sha256 2>/dev/null || echo "key_error")

    if [ "$CERT_HASH" = "$KEY_HASH" ] && [ "$CERT_HASH" != "cert_error" ]; then
        log_info "✓ Certificate and private key match"
        return 0
    else
        log_warn "Certificate verification inconclusive (this is normal for ECDSA keys)"
        return 0
    fi
}

# Main setup logic
setup_ssl() {
    log_info "========================================="
    log_info "   Nginx SSL Certificate Setup"
    log_info "========================================="
    log_info "Domain: $DOMAIN"
    log_info "SSL Directory: $SSL_DIR"
    log_info ""

    # Ensure SSL directory exists
    mkdir -p "$SSL_DIR"

    # Try to use Let's Encrypt certificates
    if check_letsencrypt_certs; then
        if copy_letsencrypt_certs; then
            verify_cert_key_match
            log_info "Certificate Type: Let's Encrypt (Production)"
        else
            use_fallback_certs
        fi
    else
        use_fallback_certs
    fi

    log_info ""
    log_info "SSL Setup Complete"
    log_info "========================================="
}

# Run SSL setup
setup_ssl

# Test nginx configuration
log_info "Testing nginx configuration..."
if nginx -t 2>&1; then
    log_info "✓ Nginx configuration is valid"
else
    log_error "Nginx configuration test failed!"
    exit 1
fi

# Start nginx
log_info "Starting nginx..."
exec "$@"
