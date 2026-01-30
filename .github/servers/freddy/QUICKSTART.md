# 🚀 Freddy Server - Quick Start Guide

This guide will help you deploy the Freddy server (personal services) with automated SSL certificates and CI/CD.

## 📋 Prerequisites

### 1. Server Requirements (Freddy)
- ✅ Linux server (Ubuntu/Debian recommended)
- ✅ Docker & Docker Compose installed
- ✅ SSH access configured
- ✅ Tailscale installed and authenticated
- ✅ Ports 80 and 443 available
- ✅ User with Docker permissions

### 2. Domain & DNS
- ✅ Domain registered (e.g., `7gram.xyz`)
- ✅ Cloudflare account with domain added
- ✅ Cloudflare API token with DNS edit permissions

### 3. GitHub Repository
- ✅ Repository for Freddy project (e.g., `nuniesmith/freddy`)
- ✅ This actions repository accessible as shared actions

## 🔧 Initial Setup

### Step 1: Configure GitHub Secrets

In your GitHub repository settings, add these secrets:

```
CLOUDFLARE_API_TOKEN       # Cloudflare API token with DNS:Edit permissions
CLOUDFLARE_ZONE_ID         # Your Cloudflare zone ID for 7gram.xyz
SSL_EMAIL                  # Email for Let's Encrypt notifications
FREDDY_TAILSCALE_IP        # Freddy's Tailscale IP address
SSH_USER                   # SSH username (e.g., actions)
SSH_KEY                    # SSH private key for authentication
SSH_PORT                   # SSH port (default: 22)
TAILSCALE_OAUTH_CLIENT_ID  # Tailscale OAuth client ID
TAILSCALE_OAUTH_SECRET     # Tailscale OAuth secret
DOCKER_USERNAME            # Docker Hub username (optional)
DOCKER_TOKEN               # Docker Hub token (optional)
DISCORD_WEBHOOK_ACTIONS    # Discord webhook URL for notifications (optional)
```

### Step 2: Prepare Freddy Server

Connect to your Freddy server and run:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker (if not already installed)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose (if not already installed)
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installations
docker --version
docker-compose --version

# Install Tailscale (if not already installed)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Get Tailscale IP
tailscale ip -4
```

### Step 3: Create SSH User for GitHub Actions

```bash
# Create actions user
sudo useradd -m -s /bin/bash actions
sudo usermod -aG docker actions

# Create SSH directory
sudo mkdir -p /home/actions/.ssh
sudo chmod 700 /home/actions/.ssh

# Add your SSH public key
sudo nano /home/actions/.ssh/authorized_keys
# Paste your public key, save and exit

sudo chmod 600 /home/actions/.ssh/authorized_keys
sudo chown -R actions:actions /home/actions/.ssh

# Test SSH access
ssh actions@<FREDDY_TAILSCALE_IP> "echo 'SSH works!'"
```

### Step 4: Create Project Directory Structure

```bash
# Switch to actions user
sudo su - actions

# Create project directory
mkdir -p ~/freddy
cd ~/freddy

# The CI/CD will clone the repo here on first deployment
```

### Step 5: Create Docker Volume for SSL Certificates

```bash
# Create the ssl-certs volume (used by CI/CD)
docker volume create ssl-certs

# Verify it was created
docker volume ls | grep ssl-certs
```

### Step 6: Set Up Project Files on Freddy

In your `freddy` repository, create these files:

#### `docker-compose.yml`
```yaml
# Copy from: .github/servers/freddy/example-docker-compose.yml
# Customize as needed for your services
```

#### `.env`
```bash
# Environment variables for your services
TIMEZONE=America/New_York

# PhotoPrism
PHOTOPRISM_ADMIN_PASSWORD=your_secure_password
PHOTOPRISM_DB_PASSWORD=your_db_password
PHOTOPRISM_DB_ROOT_PASSWORD=your_root_password

# Nextcloud
NEXTCLOUD_ADMIN_PASSWORD=your_secure_password
NEXTCLOUD_DB_PASSWORD=your_db_password
NEXTCLOUD_DB_ROOT_PASSWORD=your_root_password

# Add other service credentials
```

#### `nginx/nginx.conf`
```nginx
# Copy from: .github/servers/freddy/example-nginx.conf
```

#### `nginx/conf.d/ssl.conf`
```nginx
# Copy from: .github/servers/freddy/example-nginx-conf.d/ssl.conf
```

#### `nginx/conf.d/7gram.xyz.conf`
```nginx
# Copy from: .github/servers/freddy/example-nginx-conf.d/7gram.xyz.conf
# Update SULLIVAN_TAILSCALE_IP if using Sullivan proxy
```

#### `run.sh`
```bash
#!/bin/bash
# Simple deployment script

case "$1" in
  start)
    docker compose up -d
    ;;
  stop)
    docker compose down
    ;;
  restart)
    docker compose restart
    ;;
  prod)
    if [ "$2" = "start" ]; then
      docker compose up -d --remove-orphans
    fi
    ;;
  logs)
    docker compose logs -f
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|prod start|logs}"
    exit 1
    ;;
esac
```

```bash
chmod +x run.sh
```

## 🚀 First Deployment

### Option 1: Manual Trigger (Recommended for First Time)

1. Go to your repository on GitHub
2. Click **Actions** tab
3. Select **🏠 Freddy Deploy** workflow
4. Click **Run workflow**
5. Leave defaults and click **Run workflow**

The workflow will:
1. ✅ Update Cloudflare DNS records
2. ✅ Generate Let's Encrypt SSL certificates
3. ✅ Deploy to Freddy server
4. ✅ Run health checks
5. ✅ Send notification (if configured)

### Option 2: Push to Main Branch

```bash
git add .
git commit -m "Initial Freddy deployment"
git push origin main
```

## ✅ Verify Deployment

### Check Workflow Status

1. Go to GitHub Actions
2. Watch the workflow run
3. Check each step for success ✅

### Check SSL Certificates

```bash
# On Freddy server
docker run --rm -v ssl-certs:/certs:ro busybox:latest ls -la /certs/live/7gram.xyz/
```

Expected output:
```
-rw-r--r-- cert.pem
-rw-r--r-- chain.pem
-rw-r--r-- fullchain.pem
-rw------- privkey.pem
```

### Check Running Containers

```bash
cd ~/freddy
docker compose ps
```

Expected output:
```
NAME                  STATUS       PORTS
nginx                 Up (healthy) 0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
photoprism            Up (healthy) 
nextcloud             Up (healthy)
homeassistant         Up (healthy)
audiobookshelf        Up (healthy)
```

### Test HTTPS Access

```bash
# From your local machine
curl -I https://7gram.xyz
curl -I https://photo.7gram.xyz
curl -I https://nc.7gram.xyz
curl -I https://home.7gram.xyz
curl -I https://audiobook.7gram.xyz
```

Expected: `200 OK` or `302 Found` responses with valid SSL

### Check Nginx Logs

```bash
docker logs nginx --tail 50
```

Look for any errors or warnings.

## 🔍 Troubleshooting

### Issue: nginx 500 Error

**Symptoms:** nginx returns 500 Internal Server Error

**Causes:**
1. SSL certificates not found
2. Backend service not running
3. Nginx config error

**Fix:**
```bash
# Check SSL certs
docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/live/7gram.xyz/

# Test nginx config
docker exec nginx nginx -t

# Check nginx error logs
docker logs nginx | grep error

# Check backend services
docker compose ps
```

### Issue: SSL Certificate Not Found

**Symptoms:** nginx fails to start, "certificate file not found"

**Fix:**
```bash
# Verify volume exists
docker volume inspect ssl-certs

# Re-run SSL generation
# Go to GitHub Actions → Run workflow manually

# Check if certs are in volume
docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/
```

### Issue: Git Clone/Pull Fails

**Symptoms:** pre-deploy-command fails with git errors

**Fix:**
```bash
# On Freddy server, manually fix
cd ~
sudo rm -rf freddy
mkdir freddy
cd freddy
git init
git remote add origin https://github.com/nuniesmith/freddy.git
git fetch
git checkout main
```

### Issue: Docker Permission Denied

**Symptoms:** "permission denied while trying to connect to Docker daemon"

**Fix:**
```bash
# Add actions user to docker group
sudo usermod -aG docker actions

# Logout and login again
sudo su - actions
```

### Issue: Backend Service Unhealthy

**Symptoms:** Health checks fail

**Fix:**
```bash
# Check logs for specific service
docker compose logs photoprism
docker compose logs nextcloud

# Restart specific service
docker compose restart photoprism

# Check service status
docker compose ps
```

## 🔄 Regular Operations

### Manual Deploy

```bash
# Trigger GitHub workflow manually
# OR SSH to server:
cd ~/freddy
git pull origin main
./run.sh restart
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f nginx
docker compose logs -f photoprism
```

### Restart Services

```bash
cd ~/freddy
./run.sh restart

# Or specific service
docker compose restart nginx
```

### Update SSL Certificates

Certificates auto-renew weekly via GitHub Actions schedule.

Manual renewal:
1. Go to GitHub Actions
2. Run workflow manually
3. Workflow runs every Sunday at 3am UTC automatically

### Check SSL Expiry

```bash
# On Freddy server
docker run --rm -v ssl-certs:/certs:ro alpine/openssl \
  x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -enddate
```

## 📚 Additional Resources

- **Detailed Review:** See `REVIEW-AND-FIXES.md` for complete technical analysis
- **Example Configs:** See `example-*.yml` and `example-nginx-conf.d/` files
- **Actions Documentation:** See `.github/actions/README.md`

## 🆘 Getting Help

If you're stuck:

1. Check workflow logs in GitHub Actions
2. Check server logs: `docker compose logs`
3. Review nginx error logs: `docker logs nginx`
4. Test nginx config: `docker exec nginx nginx -t`
5. Verify SSL certs exist in Docker volume
6. Check all services are running: `docker compose ps`

## 🎉 Success Checklist

- ✅ GitHub secrets configured
- ✅ Freddy server prepared with Docker & Tailscale
- ✅ SSH access working
- ✅ Project files created on server
- ✅ First deployment successful
- ✅ SSL certificates generated and deployed
- ✅ All services running and healthy
- ✅ HTTPS access working for all subdomains
- ✅ No nginx 500 errors

**Congratulations! Your Freddy server is now deployed! 🚀**