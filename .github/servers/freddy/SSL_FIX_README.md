# SSL Certificate Deployment Fix

## Problem Summary

The CI/CD workflow was successfully generating Let's Encrypt SSL certificates but failing to deploy them to the Docker volume because the `actions` user lacks permission to write to Docker volumes.

### Root Cause

1. ✅ Certificates generated successfully via Certbot
2. ✅ Certificates packaged and transferred to server
3. ❌ **Extraction to Docker volume fails silently** - `actions` user cannot write to Docker volumes
4. ❌ Volume remains empty, nginx falls back to self-signed certificates

### Evidence from Diagnostics

```
Contents of volume:
(empty)

/etc/letsencrypt/live/7gram.xyz/:
total 8
drwxr-xr-x    2 root     root          4096 Feb  3 01:25 .
drwxr-xr-x    3 root     root          4096 Feb  3 01:25 ..
(no certificate files)
```

The nginx container mounts `ssl-certs:/etc/letsencrypt-volume:ro` but the volume is empty, so nginx uses self-signed fallback certificates.

## Solution

Updated the SSL deployment process to support **root SSH access** for Docker volume operations while maintaining the `actions` user for regular deployment tasks.

### Changes Made

#### 1. Updated `ssl-certbot-cloudflare` Action

**File:** `actions/.github/actions/ssl-certbot-cloudflare/action.yml`

Added new inputs:
- `root-ssh-key`: Root SSH private key for Docker volume operations
- `use-sudo`: Alternative option if `actions` user has sudo access

The action now:
1. Uses regular `ssh-user` and `ssh-key` to transfer certificates to `/tmp/`
2. Switches to `root-ssh-key` or uses `sudo` for Docker volume extraction
3. Properly handles permissions for certificate deployment

#### 2. Updated Freddy CI/CD Workflow

**File:** `actions/.github/servers/freddy/ci-cd.yml`

Updated three steps to use root access when available:

1. **🧹 Clean corrupted SSL certificates** - Uses root for Docker volume removal
2. **🔐 Generate SSL Certificates** - Passes `root-ssh-key` to action
3. **✅ Verify SSL certificates in volume** - Uses root for Docker volume inspection

## Setup Instructions

### Option 1: Use Root SSH Key (Recommended)

This approach uses root access only for Docker operations, keeping regular deployments with the `actions` user.

#### Step 1: Generate Root SSH Key Pair

On your local machine:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/freddy_root -C "root@freddy-ci"
```

#### Step 2: Add Public Key to Freddy Server

On the Freddy server as root:

```bash
# Create .ssh directory for root if it doesn't exist
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Add the public key
cat >> /root/.ssh/authorized_keys << 'EOF'
<paste your freddy_root.pub content here>
EOF

chmod 600 /root/.ssh/authorized_keys
```

#### Step 3: Test Root SSH Access

From your local machine or GitHub Actions runner (via Tailscale):

```bash
ssh -i ~/.ssh/freddy_root root@<freddy-tailscale-ip>
```

#### Step 4: Add GitHub Secret

1. Go to your repository settings
2. Navigate to **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `ROOT_SSH_KEY`
5. Value: Content of `~/.ssh/freddy_root` (the private key)

#### Step 5: Update Workflow (Already Done)

The workflow has been updated to use `${{ secrets.ROOT_SSH_KEY }}` when available.

### Option 2: Grant Sudo Access to Actions User

If you prefer not to use a separate root key, you can grant sudo access to the `actions` user.

#### Step 1: Add Actions User to Docker Group

On Freddy server:

```bash
sudo usermod -aG docker actions
```

#### Step 2: Grant Sudo Without Password (Optional)

Create sudoers file:

```bash
sudo visudo -f /etc/sudoers.d/actions
```

Add this line:

```
actions ALL=(ALL) NOPASSWD: /usr/bin/docker
```

#### Step 3: Update Workflow

Change `use-sudo: false` to `use-sudo: true` in the CI/CD workflow:

```yaml
- name: 🔐 Generate SSL Certificates
  uses: nuniesmith/actions/.github/actions/ssl-certbot-cloudflare@main
  with:
    # ... other parameters ...
    use-sudo: true  # Change from false to true
    # Don't set root-ssh-key
```

## Verification

After deploying with the fix:

### 1. Check Volume Contents

```bash
sudo docker run --rm -v ssl-certs:/certs:ro busybox:latest ls -la /certs/live/7gram.xyz/
```

Expected output:
```
total 8
drwxr-xr-x    2 root     root          4096 Feb  3 01:25 .
drwxr-xr-x    3 root     root          4096 Feb  3 01:25 ..
lrwxrwxrwx    1 root     root            35 Feb  3 01:25 cert.pem -> ../../archive/7gram.xyz/cert1.pem
lrwxrwxrwx    1 root     root            36 Feb  3 01:25 chain.pem -> ../../archive/7gram.xyz/chain1.pem
lrwxrwxrwx    1 root     root            40 Feb  3 01:25 fullchain.pem -> ../../archive/7gram.xyz/fullchain1.pem
lrwxrwxrwx    1 root     root            38 Feb  3 01:25 privkey.pem -> ../../archive/7gram.xyz/privkey1.pem
```

### 2. Check Certificate Being Served

```bash
openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null 2>/dev/null | openssl x509 -noout -issuer -dates
```

Expected output (Let's Encrypt certificate):
```
issuer=C=US, O=Let's Encrypt, CN=R3
notBefore=Feb  3 01:25:32 2025 GMT
notAfter=May   4 01:25:31 2025 GMT
```

NOT this (self-signed):
```
issuer=C=CA, ST=Ontario, L=Toronto, O=Freddy, CN=7gram.xyz
```

### 3. Run Diagnostic Script

On Freddy server:

```bash
~/ssl.sh
```

Look for:
- ✅ Volume exists and contains Let's Encrypt certificates
- ✅ Certificate being served is NOT self-signed
- ✅ Nginx is using Let's Encrypt certificates

## Troubleshooting

### Issue: Still seeing self-signed certificates

**Solution:** Restart nginx after successful certificate deployment

```bash
cd ~/freddy
sudo docker compose restart nginx
```

### Issue: Permission denied when accessing Docker volume

**Solution:** Ensure you're using root or sudo:

```bash
# Wrong (as actions user)
docker run --rm -v ssl-certs:/certs busybox ls /certs

# Right (with sudo)
sudo docker run --rm -v ssl-certs:/certs busybox ls /certs

# Right (as root)
ssh root@freddy "docker run --rm -v ssl-certs:/certs busybox ls /certs"
```

### Issue: Certificates in volume but nginx still using self-signed

**Check nginx volume mount path:**

The nginx container mounts the volume at `/etc/letsencrypt-volume` but expects certificates at `/etc/nginx/ssl/`. The entrypoint script should copy from volume to `/etc/nginx/ssl/`.

Verify nginx entrypoint is running:

```bash
sudo docker logs nginx 2>&1 | grep -A 20 "SSL"
```

Expected output:
```
[INFO] ✓ Certificate files found in volume
[INFO] Copying certificates from volume to /etc/nginx/ssl/
[INFO] ✓ Let's Encrypt certificates configured
```

### Issue: GitHub Actions can't connect via Tailscale

**Solution:** Ensure secrets are set:
- `TAILSCALE_OAUTH_CLIENT_ID`
- `TAILSCALE_OAUTH_SECRET`
- `FREDDY_TAILSCALE_IP`

## Manual Certificate Deployment (Fallback)

If CI/CD deployment fails, you can manually deploy certificates:

```bash
# On your local machine (with certificates in /tmp/letsencrypt)
cd /tmp/letsencrypt
tar -czf ssl-certs.tar.gz live/ archive/ renewal/

# Transfer to server
scp -P 22 ssl-certs.tar.gz root@<freddy-ip>:/tmp/

# On Freddy server as root
ssh root@<freddy-ip>

# Extract to Docker volume
docker volume create ssl-certs 2>/dev/null || true
docker run --rm \
  -v /tmp/ssl-certs.tar.gz:/tmp/ssl-certs.tar.gz:ro \
  -v ssl-certs:/etc/letsencrypt \
  busybox:latest \
  sh -c 'cd /etc/letsencrypt && tar -xzf /tmp/ssl-certs.tar.gz && chmod -R 755 /etc/letsencrypt'

# Restart nginx
cd ~/freddy
docker compose restart nginx
```

## Security Notes

1. **Root SSH Key Security:**
   - Store root SSH key securely in GitHub Secrets (encrypted at rest)
   - Key is only used for Docker volume operations during deployment
   - Consider IP restrictions in `/root/.ssh/authorized_keys` if possible
   - Rotate keys periodically

2. **Sudo Access Alternative:**
   - More restrictive than full root access
   - Can be limited to specific Docker commands
   - Easier to audit via sudo logs

3. **Best Practice:**
   - Use root SSH key only for SSL deployment
   - Keep regular `actions` user for all other operations
   - Monitor deployment logs for unauthorized access attempts

## Next Steps

1. ✅ Add `ROOT_SSH_KEY` to GitHub Secrets
2. ✅ Test deployment with `workflow_dispatch` and `force_ssl_regen: true`
3. ✅ Verify Let's Encrypt certificates are being served
4. ✅ Schedule regular certificate renewal (currently runs weekly via cron)
5. ✅ Set up monitoring/alerts for certificate expiration

## Related Files

- Action: `actions/.github/actions/ssl-certbot-cloudflare/action.yml`
- Workflow: `actions/.github/servers/freddy/ci-cd.yml`
- Diagnostic: `~/ssl.sh` (on Freddy server)

## Support

If issues persist after implementing this fix, check:
1. GitHub Actions workflow run logs
2. Nginx container logs: `sudo docker logs nginx`
3. Certificate diagnostic output: `~/ssl.sh`
4. Docker volume contents: `sudo docker run --rm -v ssl-certs:/certs busybox ls -laR /certs`
