# SSL Certificate Fix - Quick Start Guide

## 🚀 What You Need to Do RIGHT NOW

Your CI/CD is working but nginx is serving **self-signed certificates** instead of **Let's Encrypt certificates** because the `actions` user can't write to Docker volumes.

**Fix:** Add a root SSH key so the workflow can deploy certificates properly.

---

## ⚡ 3-Step Quick Fix

### Step 1: Generate Root SSH Key (2 minutes)

On your local machine:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/freddy_root -C "root@freddy-ci"
# Press Enter for all prompts (no passphrase needed for automation)
```

### Step 2: Add Public Key to Freddy (2 minutes)

```bash
# SSH to Freddy as root (or use 'su -' if logged in as actions)
ssh root@<freddy-tailscale-ip>

# If that doesn't work, try:
ssh actions@<freddy-tailscale-ip>
su -

# Then run:
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat >> /root/.ssh/authorized_keys
# NOW: Paste the content of ~/.ssh/freddy_root.pub (from your local machine)
# Press Ctrl+D when done
chmod 600 /root/.ssh/authorized_keys
exit
```

**Test it works:**
```bash
ssh -i ~/.ssh/freddy_root root@<freddy-tailscale-ip>
whoami  # Should say "root"
exit
```

### Step 3: Add GitHub Secret (1 minute)

1. Go to: https://github.com/nuniesmith/actions/settings/secrets/actions
2. Click **"New repository secret"**
3. Name: `ROOT_SSH_KEY`
4. Value: Copy the ENTIRE content of `~/.ssh/freddy_root` (private key file)
   ```bash
   # On your local machine:
   cat ~/.ssh/freddy_root
   # Copy everything from "-----BEGIN OPENSSH PRIVATE KEY-----" to "-----END OPENSSH PRIVATE KEY-----"
   ```
5. Click **"Add secret"**

---

## ✅ Test the Fix (5 minutes)

### Run the Workflow

1. Go to: https://github.com/nuniesmith/actions/actions
2. Find **"🏠 Freddy Deploy"** workflow
3. Click **"Run workflow"**
4. Settings:
   - Branch: `main`
   - ✅ Check **"Force SSL regeneration"**
   - ⬜ Leave **"Use staging certs"** unchecked (unless testing)
5. Click **"Run workflow"** button

### Watch for Success

In the workflow logs, look for:

```
🔑 Using root SSH key for Docker volume operations
👤 Running as: root
✅ Certificates deployed to Docker volume: ssl-certs
✅ Let's Encrypt certificates found in volume
✓ Certificate and private key match
issuer=C=US, O=Let's Encrypt, CN=R3
```

### Verify in Browser

1. Visit: https://7gram.xyz
2. Click the **lock icon** in address bar
3. Check certificate:
   - ✅ Issued by: **Let's Encrypt**
   - ❌ NOT: "Freddy" or "self-signed"

---

## 🔍 Quick Verification Commands

On Freddy server:

```bash
# Check if certificates are in Docker volume
sudo docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/live/7gram.xyz/

# Should show: cert.pem, chain.pem, fullchain.pem, privkey.pem

# Check what nginx is serving
openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null 2>/dev/null | openssl x509 -noout -issuer

# Should show: issuer=C=US, O=Let's Encrypt, CN=R3
# NOT: issuer=C=CA, ST=Ontario, L=Toronto, O=Freddy
```

---

## 🆘 If Something Goes Wrong

### Problem: "Permission denied" when connecting via root SSH

**Fix:**
```bash
# Make sure you're using the correct IP
ssh -i ~/.ssh/freddy_root root@<freddy-tailscale-ip>

# If that fails, check authorized_keys on server
ssh actions@<freddy-tailscale-ip>
su -
cat /root/.ssh/authorized_keys
# Should contain your public key
```

### Problem: Still seeing self-signed certificate after deployment

**Fix:**
```bash
# SSH to Freddy
ssh actions@<freddy-tailscale-ip>

# Restart nginx
cd ~/freddy
sudo docker compose restart nginx

# Wait 10 seconds, then check
curl -vI https://7gram.xyz 2>&1 | grep "issuer"
```

### Problem: Workflow fails at certificate deployment

**Check:**
1. Is `ROOT_SSH_KEY` secret set correctly?
2. Can you manually SSH as root? `ssh -i ~/.ssh/freddy_root root@<freddy-ip>`
3. Check workflow logs for specific error message

---

## 📚 Full Documentation

- **Detailed setup:** See `SSL_FIX_README.md`
- **Step-by-step checklist:** See `SETUP_CHECKLIST.md`
- **Diagnostic script:** Run `~/check-ssl-setup.sh` on Freddy server
- **All changes:** See `CHANGES_SUMMARY.md`

---

## ✨ What Changed

**Before:**
- CI/CD generates certificates ✅
- `actions` user can't write to Docker volume ❌
- Volume stays empty ❌
- Nginx uses self-signed fallback ❌

**After:**
- CI/CD generates certificates ✅
- Uses root SSH key for Docker operations ✅
- Certificates deployed to volume ✅
- Nginx uses Let's Encrypt certificates ✅

---

## 🎯 Expected Timeline

- **Setup:** 5 minutes
- **First deployment:** 5-10 minutes
- **Verification:** 2 minutes
- **Total:** ~15 minutes

---

## 🔒 Security Notes

- Root SSH key is **only used for Docker volume operations**
- Regular deployments still use limited `actions` user
- Key is encrypted in GitHub Secrets
- Rotate keys every 90 days (calendar reminder recommended)

---

## ✅ Success Checklist

- [ ] Root SSH key generated
- [ ] Public key added to `/root/.ssh/authorized_keys` on Freddy
- [ ] Can SSH as root: `ssh -i ~/.ssh/freddy_root root@<freddy-ip>`
- [ ] `ROOT_SSH_KEY` secret added to GitHub
- [ ] Workflow run completed successfully
- [ ] Docker volume contains certificates
- [ ] Browser shows Let's Encrypt certificate (not self-signed)

**When all boxes are checked, you're done! 🎉**

---

**Questions?** Check the troubleshooting section above or review `SSL_FIX_README.md` for details.