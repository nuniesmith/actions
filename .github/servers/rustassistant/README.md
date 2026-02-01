# RustAssistant - CI/CD Deployment Setup

Complete CI/CD pipeline for deploying RustAssistant to a Raspberry Pi via Tailscale and GitHub Actions.

## 🎯 Overview

This setup provides:
- ✅ **Automated Testing** - Rust fmt, clippy, and tests on every push
- ✅ **Multi-Arch Docker Builds** - Builds for both AMD64 and ARM64 (Raspberry Pi)
- ✅ **Secure Deployment** - Via Tailscale VPN (no public SSH exposure)
- ✅ **Discord Notifications** - CI/CD status updates
- ✅ **Zero-Downtime Deployments** - Automatic container updates

## 📋 Prerequisites

1. **Raspberry Pi** (or any ARM64 server)
   - Raspberry Pi 3B+, 4, or 5 recommended
   - Raspberry Pi OS (64-bit) or Ubuntu Server ARM64
   - At least 2GB RAM, 16GB storage

2. **Tailscale Account**
   - Free tier is sufficient
   - OAuth credentials for GitHub Actions

3. **Docker Hub Account**
   - For storing multi-arch Docker images

4. **GitHub Repository**
   - Your RustAssistant project repository

5. **Discord Webhook** (Optional)
   - For CI/CD notifications

## 🚀 Quick Start

### Step 1: Prepare Your Raspberry Pi

SSH into your Raspberry Pi and download the setup scripts:

```bash
# Download the setup scripts
wget https://raw.githubusercontent.com/YOUR_USERNAME/actions/main/.github/servers/rustassistant/setup-production-server.sh
wget https://raw.githubusercontent.com/YOUR_USERNAME/actions/main/.github/servers/rustassistant/generate-secrets.sh

# Make them executable
chmod +x setup-production-server.sh generate-secrets.sh

# Run the production server setup
sudo ./setup-production-server.sh
```

This script will:
- ✅ Install Docker (ARM64 optimized)
- ✅ Create the `actions` user for CI/CD
- ✅ Configure SSH
- ✅ Install Tailscale
- ✅ Setup firewall
- ✅ Create project directories

### Step 2: Connect to Tailscale

```bash
# Connect to your Tailscale network
sudo tailscale up

# Get your Tailscale IP (save this for GitHub secrets)
tailscale ip -4
```

### Step 3: Generate Deployment Secrets

```bash
# Generate SSH keys and credentials
sudo ./generate-secrets.sh
```

This will create a credentials file with all the values you need for GitHub.

**Important:** Save the output! You'll need these values in the next step.

### Step 4: Configure GitHub Secrets

Go to your repository settings:
```
https://github.com/YOUR_USERNAME/rustassistant/settings/secrets/actions
```

Add these **REQUIRED** secrets:

| Secret Name | Description | Where to Get It |
|-------------|-------------|-----------------|
| `PROD_TAILSCALE_IP` | Tailscale IP of your Raspberry Pi | Output of `tailscale ip -4` |
| `PROD_SSH_KEY` | SSH private key for actions user | From generate-secrets.sh output |
| `PROD_SSH_PORT` | SSH port (usually 22) | From generate-secrets.sh output |
| `PROD_SSH_USER` | Username: `actions` | Literal value: `actions` |
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth client ID | [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth) |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth secret | [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth) |
| `DOCKER_USERNAME` | Your Docker Hub username | [Docker Hub Settings](https://hub.docker.com/settings/general) |
| `DOCKER_TOKEN` | Docker Hub access token | [Docker Hub Security](https://hub.docker.com/settings/security) |

Add these **OPTIONAL** secrets:

| Secret Name | Description |
|-------------|-------------|
| `DISCORD_WEBHOOK_ACTIONS` | Discord webhook for CI/CD notifications |
| `RUSTASSISTANT_API_KEY` | API key for your RustAssistant application |

### Step 5: Add CI/CD Workflow to Your Repository

Copy the CI/CD workflow to your RustAssistant repository:

```bash
# In your rustassistant repository
mkdir -p .github/workflows

# Copy the workflow file
cp /path/to/actions/.github/servers/rustassistant/ci-cd.yml .github/workflows/ci-cd.yml

# Commit and push
git add .github/workflows/ci-cd.yml
git commit -m "Add CI/CD pipeline for Raspberry Pi deployment"
git push origin main
```

### Step 6: Deploy!

The CI/CD pipeline will automatically:
1. Run tests on every push
2. Build multi-arch Docker images on main branch
3. Deploy to your Raspberry Pi

**Manual trigger:**
Go to Actions → CI/CD Pipeline → Run workflow

## 📁 Required Files in Your Repository

Your RustAssistant repository should have:

```
rustassistant/
├── .github/
│   └── workflows/
│       └── ci-cd.yml          # The CI/CD workflow
├── docker/
│   └── rust/
│       └── Dockerfile         # Multi-stage Rust Dockerfile
├── docker-compose.prod.yml    # Production docker-compose (optional)
├── docker-compose.yml         # Development docker-compose
├── deploy/
│   └── env.template          # Environment variable template (optional)
├── run.sh                    # Simple start/stop script (optional)
├── Cargo.toml
└── src/
```

### Example `run.sh` Script

```bash
#!/bin/bash
# Simple deployment script

case "$1" in
    start)
        echo "🚀 Starting RustAssistant..."
        docker compose -f docker-compose.prod.yml pull
        docker compose -f docker-compose.prod.yml up -d
        ;;
    stop)
        echo "🛑 Stopping RustAssistant..."
        docker compose -f docker-compose.prod.yml down
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    logs)
        docker compose -f docker-compose.prod.yml logs -f
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs}"
        exit 1
        ;;
esac
```

### Example `docker-compose.prod.yml`

```yaml
version: '3.8'

services:
  rustassistant:
    image: nuniesmith/rustassistant:latest
    container_name: rustassistant
    restart: unless-stopped
    env_file:
      - .env
    ports:
      - "8080:8080"
    volumes:
      - ./data:/app/data
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

### Example `deploy/env.template`

```bash
# RustAssistant Environment Configuration
RUST_LOG=info
RUSTASSISTANT_API_KEY=__RUSTASSISTANT_API_KEY__

# Add your other environment variables here
```

## 🔧 Customization

### Update Docker Image Name

In `ci-cd.yml`, change:
```yaml
env:
  IMAGE_NAME: nuniesmith/rustassistant  # Change to your Docker Hub username
```

### Update Repository Path

The default deployment path is `~/rustassistant`. To change it, update in `ci-cd.yml`:
```yaml
project-path: ~/rustassistant  # Change to your preferred path
```

### Add More Secrets

If your app needs additional secrets, update `deploy/env.template` and the pre-deploy-command in `ci-cd.yml`:

```yaml
# In ci-cd.yml pre-deploy-command section
sed -i "s|__YOUR_SECRET__|${{ secrets.YOUR_SECRET }}|g" .env
```

## 📊 Monitoring

### View Deployment Logs

```bash
# SSH into your Raspberry Pi
ssh -p 22 actions@YOUR_TAILSCALE_IP

# View container logs
cd ~/rustassistant
docker compose logs -f

# Check container status
docker compose ps

# Check system resources
htop
docker system df
```

### Discord Notifications

If you configured `DISCORD_WEBHOOK_ACTIONS`, you'll receive notifications for:
- ✅ Build started
- ✅ Tests passed/failed
- ✅ Docker image built
- ✅ Deployment successful/failed

## 🐛 Troubleshooting

### Build Fails on ARM64

**Issue:** ARM builds timing out or failing

**Solution:**
```yaml
# Increase timeout in ci-cd.yml
timeout-minutes: 60  # Increase from 45
```

### SSH Connection Fails

**Issue:** Can't connect to Raspberry Pi

**Solution:**
1. Verify Tailscale is running: `tailscale status`
2. Check SSH service: `sudo systemctl status ssh`
3. Verify firewall: `sudo ufw status`
4. Test SSH locally: `ssh -p 22 actions@localhost`

### Docker Pull Fails

**Issue:** Cannot pull ARM64 images

**Solution:**
```bash
# Check Docker architecture
docker info | grep Architecture

# Should show: arm64 or aarch64

# Manual pull test
docker pull --platform linux/arm64 nuniesmith/rustassistant:latest
```

### Out of Disk Space

**Issue:** Raspberry Pi running out of space

**Solution:**
```bash
# Clean up Docker
docker system prune -af --volumes

# Check disk usage
df -h
docker system df

# Remove old images
docker image prune -af
```

## 🔒 Security Best Practices

1. **Use Tailscale** - Never expose SSH to the public internet
2. **Rotate Secrets** - Regenerate SSH keys and secrets periodically
3. **Monitor Logs** - Set up log monitoring and alerts
4. **Keep Updated** - Regularly update Raspberry Pi OS and Docker
5. **Backup Data** - Regular backups of important data volumes
6. **Use HTTPS** - If exposing web services, use SSL/TLS

## 📚 Additional Resources

- [Tailscale Setup Guide](https://tailscale.com/kb/1017/install/)
- [Docker on Raspberry Pi](https://docs.docker.com/engine/install/debian/)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)
- [Multi-Arch Docker Builds](https://docs.docker.com/build/building/multi-platform/)

## 🤝 Contributing

This CI/CD setup is part of the [nuniesmith/actions](https://github.com/nuniesmith/actions) repository.

## 📝 License

Same as your RustAssistant project license.

---

**Happy Deploying! 🚀**

For issues or questions, check the GitHub Actions logs or SSH into your Raspberry Pi to debug.