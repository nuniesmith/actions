# Migrating to Host-Based SSL Certificate Storage

## Overview

This guide explains how to update your Freddy setup to store SSL certificates on the host filesystem (`/etc/letsencrypt`) instead of using Docker volumes. This approach is simpler, avoids permission issues, and makes certificates easier to manage.

## Benefits

- ✅ **No Docker volume permission issues** - certificates stored on regular filesystem
- ✅ **Easier to manage** - can view/edit certificates directly with `ls /etc/letsencrypt`
- ✅ **Easier to backup** - standard filesystem backup tools work
- ✅ **No container rebuilds needed** - certificates mount at runtime
- ✅ **Works with existing tools** - certbot can write directly to `/etc/letsencrypt`

## Architecture Change

### Before (Docker Volume)
```
CI/CD → Docker Volume (ssl-certs) → Nginx Container
        (permission issues)         (mounts volume)
```

### After (Host Path)
```
CI/CD → Host /etc/letsencrypt → Nginx Container
        (standard filesystem)   (mounts host path)
```

## Required Changes

### 1. Update docker-compose.yml

**Location:** `~/freddy/docker-compose.yml`

Find the nginx service and update the volumes section:

#### Before:
```yaml
services:
  nginx:
    container_name: nginx
    # ... other config ...
    volumes:
      - ssl-certs:/etc/letsencrypt-volume:ro
      - ./config/nginx:/etc/nginx/conf.d:ro
      # ... other volumes ...

volumes:
  ssl-certs:
    external: true
```

#### After:
```yaml
services:
  nginx:
    container_name: nginx
    # ... other config ...
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
      - ./config/nginx:/etc/nginx/conf.d:ro
      # ... other volumes ...

# Remove ssl-certs from volumes section (or comment it out)
volumes:
  # ssl-certs:  # No longer needed
  #   external: true
  photoprism_storage:
    # ... other volumes remain ...
```

**Key changes:**
- Replace `ssl-certs:/etc/letsencrypt-volume:ro` with `/etc/letsencrypt:/etc/letsencrypt:ro`
- Remove or comment out the `ssl-certs` volume definition
- The mount is read-only (`:ro`) for security

### 2. Update Nginx Entrypoint Script

**Location:** `~/freddy/docker/nginx/entrypoint.sh` or wherever your nginx entrypoint is

#### Before:
```bash
VOLUME_DIR="/etc/letsencrypt-volume"

# Check for certificates in volume
if [ -f "$VOLUME_DIR/live/$DOMAIN/fullchain.pem" ]; then
  # Copy from volume to /etc/nginx/ssl/
  cp "$VOLUME_DIR/live/$DOMAIN/fullchain.pem" /etc/nginx/ssl/
  cp "$VOLUME_DIR/live/$DOMAIN/privkey.pem" /etc/nginx/ssl/
fi
```

#### After:
```bash
LETSENCRYPT_DIR="/etc/letsencrypt"

# Check for certificates on host
if [ -f "$LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem" ]; then
  # Copy from letsencrypt to /etc/nginx/ssl/
  cp "$LETSENCRYPT_DIR/live/$DOMAIN/fullchain.pem" /etc/nginx/ssl/
  cp "$LETSENCRYPT_DIR/live/$DOMAIN/privkey.pem" /etc/nginx/ssl/
fi
```

**Alternative: Direct use (no copy)**

You can also configure nginx to use certificates directly from `/etc/letsencrypt`:

```nginx
server {
    listen 443 ssl http2;
    server_name 7gram.xyz;
    
    # Use certificates directly from mounted path
    ssl_certificate /etc/letsencrypt/live/7gram.xyz/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/7gram.xyz/privkey.pem;
    
    # ... rest of config ...
}
```

### 3. Create /etc/letsencrypt Directory on Host

On the Freddy server:

```bash
# As root or with sudo
sudo mkdir -p /etc/letsencrypt
sudo chmod 755 /etc/letsencrypt

# Optional: Create expected subdirectories
sudo mkdir -p /etc/letsencrypt/{live,archive,renewal}
sudo chmod 755 /etc/letsencrypt/{live,archive,renewal}
```

## Migration Steps

### Step 1: Backup Existing Certificates (if any)

If you have certificates in the Docker volume, back them up first:

```bash
# Extract from Docker volume to temporary location
docker run --rm \
  -v ssl-certs:/certs:ro \
  -v /tmp:/backup \
  busybox:latest \
  tar -czf /backup/ssl-certs-backup.tar.gz -C /certs .

# Verify backup
ls -lh /tmp/ssl-certs-backup.tar.gz
```

### Step 2: Update docker-compose.yml

```bash
cd ~/freddy

# Backup current docker-compose.yml
cp docker-compose.yml docker-compose.yml.backup

# Edit docker-compose.yml
nano docker-compose.yml

# Make the changes described in section 1 above
```

### Step 3: Update CI/CD Configuration

The CI/CD workflow has already been updated to use `deploy-method: host-path`. No additional changes needed.

### Step 4: Stop Services

```bash
cd ~/freddy
docker compose down
```

### Step 5: Prepare Host Directory

```bash
# Create directory structure
sudo mkdir -p /etc/letsencrypt

# If you have a backup, restore it
if [ -f /tmp/ssl-certs-backup.tar.gz ]; then
  sudo tar -xzf /tmp/ssl-certs-backup.tar.gz -C /etc/letsencrypt
  sudo chmod -R 755 /etc/letsencrypt
  sudo chmod 600 /etc/letsencrypt/archive/*/privkey*.pem 2>/dev/null || true
fi

# Set proper ownership (nginx usually runs as nginx or www-data)
sudo chown -R root:root /etc/letsencrypt
```

### Step 6: Start Services

```bash
cd ~/freddy
docker compose up -d
```

### Step 7: Verify

```bash
# Check nginx logs
docker logs nginx --tail 50

# Verify certificate mount
docker exec nginx ls -la /etc/letsencrypt/live/

# Test HTTPS
curl -vI https://7gram.xyz 2>&1 | grep -i "issuer"
```

## CI/CD Workflow Usage

The CI/CD workflow has been updated. When you run it:

1. **Force SSL regeneration:**
   - Enable `force_ssl_regen` input
   - This cleans `/etc/letsencrypt` on host and regenerates certificates

2. **Normal deployment:**
   - Certificates are generated and deployed to `/etc/letsencrypt`
   - Nginx automatically picks them up on restart

3. **Automatic renewal:**
   - Weekly cron job regenerates certificates
   - They're deployed to `/etc/letsencrypt`
   - Nginx uses updated certificates after restart

## Verification Commands

### Check Certificates on Host
```bash
# List certificate files
sudo ls -la /etc/letsencrypt/live/7gram.xyz/

# View certificate details
sudo openssl x509 -in /etc/letsencrypt/live/7gram.xyz/fullchain.pem -noout -text

# Check issuer
sudo openssl x509 -in /etc/letsencrypt/live/7gram.xyz/fullchain.pem -noout -issuer

# Expected: issuer=C=US, O=Let's Encrypt, CN=R3
```

### Check Nginx Container
```bash
# Verify mount
docker inspect nginx | grep -A 10 Mounts

# Check if nginx can see certificates
docker exec nginx ls -la /etc/letsencrypt/live/

# Check what nginx is using
docker exec nginx cat /etc/nginx/conf.d/*.conf | grep ssl_certificate
```

### Check What's Being Served
```bash
# Quick check
openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null 2>/dev/null | openssl x509 -noout -issuer -dates

# Full certificate
echo | openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz 2>/dev/null | openssl x509 -text
```

## Troubleshooting

### Nginx Can't Read Certificates

**Symptom:** Nginx logs show permission denied errors

**Solution:**
```bash
# Check permissions
sudo ls -la /etc/letsencrypt/live/7gram.xyz/

# Fix permissions (certificates should be world-readable, keys should not)
sudo chmod 755 /etc/letsencrypt
sudo chmod 755 /etc/letsencrypt/live
sudo chmod 755 /etc/letsencrypt/live/7gram.xyz
sudo chmod 644 /etc/letsencrypt/live/7gram.xyz/fullchain.pem
sudo chmod 644 /etc/letsencrypt/live/7gram.xyz/cert.pem
sudo chmod 644 /etc/letsencrypt/live/7gram.xyz/chain.pem
sudo chmod 600 /etc/letsencrypt/archive/7gram.xyz/privkey*.pem

# Note: live/ contains symlinks, archive/ contains actual files
```

### Certificates Not Updating

**Symptom:** New certificates deployed but nginx still uses old ones

**Solution:**
```bash
# Restart nginx to reload certificates
cd ~/freddy
docker compose restart nginx

# Or force recreate
docker compose up -d --force-recreate nginx
```

### Directory Not Mounting

**Symptom:** `/etc/letsencrypt` is empty inside container

**Solution:**
```bash
# Check docker-compose.yml syntax
cd ~/freddy
docker compose config

# Verify volume mount
docker inspect nginx --format='{{json .Mounts}}' | jq

# Recreate container
docker compose up -d --force-recreate nginx
```

## Rollback Plan

If you need to revert to Docker volumes:

```bash
# Stop services
cd ~/freddy
docker compose down

# Restore backup docker-compose.yml
cp docker-compose.yml.backup docker-compose.yml

# Recreate volume if needed
docker volume create ssl-certs

# Restore certificates to volume (if you have backup)
docker run --rm \
  -v ssl-certs:/certs \
  -v /tmp:/backup \
  busybox:latest \
  tar -xzf /backup/ssl-certs-backup.tar.gz -C /certs

# Start services
docker compose up -d

# Update CI/CD workflow to use deploy-method: docker-volume
```

## Security Considerations

1. **File Permissions:**
   - `/etc/letsencrypt` and subdirectories: `755` (readable by all)
   - Certificate files (`*.pem` except privkey): `644` (readable by all)
   - Private keys (`privkey*.pem`): `600` (readable only by root)

2. **Container Access:**
   - Mounted read-only (`:ro`) in nginx container
   - Container cannot modify host certificates
   - Prevents container compromise from affecting certificates

3. **Backup Strategy:**
   - Include `/etc/letsencrypt` in server backups
   - Store backup securely (private keys are sensitive)
   - Test restoration procedure periodically

## Benefits Recap

| Aspect | Docker Volume | Host Path |
|--------|---------------|-----------|
| **Permissions** | Complex (requires root/sudo) | Simple (standard filesystem) |
| **Viewing** | Need docker run commands | Direct: `cat /etc/letsencrypt/...` |
| **Backup** | Need docker commands | Standard tools (rsync, tar, etc.) |
| **Debugging** | Indirect through container | Direct filesystem access |
| **CI/CD** | Requires elevated privileges | Works with standard SSH |
| **Portability** | Tied to Docker | Standard Linux approach |

## Next Steps

1. ✅ Review this guide
2. ⏳ Backup existing certificates (if any)
3. ⏳ Update docker-compose.yml
4. ⏳ Update nginx entrypoint script
5. ⏳ Create `/etc/letsencrypt` on host
6. ⏳ Restart services
7. ⏳ Run CI/CD with `force_ssl_regen: true`
8. ⏳ Verify certificates in browser

## Support Files

- **CI/CD Workflow:** `.github/servers/freddy/ci-cd.yml` (already updated)
- **SSL Action:** `.github/actions/ssl-certbot-cloudflare/action.yml` (already updated)
- **Setup Guide:** `.github/servers/freddy/QUICKSTART.md`
- **Full Docs:** `.github/servers/freddy/SSL_FIX_README.md`

---

**Status:** Ready to implement  
**Risk:** Low (easy rollback available)  
**Downtime:** ~2 minutes (during container restart)  
**Compatibility:** Works with all existing certificates