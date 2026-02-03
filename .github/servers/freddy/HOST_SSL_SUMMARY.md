# Host-Based SSL Certificate Storage - Implementation Summary

**Date:** 2025-02-03  
**Server:** Freddy  
**Change:** Migrate from Docker volume to host filesystem for SSL certificates

---

## 🎯 What Changed

### Before
- SSL certificates stored in Docker volume (`ssl-certs`)
- Required root/sudo access to write to volume
- `actions` user couldn't deploy certificates (permission issues)
- Harder to view/manage certificates
- Nginx mounted volume at `/etc/letsencrypt-volume`

### After
- SSL certificates stored on host at `/etc/letsencrypt`
- Standard filesystem permissions (no Docker volume complexity)
- CI/CD deploys directly to host filesystem
- Easy to view: `ls /etc/letsencrypt/live/7gram.xyz/`
- Nginx mounts host path at `/etc/letsencrypt`

---

## 📋 Implementation Checklist

### ✅ Code Changes (Already Done)

- [x] Updated `ssl-certbot-cloudflare` action to support `deploy-method: host-path`
- [x] Updated Freddy CI/CD to use `host-cert-path: /etc/letsencrypt`
- [x] Updated certificate verification to check host filesystem
- [x] Updated cleanup step to remove from `/etc/letsencrypt`
- [x] Created migration documentation
- [x] Created example files (entrypoint, docker-compose)

### ⏳ Server Changes (You Need to Do)

- [ ] **Update docker-compose.yml** - Change volume mount
- [ ] **Update nginx entrypoint script** - Use `/etc/letsencrypt` instead of `/etc/letsencrypt-volume`
- [ ] **Create /etc/letsencrypt directory** - Prepare host filesystem
- [ ] **Restart services** - Apply changes
- [ ] **Run CI/CD workflow** - Deploy certificates to new location
- [ ] **Verify in browser** - Confirm Let's Encrypt certificates work

---

## 🚀 Quick Implementation (5 Steps)

### Step 1: Update docker-compose.yml (2 minutes)

```bash
cd ~/freddy
cp docker-compose.yml docker-compose.yml.backup
nano docker-compose.yml
```

**Change this:**
```yaml
services:
  nginx:
    volumes:
      - ssl-certs:/etc/letsencrypt-volume:ro
```

**To this:**
```yaml
services:
  nginx:
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
```

**And remove from volumes section:**
```yaml
volumes:
  # ssl-certs:  # No longer needed
  #   external: true
```

### Step 2: Update Nginx Entrypoint (2 minutes)

Find your nginx entrypoint script (likely `~/freddy/docker/nginx/entrypoint.sh` or similar).

**Change this:**
```bash
VOLUME_DIR="/etc/letsencrypt-volume"
```

**To this:**
```bash
LETSENCRYPT_DIR="/etc/letsencrypt"
```

**Or use the example:** See `nginx-entrypoint-example.sh` in this directory.

### Step 3: Prepare Host Directory (1 minute)

```bash
# Create directory
sudo mkdir -p /etc/letsencrypt

# Set permissions
sudo chmod 755 /etc/letsencrypt
```

### Step 4: Restart Services (1 minute)

```bash
cd ~/freddy
docker compose down
docker compose up -d
```

### Step 5: Deploy Certificates via CI/CD (5 minutes)

1. Go to: https://github.com/nuniesmith/actions/actions
2. Run workflow: **🏠 Freddy Deploy**
3. Enable: **force_ssl_regen** ✅
4. Click: **Run workflow**

Watch for:
```
📂 Deploying to host filesystem: /etc/letsencrypt
✅ Certificates deployed to host path: /etc/letsencrypt
✓ Let's Encrypt certificates found on host filesystem
```

---

## 🔍 Verification

### Check Certificates on Host
```bash
# List certificates
sudo ls -la /etc/letsencrypt/live/7gram.xyz/

# Should show:
# cert.pem -> ../../archive/7gram.xyz/cert1.pem
# chain.pem -> ../../archive/7gram.xyz/chain1.pem
# fullchain.pem -> ../../archive/7gram.xyz/fullchain1.pem
# privkey.pem -> ../../archive/7gram.xyz/privkey1.pem
```

### Check Nginx Can See Them
```bash
# Verify mount
docker exec nginx ls -la /etc/letsencrypt/live/

# Check what nginx is using
docker exec nginx cat /etc/nginx/ssl/fullchain.pem | head -5
```

### Check Browser
1. Visit: https://7gram.xyz
2. Click lock icon → Certificate
3. Should show: **Issued by: Let's Encrypt**
4. NOT: "Freddy" or self-signed

### Check Command Line
```bash
openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null 2>/dev/null | openssl x509 -noout -issuer

# Expected: issuer=C=US, O=Let's Encrypt, CN=R3
# NOT: issuer=C=CA, ST=Ontario, L=Toronto, O=Freddy
```

---

## 📊 Benefits Summary

| Feature | Docker Volume | Host Path |
|---------|--------------|-----------|
| **Setup Complexity** | High (volume permissions) | Low (standard filesystem) |
| **View Certificates** | `docker run -v ssl-certs:/certs busybox ls /certs` | `ls /etc/letsencrypt` |
| **Edit Certificates** | Requires Docker commands | Direct file access |
| **Backup** | Docker-specific tools | Standard backup tools |
| **CI/CD Deployment** | Needs root/sudo for volume | Works with standard SSH |
| **Debugging** | Indirect through containers | Direct filesystem access |
| **Permission Issues** | Common | Rare |

---

## 🐛 Troubleshooting

### Problem: Nginx can't read certificates

**Solution:**
```bash
sudo chmod 755 /etc/letsencrypt
sudo chmod 755 /etc/letsencrypt/live
sudo chmod 644 /etc/letsencrypt/live/7gram.xyz/*.pem
sudo chmod 600 /etc/letsencrypt/archive/7gram.xyz/privkey*.pem
```

### Problem: Certificates exist but nginx uses old ones

**Solution:**
```bash
docker compose restart nginx
# Wait 10 seconds
curl -vI https://7gram.xyz 2>&1 | grep issuer
```

### Problem: /etc/letsencrypt is empty

**Solution:**
```bash
# Run CI/CD with force_ssl_regen
# Or manually verify CI/CD completed successfully
# Check workflow logs for "✅ Certificates deployed to host path"
```

---

## 🔄 Migration from Docker Volume

If you have existing certificates in a Docker volume:

```bash
# 1. Extract from volume to host
sudo docker run --rm \
  -v ssl-certs:/certs:ro \
  -v /etc/letsencrypt:/dest \
  busybox:latest \
  sh -c 'cp -r /certs/* /dest/'

# 2. Fix permissions
sudo chmod -R 755 /etc/letsencrypt
sudo chmod 600 /etc/letsencrypt/archive/*/privkey*.pem

# 3. Verify
sudo ls -la /etc/letsencrypt/live/7gram.xyz/

# 4. Update docker-compose.yml (see Step 1 above)

# 5. Restart
cd ~/freddy
docker compose down
docker compose up -d
```

---

## 📚 Documentation Files

- **Migration Guide:** `HOST_SSL_MIGRATION.md` - Detailed migration steps
- **Example Entrypoint:** `nginx-entrypoint-example.sh` - Reference nginx script
- **Example Compose:** `docker-compose-nginx-example.yml` - Reference configuration
- **Quick Start:** `QUICKSTART.md` - Overall SSL setup
- **Full Documentation:** `SSL_FIX_README.md` - Complete technical docs

---

## 🎯 Expected Results

### Successful Implementation:
```
✓ Certificates at: /etc/letsencrypt/live/7gram.xyz/
✓ Nginx mounts: /etc/letsencrypt (read-only)
✓ Nginx uses: Let's Encrypt certificates
✓ Browser shows: Valid Let's Encrypt certificate
✓ No permission errors in logs
✓ CI/CD deploys without root SSH key needed
```

### Workflow Output:
```
📦 Deployment method: host-path
📂 Deploying to host filesystem: /etc/letsencrypt
📦 Extracting certificates to host filesystem...
👤 Running as: root (or actions with sudo)
✅ Certificates deployed to host path: /etc/letsencrypt
✓ Let's Encrypt certificates found on host filesystem
```

---

## 🔒 Security Notes

1. **Permissions:**
   - Directories: `755` (world-readable, only root can write)
   - Certificates: `644` (world-readable)
   - Private keys: `600` (only root can read)

2. **Container Mount:**
   - Always use `:ro` (read-only) for security
   - Prevents container from modifying host certificates

3. **Backup:**
   - Include `/etc/letsencrypt` in server backups
   - Private keys are sensitive - encrypt backups

---

## ✅ Success Criteria

When complete, verify:

- [ ] `/etc/letsencrypt/live/7gram.xyz/` contains certificate files
- [ ] `docker exec nginx ls /etc/letsencrypt/live/` works
- [ ] Browser shows Let's Encrypt certificate (not self-signed)
- [ ] `openssl s_client` shows Let's Encrypt issuer
- [ ] No errors in nginx logs about missing certificates
- [ ] CI/CD workflow completes successfully

---

## 🆘 Getting Help

If you encounter issues:

1. **Check nginx logs:** `docker logs nginx --tail 50`
2. **Check permissions:** `sudo ls -la /etc/letsencrypt/live/7gram.xyz/`
3. **Verify mount:** `docker inspect nginx | grep -A 10 Mounts`
4. **Run diagnostic:** See `HOST_SSL_MIGRATION.md` troubleshooting section
5. **Review workflow logs:** GitHub Actions → Freddy Deploy → View logs

---

**Status:** Ready to implement  
**Risk Level:** Low (easy rollback available)  
**Estimated Time:** 10-15 minutes total  
**Downtime:** ~2 minutes (container restart only)

**Next Action:** Update `docker-compose.yml` and restart services!