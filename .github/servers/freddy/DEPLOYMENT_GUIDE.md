# Freddy Server Deployment Guide

Complete guide for deploying Freddy server with SSL certificate management.

---

## 🚀 Quick Start - Fresh Deployment with SSL Cleanup

### Option 1: GitHub Actions (Recommended)

1. **Go to GitHub Actions**
   - Navigate to: [Actions Tab](https://github.com/nuniesmith/actions/actions)
   - Select workflow: **🏠 Freddy Deploy**
   - Click **"Run workflow"**

2. **Configure Deployment**
   - **update_dns**: ✅ `true` (Update Cloudflare DNS records)
   - **force_ssl_regen**: ✅ `true` (Clean and regenerate SSL certificates)
   - **skip_deploy**: ❌ `false` (Deploy the services)
   - Click **"Run workflow"**

3. **Monitor Progress**
   - Watch the workflow execution
   - All jobs should complete successfully:
     - ✅ DNS Update
     - ✅ SSL Generate (with cleanup)
     - ✅ Deploy
     - ✅ Health Checks

### Option 2: Manual SSH Deployment

If the workflow fails or you need manual control:

```bash
# SSH into Freddy
ssh actions@freddy

# Navigate to project directory
cd ~/freddy

# COMPLETE CLEANUP
echo "🧹 Starting complete cleanup..."

# Stop all services
./run.sh stop || docker compose down || true

# Remove containers
docker stop nginx photoprism nextcloud homeassistant audiobookshelf 2>/dev/null || true
docker rm -f nginx photoprism nextcloud homeassistant audiobookshelf 2>/dev/null || true

# Remove SSL volumes (THIS FIXES THE CORRUPTED CERT ISSUE)
docker volume rm ssl-certs 2>/dev/null || true
docker volume rm freddy_ssl-certs 2>/dev/null || true

# Clean host certificate directories
sudo rm -rf /opt/ssl/7gram.xyz
sudo rm -rf /etc/letsencrypt
sudo rm -rf /opt/letsencrypt

# Clean project certificate directories
rm -rf ~/freddy/ssl/
rm -rf ~/freddy/certs/
rm -rf ~/freddy/nginx/ssl/
rm -rf ~/freddy/nginx/certs/

# Prune Docker resources
docker volume prune -f
docker container prune -f
docker network prune -f

echo "✅ Cleanup complete!"

# Pull latest code
git fetch origin
git checkout main
git pull origin main

# Start services (will generate fresh SSL certificates)
./run.sh prod start

# Monitor logs
docker logs -f nginx
```

---

## 🔐 SSL Certificate Management

### Understanding the Issue

The nginx container was failing with:
```
[ERROR] Certificate and private key do not match!
[DEBUG] Private key modulus: MD5(stdin)= d41d8cd98f00b204e9800998ecf8427e
```

The hash `d41d8cd98f00b204e9800998ecf8427e` is the MD5 of an **empty string**, meaning `privkey.pem` was corrupted.

### The Solution

The workflow now includes **comprehensive cleanup** that:

1. **Pre-SSL Generation Cleanup** (if `force_ssl_regen=true`)
   - Stops all services
   - Removes nginx container
   - Deletes ssl-certs Docker volume
   - Cleans host certificate directories
   - Prunes dangling volumes

2. **Clean Slate Verification**
   - Verifies no lingering SSL artifacts
   - Confirms nginx container is removed
   - Checks ssl-certs volume doesn't exist

3. **Fresh Certificate Generation**
   - Uses Let's Encrypt + Cloudflare DNS validation
   - Generates certificates for all domains
   - Stores in new ssl-certs Docker volume

4. **Post-Generation Verification**
   - Confirms certificate files exist
   - Verifies cert/key pair match
   - Checks certificate validity and expiry

5. **Pre-Deployment Cleanup**
   - Additional cleanup before deploying containers
   - Ensures no stale volumes or containers

### Certificate Details

- **Primary Domain**: `7gram.xyz`
- **Wildcard**: `*.7gram.xyz`
- **Subdomains**:
  - `nc.7gram.xyz` (Nextcloud)
  - `photo.7gram.xyz` (Photoprism)
  - `home.7gram.xyz` (Home Assistant)
  - `audiobook.7gram.xyz` (Audiobookshelf)
  - `sullivan.7gram.xyz` (Sullivan proxy)
  - `*.sullivan.7gram.xyz` (Sullivan wildcard)

- **Issuer**: Let's Encrypt (Production CA: E7)
- **Validity**: 90 days
- **Auto-renewal**: Weekly check (Sundays 3am UTC)
- **Storage**: Docker volume `ssl-certs`

---

## 📋 Workflow Jobs

### 1. DNS Update (`dns-update`)

Updates Cloudflare DNS records to point to Freddy's Tailscale IP.

**Runs when:**
- Manual workflow dispatch with `update_dns=true`
- Scheduled weekly
- Push to main branch

**What it does:**
- Updates A records for all Freddy domains
- Updates Sullivan proxy records
- Verifies DNS propagation

### 2. SSL Generation (`ssl-generate`)

Generates/renews SSL certificates using Let's Encrypt.

**Runs when:**
- DNS was updated
- Manual workflow dispatch with `force_ssl_regen=true`
- Scheduled weekly
- Any workflow dispatch or push

**What it does:**
- Cleans old certificates (if forced)
- Verifies clean slate
- Generates fresh Let's Encrypt certificates
- Deploys to ssl-certs Docker volume
- Verifies certificate/key pair match

### 3. Deployment (`deploy`)

Deploys services to Freddy server.

**Runs when:**
- SSL certificates are ready
- Manual workflow dispatch (unless `skip_deploy=true`)

**What it does:**
- Connects via Tailscale VPN
- Performs comprehensive SSL cleanup
- Pulls latest code
- Verifies SSL certificates
- Starts all services
- Runs health checks

### 4. Summary (`summary`)

Generates deployment summary and reports status.

**Always runs** after deployment completes.

---

## 🏥 Health Checks

After deployment, the workflow performs health checks on:

- ✅ **nginx** - Reverse proxy and SSL termination
- ✅ **photoprism** - Photo management
- ✅ **nextcloud** - Cloud storage
- ✅ **homeassistant** - Home automation
- ✅ **audiobookshelf** - Audiobook server

Health checks verify:
- Containers are running
- Services respond correctly
- No crash loops

---

## 🔍 Verification Commands

### Check SSL Certificates

```bash
# SSH into Freddy
ssh actions@freddy

# Check certificate files in volume
docker run --rm -v ssl-certs:/certs:ro busybox:latest ls -lah /certs/live/7gram.xyz/

# Verify cert/key match
docker run --rm -v ssl-certs:/certs:ro alpine/openssl sh -c '
  CERT_MOD=$(openssl x509 -noout -modulus -in /certs/live/7gram.xyz/fullchain.pem | openssl md5)
  KEY_MOD=$(openssl rsa -noout -modulus -in /certs/live/7gram.xyz/privkey.pem | openssl md5)
  echo "Certificate: $CERT_MOD"
  echo "Private Key: $KEY_MOD"
  [ "$CERT_MOD" = "$KEY_MOD" ] && echo "✅ MATCH" || echo "❌ MISMATCH"
'

# Check certificate expiry
docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -dates

# Check certificate issuer
docker run --rm -v ssl-certs:/certs:ro alpine/openssl x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -issuer
```

### Check Container Status

```bash
# List all containers
docker ps -a

# Check specific service
docker ps --filter "name=nginx" --format "table {{.Names}}\t{{.Status}}"

# View logs
docker logs nginx
docker logs --tail 50 -f nginx

# Check container health
docker inspect nginx | jq '.[0].State'
```

### Check Services

```bash
# Test nginx is serving
curl -I https://7gram.xyz

# Check all subdomains
for domain in nc photo home audiobook; do
  echo "Testing $domain.7gram.xyz..."
  curl -I https://$domain.7gram.xyz
done
```

---

## 🚨 Troubleshooting

### Issue: "Certificate and private key do not match"

**Solution**: Run workflow with `force_ssl_regen=true`

This completely wipes and regenerates certificates.

### Issue: "Rate limit exceeded" from Let's Encrypt

**Cause**: Too many certificate requests

**Solution**:
1. Wait 1 hour (Let's Encrypt rate limits)
2. Or use staging mode:
   - Edit `.github/servers/freddy/ci-cd.yml`
   - Line ~254: Change `staging: false` to `staging: true`
   - Run workflow to generate staging cert
   - Test deployment
   - Change back to `staging: false` and redeploy

### Issue: "DNS validation failed"

**Cause**: Cloudflare DNS not propagating

**Solution**:
1. Verify DNS at: https://www.whatsmydns.net/
2. Check Cloudflare dashboard for correct records
3. Increase propagation time in workflow (line ~253)
4. Verify Cloudflare API token has DNS:Edit permission

### Issue: Nginx container won't start

**Symptoms**: Container exits immediately or crash loops

**Solution**:
```bash
# Check nginx logs
docker logs nginx

# Remove and recreate
docker stop nginx && docker rm nginx
cd ~/freddy
docker compose up -d nginx

# If still failing, wipe SSL and regenerate
docker volume rm ssl-certs
./run.sh prod start
```

### Issue: Services not accessible from internet

**Checklist**:
- [ ] Cloudflare DNS records point to Freddy's Tailscale IP
- [ ] Tailscale is running on Freddy
- [ ] Nginx is running and healthy
- [ ] SSL certificates are valid
- [ ] Cloudflare proxy is disabled (gray cloud) for direct IP
- [ ] Ports 80/443 are not blocked by firewall

---

## 📊 Monitoring

### GitHub Actions

Monitor deployments at:
- https://github.com/nuniesmith/actions/actions

### Discord Notifications

Deployment status is sent to Discord webhook (if configured).

Notifications include:
- Deployment status (success/failure)
- Service health check results
- Timestamp and git commit info

### Manual Monitoring

```bash
# Watch container status
watch docker ps

# Monitor all logs
docker compose logs -f

# Monitor specific service
docker logs -f nginx

# Check resource usage
docker stats
```

---

## 🔄 Scheduled Maintenance

### Weekly (Sundays 3am UTC)

Automatic SSL renewal check:
- Checks certificate expiry
- Renews if < 30 days remaining
- Updates Cloudflare DNS if needed
- Deploys renewed certificates

### Manual Maintenance

Recommended monthly:
```bash
# Prune unused resources
docker system prune -a --volumes -f

# Update images
cd ~/freddy
docker compose pull
./run.sh prod restart

# Check disk usage
df -h
du -sh ~/freddy
```

---

## 🔒 Security Notes

- All certificates are production Let's Encrypt certs
- SSL/TLS termination handled by nginx
- Secrets stored in GitHub Secrets (encrypted)
- SSH access via Tailscale VPN only
- No ports exposed to public internet directly
- Cloudflare provides DDoS protection

---

## 📚 Related Documentation

- SSL Troubleshooting: `SSL_TROUBLESHOOTING.md`
- GitHub Actions Workflow: `.github/servers/freddy/ci-cd.yml`
- SSL Certbot Action: `.github/actions/ssl-certbot-cloudflare/`

---

**Last Updated**: 2025-01-29
**Maintainer**: nuniesmith
**Status**: Active - SSL cleanup enhancements deployed