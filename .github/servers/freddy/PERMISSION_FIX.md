# SSL Certificate Permission Fix - Quick Guide

## 🔴 Problem

When deploying SSL certificates to `/etc/letsencrypt` on the host, you're getting permission errors:

```
tar: live: Cannot mkdir: Permission denied
tar: archive: Cannot mkdir: Permission denied
Error: Process completed with exit code 2.
```

This happens because the `actions` user doesn't have permission to write to `/etc/letsencrypt`.

---

## ✅ Solution Applied

I've updated the workflow to use `sudo` for certificate deployment. The changes are already committed and ready to use.

### What Changed:

**File: `ci-cd.yml`**
- Changed `use-sudo: false` to `use-sudo: true`

**File: `ssl-certbot-cloudflare/action.yml`**
- Fixed remote SSH command to properly detect user and use sudo when needed
- Now automatically detects if running as root or regular user
- Uses sudo only when necessary

---

## 🚀 How to Fix

### Option 1: Use Sudo (Recommended - Already Configured)

**Prerequisites:**
- The `actions` user must have sudo access on Freddy server
- Sudo should work without password for the actions user

**Verify sudo access:**
```bash
# SSH to Freddy as actions user
ssh actions@<freddy-ip>

# Test sudo without password
sudo whoami
# Should output: root
```

**If sudo requires password, configure passwordless sudo:**
```bash
# On Freddy server as root
sudo visudo -f /etc/sudoers.d/actions

# Add this line:
actions ALL=(ALL) NOPASSWD: ALL

# Or restrict to specific commands:
actions ALL=(ALL) NOPASSWD: /usr/bin/docker, /bin/mkdir, /bin/chmod, /bin/tar, /bin/rm, /bin/ls, /bin/cat
```

**Then run the workflow again** - it should work now!

---

### Option 2: Use Root SSH Key (Alternative)

If you prefer not to grant sudo access, use a root SSH key instead.

**Steps:**

1. **Generate root SSH key:**
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/freddy_root -C "root@freddy-ci"
   ```

2. **Add public key to Freddy:**
   ```bash
   ssh root@<freddy-ip>
   mkdir -p /root/.ssh
   chmod 700 /root/.ssh
   cat >> /root/.ssh/authorized_keys
   # Paste freddy_root.pub content, press Ctrl+D
   chmod 600 /root/.ssh/authorized_keys
   ```

3. **Add GitHub Secret:**
   - Name: `ROOT_SSH_KEY`
   - Value: Content of `~/.ssh/freddy_root` (private key)

4. **Update workflow:**
   Change `use-sudo: true` back to `use-sudo: false` in `ci-cd.yml`

---

### Option 3: Use Docker Volume (Fallback)

If neither option works, revert to Docker volume storage:

**In `ci-cd.yml`, change:**
```yaml
deploy-method: host-path
host-cert-path: /etc/letsencrypt
use-sudo: true
```

**To:**
```yaml
deploy-method: docker-volume
docker-volume-name: ssl-certs
docker-username: ${{ secrets.DOCKER_USERNAME }}
docker-token: ${{ secrets.DOCKER_TOKEN }}
```

---

## 🧪 Testing

After applying the fix, run the workflow:

1. Go to: https://github.com/nuniesmith/actions/actions
2. Run: **🏠 Freddy Deploy**
3. Enable: `force_ssl_regen` ✅
4. Click: **Run workflow**

**Expected output:**
```
📂 Deploying to host filesystem: /etc/letsencrypt
📦 Extracting certificates to host filesystem...
👤 Running as: actions
✅ Certificates deployed to host path: /etc/letsencrypt
✓ Let's Encrypt certificates found on host filesystem
```

**Verify on server:**
```bash
ssh actions@<freddy-ip>
sudo ls -la /etc/letsencrypt/live/7gram.xyz/

# Should show:
# cert.pem, chain.pem, fullchain.pem, privkey.pem
```

---

## 🔍 Troubleshooting

### Still getting permission errors?

**Check sudo access:**
```bash
ssh actions@<freddy-ip>
sudo -n whoami 2>&1
# Should output: root
# If it asks for password, sudo isn't configured for passwordless
```

**Check sudo configuration:**
```bash
sudo cat /etc/sudoers.d/actions
# Should contain: actions ALL=(ALL) NOPASSWD: ...
```

### Sudo requires password in CI/CD?

**The issue:** Sudo is configured but requires password for non-interactive sessions.

**Fix:**
```bash
# On Freddy server as root
sudo visudo -f /etc/sudoers.d/actions

# Change from:
actions ALL=(ALL) ALL

# To:
actions ALL=(ALL) NOPASSWD: ALL
```

### Want to restrict sudo commands?

Instead of full sudo access, restrict to only needed commands:

```bash
# In /etc/sudoers.d/actions:
actions ALL=(ALL) NOPASSWD: /usr/bin/docker, /bin/mkdir, /bin/chmod, /bin/tar, /bin/rm, /bin/ls, /bin/cat, /usr/bin/openssl
```

---

## 📋 Summary

### Current Configuration (after fix):
- ✅ Certificates deploy to: `/etc/letsencrypt` on host
- ✅ Uses: `sudo` for privilege escalation
- ✅ Runs as: `actions` user with sudo access
- ✅ No root SSH key needed

### Next Steps:
1. Verify `actions` user has sudo access (see testing section)
2. Run workflow with `force_ssl_regen: true`
3. Verify certificates in browser at https://7gram.xyz
4. Certificates should be Let's Encrypt (not self-signed)

### If sudo doesn't work:
- Follow "Option 2: Use Root SSH Key" above
- Or follow "Option 3: Use Docker Volume" for simplest approach

---

**Status:** ✅ Fix applied and ready to test  
**Risk:** Low (workflow will fail safely if sudo doesn't work)  
**Time:** 5 minutes to verify and test