# SSL Certificate Deployment Fix - Changes Summary

**Date:** 2025-02-03  
**Issue:** CI/CD workflow generates Let's Encrypt certificates successfully but nginx continues serving self-signed certificates  
**Root Cause:** The `actions` user lacks permission to write to Docker volumes

## Problem Details

### What Was Happening

1. ✅ Certbot successfully generates Let's Encrypt certificates
2. ✅ Certificates are packaged and transferred to Freddy server
3. ❌ **Extraction to Docker volume fails silently** - `actions` user cannot write to Docker volumes without root/sudo
4. ❌ Docker volume `ssl-certs` remains empty
5. ❌ Nginx entrypoint finds no certificates in volume, falls back to self-signed certificates

### Evidence

From diagnostic output:
```
Contents of volume: (empty)

/etc/letsencrypt/live/7gram.xyz/:
total 8
drwxr-xr-x    2 root     root          4096 Feb  3 01:25 .
drwxr-xr-x    3 root     root          4096 Feb  3 01:25 ..
(no certificate files)

Certificate being served:
issuer=C=CA, ST=Ontario, L=Toronto, O=Freddy, CN=7gram.xyz (SELF-SIGNED)
```

## Solution Implemented

Added support for root SSH access specifically for Docker volume operations while maintaining the `actions` user for regular deployment tasks.

## Files Changed

### 1. `actions/.github/actions/ssl-certbot-cloudflare/action.yml`

**Changes:**
- Added `root-ssh-key` input parameter for root SSH private key
- Added `use-sudo` input parameter as alternative if `actions` user has sudo access
- Modified certificate deployment step to:
  - Transfer files using regular `ssh-user` credentials
  - Switch to `root-ssh-key` or use `sudo` for Docker volume operations
  - Properly handle permissions during extraction

**Key Logic:**
```yaml
# Determine which SSH key and user to use for Docker operations
if [ -n "$ROOT_SSH_KEY" ]; then
  DEPLOY_USER="root"
  DEPLOY_SSH_KEY="$ROOT_SSH_KEY"
elif [ "$USE_SUDO" = "true" ]; then
  SUDO_CMD="sudo"
fi

# Extract with proper permissions
$SUDO_CMD docker run --rm \
  -v /tmp/ssl-certs.tar.gz:/tmp/ssl-certs.tar.gz:ro \
  -v $DOCKER_VOLUME:/etc/letsencrypt \
  busybox:latest \
  sh -c 'cd /etc/letsencrypt && tar -xzf /tmp/ssl-certs.tar.gz ...'
```

### 2. `actions/.github/servers/freddy/ci-cd.yml`

**Changes:**

#### a) SSL Certificate Generation Step
- Added `root-ssh-key: ${{ secrets.ROOT_SSH_KEY }}`
- Added `use-sudo: false`

```yaml
- name: 🔐 Generate SSL Certificates
  uses: nuniesmith/actions/.github/actions/ssl-certbot-cloudflare@main
  with:
    # ... existing parameters ...
    root-ssh-key: ${{ secrets.ROOT_SSH_KEY }}
    use-sudo: false
```

#### b) SSL Certificate Verification Step
- Modified to use `ROOT_SSH_KEY` when available
- Adds `sudo` prefix to all Docker commands when not running as root
- Properly detects user context (root vs actions)

```yaml
# Determine which SSH key and user to use
if [ -n "$ROOT_SSH_KEY" ]; then
  VERIFY_USER="root"
  VERIFY_SSH_KEY="$ROOT_SSH_KEY"
  SUDO_CMD=""
else
  VERIFY_USER="actions"
  VERIFY_SSH_KEY="$SSH_KEY"
  SUDO_CMD="sudo"
fi
```

#### c) SSL Cleanup Step (force_ssl_regen)
- Modified to use `ROOT_SSH_KEY` when available
- Adds `sudo` prefix to all Docker commands
- Handles both root and actions user contexts

## New Files Created

### 1. `actions/.github/servers/freddy/SSL_FIX_README.md`
Comprehensive documentation covering:
- Problem explanation with diagnostics evidence
- Solution architecture
- Two setup options (root SSH key vs sudo)
- Step-by-step setup instructions
- Verification procedures
- Troubleshooting guide
- Security considerations
- Manual deployment fallback

### 2. `actions/.github/servers/freddy/SETUP_CHECKLIST.md`
Quick reference guide with:
- Step-by-step setup checklist
- GitHub secret configuration
- Testing procedures
- Verification commands
- Troubleshooting quick fixes
- Success criteria

### 3. `actions/.github/servers/freddy/check-ssl-setup.sh`
Automated diagnostic script that checks:
- Permissions (root/sudo access)
- Docker volume existence and contents
- Certificate files in volume
- Certificate issuer (Let's Encrypt vs self-signed)
- Certificate expiry dates
- Nginx container status and configuration
- What certificate is being served to clients
- Required commands availability
- Provides pass/fail/warning summary

### 4. `actions/.github/servers/freddy/CHANGES_SUMMARY.md`
This file - summary of all changes made

## Required Setup

### Option 1: Root SSH Key (Recommended)

1. **Generate SSH key pair:**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/freddy_root -C "root@freddy-ci"
   ```

2. **Add public key to Freddy server:**
   ```bash
   ssh root@freddy
   mkdir -p /root/.ssh
   chmod 700 /root/.ssh
   cat >> /root/.ssh/authorized_keys
   # Paste freddy_root.pub content
   chmod 600 /root/.ssh/authorized_keys
   ```

3. **Add GitHub Secret:**
   - Name: `ROOT_SSH_KEY`
   - Value: Content of `~/.ssh/freddy_root` (private key)

### Option 2: Grant Sudo Access to Actions User

1. **Add to docker group:**
   ```bash
   sudo usermod -aG docker actions
   ```

2. **Grant passwordless sudo for docker:**
   ```bash
   sudo visudo -f /etc/sudoers.d/actions
   # Add: actions ALL=(ALL) NOPASSWD: /usr/bin/docker
   ```

3. **Update workflow:**
   Change `use-sudo: false` to `use-sudo: true`

## Testing

### 1. Run Workflow
```
GitHub Actions → ci-cd.yml → Run workflow
✓ force_ssl_regen: true
✓ Branch: main
```

### 2. Monitor Logs
Look for:
```
🔑 Using root SSH key for Docker volume operations
👤 Running as: root
✅ Certificates deployed to Docker volume: ssl-certs
✅ Let's Encrypt certificates found in volume
```

### 3. Verify on Server
```bash
ssh actions@freddy
~/check-ssl-setup.sh
```

### 4. Check Browser
Visit: https://7gram.xyz
- Lock icon → Certificate details
- Should show: "Let's Encrypt" (not self-signed)

## Verification Commands

```bash
# Check volume contents
sudo docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/live/7gram.xyz/

# Check certificate being served
openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null 2>/dev/null | openssl x509 -noout -issuer -dates

# Check nginx logs
sudo docker logs nginx --tail 50 | grep -i ssl

# Run comprehensive diagnostics
~/check-ssl-setup.sh
```

## Expected Results

### Before Fix
```
issuer=C=CA, ST=Ontario, L=Toronto, O=Freddy, CN=7gram.xyz
subject=C=CA, ST=Ontario, L=Toronto, O=Freddy, CN=7gram.xyz
✗ Self-signed certificate detected!
```

### After Fix
```
issuer=C=US, O=Let's Encrypt, CN=R3
subject=CN=7gram.xyz
notBefore=Feb  3 XX:XX:XX 2025 GMT
notAfter=May   4 XX:XX:XX 2025 GMT
✓ Let's Encrypt certificate detected!
```

## Security Considerations

1. **Root SSH Key:**
   - Stored encrypted in GitHub Secrets
   - Only used during certificate deployment
   - Regular deployments still use limited `actions` user
   - Rotate periodically (every 90 days recommended)

2. **Separation of Concerns:**
   - Certificate deployment: uses root
   - Application deployment: uses actions user
   - Minimal privilege escalation

3. **Audit Trail:**
   - All operations logged in GitHub Actions
   - Docker operations logged on server
   - SSH access logged in system logs

## Rollback Plan

If issues occur:

1. **Immediate:** Remove `ROOT_SSH_KEY` secret → workflow falls back to actions user behavior
2. **Manual deployment:** Use manual certificate deployment procedure in `SSL_FIX_README.md`
3. **Self-signed fallback:** Nginx automatically falls back to self-signed certificates if volume is empty

## Maintenance

- **Weekly:** Automated certificate renewal (existing cron schedule)
- **Monthly:** Review deployment logs
- **Quarterly:** Rotate SSH keys
- **As needed:** Update Let's Encrypt renewal settings

## References

- Let's Encrypt: https://letsencrypt.org/
- Certbot Documentation: https://certbot.eff.org/
- Docker Volume Documentation: https://docs.docker.com/storage/volumes/
- GitHub Actions Secrets: https://docs.github.com/en/actions/security-guides/encrypted-secrets

## Success Metrics

- ✅ CI/CD workflow completes without errors
- ✅ Docker volume contains Let's Encrypt certificates
- ✅ Nginx serves Let's Encrypt certificates (not self-signed)
- ✅ Browser shows valid certificate for 7gram.xyz
- ✅ Automated renewal works (check after 60 days)
- ✅ No manual intervention required for renewals

## Next Steps

1. ✅ Review this document
2. ⏳ Add `ROOT_SSH_KEY` to GitHub Secrets
3. ⏳ Test deployment with `force_ssl_regen: true`
4. ⏳ Verify certificates in browser
5. ⏳ Monitor first automated renewal
6. ⏳ Document any additional findings

---

**Status:** Ready for deployment  
**Risk Level:** Low (fallback to self-signed certificates if issues occur)  
**Estimated Deployment Time:** 5-10 minutes  
**Downtime Required:** None (nginx continues serving during certificate update)