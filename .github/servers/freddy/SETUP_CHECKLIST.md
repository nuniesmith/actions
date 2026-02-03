# SSL Certificate Fix - Quick Setup Checklist

## 🎯 Objective
Enable CI/CD to deploy Let's Encrypt certificates to Freddy's Docker volume by granting root access for Docker operations.

## ✅ Setup Steps

### 1. Generate Root SSH Key Pair
```bash
# On your local machine
ssh-keygen -t ed25519 -f ~/.ssh/freddy_root -C "root@freddy-ci"
```

### 2. Add Public Key to Freddy Server
```bash
# SSH to Freddy as root (or use existing access to become root)
ssh root@<freddy-tailscale-ip>

# Or if using actions user
ssh actions@<freddy-tailscale-ip>
su -

# Create .ssh directory if needed
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Add the public key (paste content of freddy_root.pub)
nano /root/.ssh/authorized_keys
# Paste your public key, save and exit

chmod 600 /root/.ssh/authorized_keys
```

### 3. Test Root SSH Access
```bash
# From local machine via Tailscale
ssh -i ~/.ssh/freddy_root root@<freddy-tailscale-ip>

# Should connect successfully
whoami  # Should output: root
exit
```

### 4. Add GitHub Secret
1. Go to: https://github.com/nuniesmith/actions/settings/secrets/actions
2. Click **New repository secret**
3. Name: `ROOT_SSH_KEY`
4. Value: Paste content of `~/.ssh/freddy_root` (private key, starts with `-----BEGIN OPENSSH PRIVATE KEY-----`)
5. Click **Add secret**

### 5. Verify Existing Secrets
Ensure these secrets exist:
- ✅ `CLOUDFLARE_API_TOKEN`
- ✅ `CLOUDFLARE_ZONE_ID`
- ✅ `FREDDY_TAILSCALE_IP`
- ✅ `SSH_KEY` (for actions user)
- ✅ `SSH_PORT` (usually 22)
- ✅ `SSH_USER` (usually actions)
- ✅ `SSL_EMAIL`
- ✅ `TAILSCALE_OAUTH_CLIENT_ID`
- ✅ `TAILSCALE_OAUTH_SECRET`
- ✅ `DOCKER_USERNAME` (optional, for rate limits)
- ✅ `DOCKER_TOKEN` (optional, for rate limits)
- ✅ `ROOT_SSH_KEY` ← **NEW!**

### 6. Test Deployment
1. Go to: https://github.com/nuniesmith/actions/actions/workflows/ci-cd.yml
2. Click **Run workflow**
3. Select branch: `main`
4. Check: `force_ssl_regen` ✅
5. Uncheck: `use_staging_certs` ☐ (unless testing)
6. Click **Run workflow**

### 7. Monitor Deployment
Watch the workflow run and check these steps:
- ✅ 🧹 Clean corrupted SSL certificates
- ✅ 🔐 Generate SSL Certificates
- ✅ ✅ Verify SSL certificates in volume
- ✅ 🚀 Deploy to Freddy

Look for in logs:
```
🔑 Using root SSH key for Docker volume operations
👤 Running as: root
✅ Certificates deployed to Docker volume: ssl-certs
✅ Let's Encrypt certificates found in volume
```

### 8. Verify Certificate Deployment
```bash
# SSH to Freddy
ssh actions@<freddy-tailscale-ip>

# Run diagnostic script
~/ssl.sh

# Look for:
# ✅ Volume exists and contains Let's Encrypt certificates
# ✅ Certificate being served is NOT self-signed
# issuer=C=US, O=Let's Encrypt, CN=R3
```

### 9. Test in Browser
Visit: https://7gram.xyz

Check certificate:
1. Click lock icon in address bar
2. Click "Connection is secure"
3. Click certificate details
4. Verify:
   - Issued by: Let's Encrypt
   - Valid from: (recent date)
   - Valid to: (3 months from issue date)
   - NOT self-signed

## 🐛 Troubleshooting

### Problem: "Permission denied" during Docker operations
**Solution:** Ensure ROOT_SSH_KEY secret is set correctly
```bash
# Test manually
ssh -i ~/.ssh/freddy_root root@<freddy-tailscale-ip> "docker volume ls"
```

### Problem: Still seeing self-signed certificates after deployment
**Solution:** Restart nginx container
```bash
ssh actions@<freddy-tailscale-ip>
cd ~/freddy
sudo docker compose restart nginx

# Wait 10 seconds, then check
curl -vI https://7gram.xyz 2>&1 | grep "issuer"
```

### Problem: Volume contains certificates but nginx doesn't use them
**Solution:** Check nginx entrypoint logs
```bash
ssh actions@<freddy-tailscale-ip>
sudo docker logs nginx 2>&1 | grep -A 30 "SSL"

# Should show:
# [INFO] ✓ Certificate files found in volume
# [INFO] Copying certificates from volume to /etc/nginx/ssl/
```

### Problem: "No space left on device"
**Solution:** Clean up Docker
```bash
ssh root@<freddy-tailscale-ip>
docker system prune -a --volumes -f
```

## 📊 Quick Verification Commands

```bash
# Check volume contents (as root or with sudo)
sudo docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/live/7gram.xyz/

# Check certificate being served
openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null 2>/dev/null | openssl x509 -noout -issuer -dates

# Check nginx logs
sudo docker logs nginx --tail 50

# Check all container health
sudo docker ps --format "table {{.Names}}\t{{.Status}}"
```

## 🔒 Security Reminders

- ✅ ROOT_SSH_KEY is encrypted in GitHub Secrets
- ✅ Only used for Docker volume operations during deployment
- ✅ Regular deployments still use limited `actions` user
- ✅ Consider IP restrictions in authorized_keys if needed
- ✅ Rotate SSH keys periodically (every 90 days recommended)

## 📅 Maintenance

- **Weekly:** Automated certificate renewal (via cron schedule in workflow)
- **Monthly:** Review deployment logs for issues
- **Quarterly:** Rotate SSH keys
- **Yearly:** Review and update security practices

## ✅ Success Criteria

When complete, you should have:
- [x] ROOT_SSH_KEY secret added to GitHub
- [x] Root SSH access tested and working
- [x] CI/CD workflow successfully deploys certificates
- [x] Docker volume contains Let's Encrypt certificates
- [x] Nginx serves Let's Encrypt certificates (not self-signed)
- [x] Browser shows valid Let's Encrypt certificate for 7gram.xyz

## 📖 Additional Resources

- Full documentation: `SSL_FIX_README.md`
- SSL Certbot action: `actions/.github/actions/ssl-certbot-cloudflare/`
- CI/CD workflow: `actions/.github/servers/freddy/ci-cd.yml`
- Diagnostic script: `~/ssl.sh` (on Freddy server)