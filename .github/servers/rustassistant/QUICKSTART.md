# RustAssistant - Quick Start Guide

Get RustAssistant deployed to your Raspberry Pi in under 15 minutes.

## 🎯 Prerequisites Checklist

Before you start, make sure you have:

- [ ] Raspberry Pi (3B+, 4, or 5) with Raspberry Pi OS 64-bit
- [ ] SSH access to your Raspberry Pi
- [ ] Tailscale account (free tier is fine)
- [ ] Docker Hub account (free tier is fine)
- [ ] GitHub account with your RustAssistant repository
- [ ] Discord server (optional, for notifications)

## 🚀 5-Step Deployment

### Step 1: Setup Your Raspberry Pi (5 minutes)

SSH into your Raspberry Pi and run:

```bash
# Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/actions/main/.github/servers/rustassistant/setup-production-server.sh | sudo bash

# Or download first, review, then run:
wget https://raw.githubusercontent.com/YOUR_USERNAME/actions/main/.github/servers/rustassistant/setup-production-server.sh
chmod +x setup-production-server.sh
sudo ./setup-production-server.sh
```

**What this does:**
- ✅ Installs Docker (optimized for ARM64)
- ✅ Creates the `actions` user for deployments
- ✅ Configures SSH and firewall
- ✅ Installs Tailscale
- ✅ Sets up project directories

### Step 2: Connect to Tailscale (2 minutes)

```bash
# Connect to your Tailscale network
sudo tailscale up

# Get your Tailscale IP (save this!)
tailscale ip -4
```

**Save the IP address** - you'll need it for GitHub secrets.

Example output: `100.64.0.15`

### Step 3: Generate Secrets (3 minutes)

```bash
# Download and run the secrets generator
wget https://raw.githubusercontent.com/YOUR_USERNAME/actions/main/.github/servers/rustassistant/generate-secrets.sh
chmod +x generate-secrets.sh
sudo ./generate-secrets.sh
```

**What this does:**
- ✅ Creates SSH keys for GitHub Actions
- ✅ Generates secure API keys
- ✅ Detects your Tailscale IP
- ✅ Outputs everything in GitHub-friendly format

**IMPORTANT:** Copy the output! You'll paste it into GitHub in the next step.

The script creates a file like `/tmp/rustassistant_credentials_1234567890.txt`

View it with:
```bash
sudo cat /tmp/rustassistant_credentials_*.txt
```

### Step 4: Configure GitHub (3 minutes)

#### A. Add Repository Secrets

Go to: `https://github.com/YOUR_USERNAME/rustassistant/settings/secrets/actions`

Click "New repository secret" for each:

**Deployment Secrets (from generate-secrets.sh output):**
```
Name: PROD_TAILSCALE_IP
Value: 100.64.0.15  (your Tailscale IP)

Name: PROD_SSH_KEY
Value: (paste entire private key, including BEGIN/END lines)

Name: PROD_SSH_PORT
Value: 22

Name: PROD_SSH_USER
Value: actions
```

**Tailscale Secrets (from Tailscale admin console):**

Get these from: https://login.tailscale.com/admin/settings/oauth

```
Name: TAILSCALE_OAUTH_CLIENT_ID
Value: (from Tailscale)

Name: TAILSCALE_OAUTH_SECRET
Value: (from Tailscale)
```

**Docker Hub Secrets:**

Get token from: https://hub.docker.com/settings/security

```
Name: DOCKER_USERNAME
Value: yourusername

Name: DOCKER_TOKEN
Value: dckr_pat_...
```

**Optional Secrets:**

```
Name: DISCORD_WEBHOOK_ACTIONS
Value: https://discord.com/api/webhooks/...

Name: RUSTASSISTANT_API_KEY
Value: (from generate-secrets.sh output)
```

#### B. Add CI/CD Workflow

In your RustAssistant repository:

```bash
# Create workflows directory
mkdir -p .github/workflows

# Copy the CI/CD workflow
# (Download from this repo or copy the ci-cd.yml file)
```

**Quick copy method:**

```bash
# In your rustassistant repo
cd .github/workflows

# Download the workflow
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/actions/main/.github/servers/rustassistant/ci-cd.yml -o ci-cd.yml

# Update the image name in the file
sed -i 's/nuniesmith\/rustassistant/YOUR_USERNAME\/rustassistant/' ci-cd.yml
```

### Step 5: Deploy! (2 minutes)

Commit and push the workflow:

```bash
git add .github/workflows/ci-cd.yml
git commit -m "Add CI/CD pipeline"
git push origin main
```

**Watch it deploy:**
- Go to: `https://github.com/YOUR_USERNAME/rustassistant/actions`
- Click on the running workflow
- Watch the magic happen! 🎉

## ✅ Verification

After deployment completes, verify everything works:

```bash
# SSH to your Raspberry Pi
ssh -p 22 actions@YOUR_TAILSCALE_IP

# Check if containers are running
docker ps

# View logs
cd ~/rustassistant
docker compose logs -f

# Check system resources
htop
```

Expected output of `docker ps`:
```
CONTAINER ID   IMAGE                                STATUS
abc123def456   nuniesmith/rustassistant:latest     Up 2 minutes
```

## 🎊 Success!

You should now have:

✅ RustAssistant running on your Raspberry Pi
✅ Automatic deployments on every push to main
✅ Multi-arch Docker images (works on both x86 and ARM64)
✅ Secure access via Tailscale VPN
✅ Optional Discord notifications

## 🔄 Making Changes

Every time you push to `main`, the CI/CD will:

1. Run tests and linting
2. Build new Docker images
3. Push to Docker Hub
4. Deploy to your Raspberry Pi
5. Notify you on Discord (if configured)

No manual steps required!

## 🐛 Troubleshooting

### Can't Connect to Raspberry Pi

```bash
# On your Pi, check Tailscale
tailscale status

# If not running
sudo tailscale up

# Check SSH
sudo systemctl status ssh
```

### Docker Not Found

```bash
# Verify Docker is installed
docker --version

# If not, re-run setup script
sudo ./setup-production-server.sh
```

### Deployment Fails

Check GitHub Actions logs:
1. Go to Actions tab in GitHub
2. Click on failed workflow
3. Expand failed step
4. Read error message

Common fixes:
- Verify all secrets are set correctly
- Check Tailscale is connected on Pi
- Ensure SSH key is correct (entire key, including BEGIN/END)

### Out of Space on Pi

```bash
# Clean up Docker
docker system prune -af --volumes

# Check space
df -h
```

## 📚 Next Steps

- **Add monitoring**: Set up Prometheus/Grafana
- **Configure backups**: Regular data backups
- **Set up logging**: Centralized log aggregation
- **Add staging**: Create staging environment
- **Set up alerts**: Monitor health and uptime

## 🆘 Getting Help

1. **Check the logs:**
   ```bash
   # On Raspberry Pi
   docker compose logs -f
   
   # GitHub Actions
   Check workflow logs in GitHub UI
   ```

2. **Read the docs:**
   - [Full README](README.md)
   - [Migration Notes](MIGRATION_NOTES.md)
   - [Troubleshooting Guide](README.md#troubleshooting)

3. **Common issues:**
   - SSH connection: Check Tailscale on both sides
   - Build timeout: Increase timeout in ci-cd.yml
   - Disk space: Run `docker system prune -af`

## 💡 Pro Tips

1. **Test locally first:**
   ```bash
   docker compose up
   ```

2. **Use semantic versioning:**
   ```bash
   git tag v1.0.0
   git push --tags
   ```

3. **Monitor your Pi:**
   ```bash
   watch -n 1 "docker stats --no-stream"
   ```

4. **Keep it updated:**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

5. **Backup before updates:**
   ```bash
   docker compose down
   tar -czf backup-$(date +%F).tar.gz ~/rustassistant
   ```

## 🎯 Summary

You now have a production-ready CI/CD pipeline that:
- ✅ Runs on Raspberry Pi (ARM64)
- ✅ Deploys automatically on git push
- ✅ Uses secure Tailscale VPN
- ✅ Sends Discord notifications
- ✅ Builds multi-arch Docker images

**Total setup time:** ~15 minutes
**Ongoing maintenance:** Minimal (just push code!)

---

**Happy Coding! 🦀🥧**

Need help? Check [README.md](README.md) for detailed documentation.