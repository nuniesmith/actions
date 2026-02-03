# Host-Based SSL Certificates - Quick Reference Card

## 🎯 What to Change

### 1. docker-compose.yml
```yaml
# BEFORE
volumes:
  - ssl-certs:/etc/letsencrypt-volume:ro

# AFTER
volumes:
  - /etc/letsencrypt:/etc/letsencrypt:ro
```

### 2. Nginx Entrypoint Script
```bash
# BEFORE
VOLUME_DIR="/etc/letsencrypt-volume"

# AFTER
LETSENCRYPT_DIR="/etc/letsencrypt"
```

### 3. Remove from volumes section
```yaml
# DELETE OR COMMENT OUT
volumes:
  # ssl-certs:
  #   external: true
```

---

## ⚡ Commands

### Setup
```bash
# Create directory
sudo mkdir -p /etc/letsencrypt
sudo chmod 755 /etc/letsencrypt

# Update docker-compose.yml
cd ~/freddy
nano docker-compose.yml  # Make changes above

# Restart
docker compose down
docker compose up -d
```

### Deploy Certificates
```bash
# Via CI/CD (recommended)
# GitHub Actions → Freddy Deploy → force_ssl_regen ✅

# Or manually check if they exist
sudo ls -la /etc/letsencrypt/live/7gram.xyz/
```

### Verify
```bash
# On host
sudo ls -la /etc/letsencrypt/live/7gram.xyz/

# In container
docker exec nginx ls -la /etc/letsencrypt/live/

# In browser
https://7gram.xyz → Lock icon → Certificate → Should say "Let's Encrypt"

# Command line
openssl s_client -connect 7gram.xyz:443 < /dev/null 2>&1 | grep "issuer"
# Should show: O=Let's Encrypt
```

---

## 🐛 Quick Fixes

### Nginx can't read certs
```bash
sudo chmod -R 755 /etc/letsencrypt
sudo chmod 600 /etc/letsencrypt/archive/*/privkey*.pem
docker compose restart nginx
```

### Mount not working
```bash
# Check syntax
docker compose config

# Force recreate
docker compose up -d --force-recreate nginx
```

### Old certificates
```bash
docker compose restart nginx
```

---

## 📋 Checklist

- [ ] Update `docker-compose.yml` (change volume mount)
- [ ] Update nginx entrypoint (change directory path)
- [ ] Create `/etc/letsencrypt` on host
- [ ] Restart nginx container
- [ ] Run CI/CD with `force_ssl_regen`
- [ ] Verify browser shows Let's Encrypt cert
- [ ] Verify `ls /etc/letsencrypt/live/7gram.xyz/` works

---

## 🎯 One-Liner Migration

```bash
sudo mkdir -p /etc/letsencrypt && \
sudo chmod 755 /etc/letsencrypt && \
cd ~/freddy && \
cp docker-compose.yml docker-compose.yml.backup && \
sed -i 's|ssl-certs:/etc/letsencrypt-volume:ro|/etc/letsencrypt:/etc/letsencrypt:ro|g' docker-compose.yml && \
docker compose down && \
docker compose up -d && \
echo "✅ Migration complete - now run CI/CD with force_ssl_regen"
```

**Note:** This assumes standard setup. Verify changes before running!

---

## 📖 Full Docs

- **Complete Guide:** `HOST_SSL_MIGRATION.md`
- **Summary:** `HOST_SSL_SUMMARY.md`
- **Examples:** `nginx-entrypoint-example.sh`, `docker-compose-nginx-example.yml`

---

**Time Required:** 10 minutes  
**Downtime:** 2 minutes  
**Risk:** Low (easy rollback)