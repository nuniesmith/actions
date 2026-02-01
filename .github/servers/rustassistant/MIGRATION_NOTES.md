# Migration Notes: Kraken to RustAssistant

This document outlines the changes made to convert the Kraken Trading Bot CI/CD pipeline to RustAssistant for Raspberry Pi deployment.

## 📋 Summary of Changes

The CI/CD pipeline and deployment scripts have been adapted from the Kraken Trading Bot to work with RustAssistant, with specific optimizations for Raspberry Pi (ARM64) deployment.

## 🔄 Files Updated

### 1. `ci-cd.yml` - Main CI/CD Pipeline

**Key Changes:**
- ✅ Changed project name from "Kraken Trading Bot" to "RustAssistant"
- ✅ Updated Docker image name: `nuniesmith/kraken` → `nuniesmith/rustassistant`
- ✅ Removed trading-specific secrets (KRAKEN_API_KEY, KRAKEN_API_SECRET, DISCORD_WEBHOOK_KRAKEN)
- ✅ Removed smoke test examples job (trading bot specific)
- ✅ Updated deployment path: `~/kraken` → `~/rustassistant`
- ✅ Simplified environment variable handling (removed trading-specific configs)
- ✅ Added ARM64-specific deployment messages and checks
- ✅ Increased Docker build timeout to 45 minutes (ARM builds take longer)
- ✅ Added architecture detection in post-deploy verification

**Secrets Removed:**
- `DISCORD_WEBHOOK_KRAKEN` (trading signals webhook)
- `KRAKEN_API_KEY` (exchange API key)
- `KRAKEN_API_SECRET` (exchange API secret)

**Secrets Added/Optional:**
- `RUSTASSISTANT_API_KEY` (optional, for your application)

**What Stayed the Same:**
- Multi-arch Docker builds (linux/amd64, linux/arm64) ✅
- Tailscale VPN integration ✅
- SSH deployment via actions user ✅
- Discord notifications for CI/CD status ✅
- Test and lint workflow ✅
- Docker Hub push workflow ✅

### 2. `generate-secrets.sh` - Secrets Generation Script

**Key Changes:**
- ✅ Updated header from "FKS Trading Platform" to "RustAssistant"
- ✅ Removed FKS-specific environment file paths
- ✅ Simplified application secrets (removed trading-specific ones)
- ✅ Added ARM architecture detection and Raspberry Pi messages
- ✅ Updated SSH key comment to include "rustassistant"
- ✅ Changed credentials file name: `fks_credentials_*` → `rustassistant_credentials_*`
- ✅ Simplified GitHub secrets instructions
- ✅ Added Raspberry Pi deployment notes
- ✅ Removed complex .env update logic (simplified for generic use)

**Secrets Generated:**
- `RUSTASSISTANT_API_KEY` (replaces complex trading bot secrets)
- `JWT_SECRET` (kept for authentication)
- `SESSION_SECRET` (kept for sessions)
- `ADMIN_PASSWORD` (kept for admin access)

**Removed:**
- `POSTGRES_PASSWORD`
- `QDRANT_API_KEY`
- `WEBHOOK_SECRET`
- `API_KEY` (generic, replaced with RUSTASSISTANT_API_KEY)
- Complex .env file manipulation

### 3. `setup-production-server.sh` - Server Setup Script

**Key Changes:**
- ✅ Updated header from "FKS Trading Platform" to "RustAssistant"
- ✅ Simplified to focus on Docker and CI/CD setup
- ✅ Added Raspberry Pi detection and optimizations
- ✅ Removed NVIDIA GPU support (not relevant for Raspberry Pi)
- ✅ Removed complex environment file creation
- ✅ Updated project directory: `~/fks` → `~/rustassistant`
- ✅ Added cgroup memory enablement for Raspberry Pi
- ✅ Added swap configuration for low-memory systems
- ✅ Simplified user setup (removed complex multi-user logic)
- ✅ Removed systemd service creation (handled by Docker Compose)
- ✅ Removed log rotation config (handled by Docker)

**Raspberry Pi Optimizations Added:**
- Memory cgroup enablement in `/boot/cmdline.txt`
- Swap increase for systems with <2GB RAM
- ARM64 architecture detection and messaging
- Docker log rotation configuration
- File descriptor limit increases

**Removed:**
- NVIDIA Container Toolkit installation
- Complex .env template with 100+ lines
- Systemd service for auto-start
- Custom log rotation configuration
- Application-specific directory structure

### 4. `README.md` - Documentation (NEW)

**Created From Scratch:**
- ✅ Complete quick start guide
- ✅ Step-by-step Raspberry Pi setup instructions
- ✅ GitHub secrets configuration guide
- ✅ Docker Compose examples
- ✅ Troubleshooting section
- ✅ Raspberry Pi specific notes
- ✅ Security best practices
- ✅ Monitoring and debugging commands

## 🎯 Migration Checklist

If you're adapting this for your own RustAssistant project:

- [ ] Update Docker image name in `ci-cd.yml`
- [ ] Update GitHub repository URLs in scripts
- [ ] Add required secrets to GitHub
- [ ] Create `docker-compose.yml` or `docker-compose.prod.yml`
- [ ] Create `deploy/env.template` if you need environment variables
- [ ] Update `run.sh` script (optional but recommended)
- [ ] Test on Raspberry Pi before production

## 🔑 Required GitHub Secrets

### Minimum Required (8 secrets):

1. `PROD_TAILSCALE_IP` - Your Raspberry Pi's Tailscale IP
2. `PROD_SSH_KEY` - SSH private key from generate-secrets.sh
3. `PROD_SSH_PORT` - Usually `22`
4. `PROD_SSH_USER` - Usually `actions`
5. `TAILSCALE_OAUTH_CLIENT_ID` - From Tailscale admin console
6. `TAILSCALE_OAUTH_SECRET` - From Tailscale admin console
7. `DOCKER_USERNAME` - Your Docker Hub username
8. `DOCKER_TOKEN` - Your Docker Hub access token

### Optional (2 secrets):

9. `DISCORD_WEBHOOK_ACTIONS` - For CI/CD notifications
10. `RUSTASSISTANT_API_KEY` - For your application

**Total: 8-10 secrets** (down from 13+ in Kraken setup)

## 🆚 Comparison: Kraken vs RustAssistant

| Feature | Kraken | RustAssistant |
|---------|--------|---------------|
| **Target Platform** | General Linux | Raspberry Pi (ARM64) |
| **Application Type** | Trading Bot | Generic Rust App |
| **Secrets Count** | 13+ | 8-10 |
| **Smoke Tests** | Yes (trading examples) | No (generic) |
| **Deployment Mode** | Simulation/Live | Production |
| **Environment Complexity** | High (trading specific) | Low (generic) |
| **Docker Images** | Multi-arch | Multi-arch |
| **Raspberry Pi Optimized** | No | Yes |
| **Setup Complexity** | High | Medium |

## 🚀 What's Better in RustAssistant Version

1. **Simpler Secrets** - Only 8 required secrets vs 13+
2. **Raspberry Pi Focus** - Specific optimizations for Pi deployment
3. **Less Opinionated** - Works for any Rust application
4. **Better Documentation** - Complete README with examples
5. **Cleaner Scripts** - Removed trading-specific complexity
6. **ARM64 First** - Built specifically for Raspberry Pi
7. **Generic Use Case** - Can be adapted for any Rust project

## 🔧 Post-Migration Tasks

After using these files:

1. **Customize Docker Image Name**
   - Update `IMAGE_NAME` in `ci-cd.yml`
   - Update in `docker-compose.yml` examples

2. **Add Your Application Secrets**
   - Update `deploy/env.template` with your variables
   - Add corresponding GitHub secrets
   - Update `pre-deploy-command` in `ci-cd.yml` to substitute them

3. **Test Deployment**
   - Run `setup-production-server.sh` on your Raspberry Pi
   - Run `generate-secrets.sh` to get credentials
   - Add secrets to GitHub
   - Push to main branch and watch deployment

4. **Monitor Performance**
   - Check Docker logs on Raspberry Pi
   - Monitor Discord notifications
   - Verify ARM64 image is being used

## 📝 Notes

- **ARM64 builds are slower** - Increased timeout to 45 minutes (was 30)
- **Multi-arch is preserved** - Still builds for both amd64 and arm64
- **Tailscale is mandatory** - Don't expose SSH to public internet
- **Discord notifications are optional** - But highly recommended
- **Environment file is flexible** - Template is optional, not required

## 🐛 Common Issues

### Issue: ARM build times out
**Solution:** Increase `timeout-minutes` in `ci-cd.yml` build job

### Issue: Can't connect to Raspberry Pi
**Solution:** Verify Tailscale is running on both GitHub Actions runner and Pi

### Issue: Docker pull fails on Pi
**Solution:** Check `docker info | grep Architecture` shows arm64

### Issue: Out of disk space on Pi
**Solution:** Run `docker system prune -af --volumes`

## 🎓 Learning Resources

- **Original Kraken Setup**: `.github/servers/kraken/ci-cd.yml`
- **Generic Scripts**: `scripts/generate-secrets.sh` and `scripts/setup-prod-server.sh`
- **RustAssistant README**: `README.md` in this directory
- **GitHub Actions Docs**: https://docs.github.com/en/actions

## ✅ Success Indicators

You'll know the migration is successful when:

1. ✅ Tests pass on every push
2. ✅ Docker images build for both amd64 and arm64
3. ✅ Images successfully push to Docker Hub
4. ✅ Deployment to Raspberry Pi completes without errors
5. ✅ Container starts and runs on Raspberry Pi
6. ✅ Discord notifications arrive (if configured)
7. ✅ You can SSH to Pi and see running containers

## 🎉 Next Steps

1. Copy `ci-cd.yml` to your RustAssistant repository
2. Run server setup scripts on your Raspberry Pi
3. Configure GitHub secrets
4. Push to main and watch it deploy!

---

**Happy Deploying! 🦀🥧**

This migration simplifies the Kraken trading bot setup into a generic, Raspberry Pi-optimized CI/CD pipeline that works for any Rust application.