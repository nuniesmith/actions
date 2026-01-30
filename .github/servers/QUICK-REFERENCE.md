# 🚀 Quick Reference Card

## 📊 Server Overview

| Server | Role | Access | IP |
|--------|------|--------|-----|
| **Freddy** | Gateway + Personal Services | Public (via Cloudflare) | FREDDY_TAILSCALE_IP |
| **Sullivan** | Media Server | Private (Tailscale only) | SULLIVAN_TAILSCALE_IP |

---

## 🌐 Service URLs

### Freddy Services
```
https://7gram.xyz                    # Main domain
https://photo.7gram.xyz              # PhotoPrism
https://nc.7gram.xyz                 # Nextcloud
https://home.7gram.xyz               # Home Assistant
https://audiobook.7gram.xyz          # Audiobookshelf
```

### Sullivan Services (via Freddy proxy)
```
https://emby.sullivan.7gram.xyz      # Emby
https://jellyfin.sullivan.7gram.xyz  # Jellyfin
https://plex.sullivan.7gram.xyz      # Plex
https://sonarr.sullivan.7gram.xyz    # Sonarr
https://radarr.sullivan.7gram.xyz    # Radarr
https://lidarr.sullivan.7gram.xyz    # Lidarr
https://jackett.sullivan.7gram.xyz   # Jackett
https://qbit.sullivan.7gram.xyz      # qBittorrent
```

---

## 🔑 GitHub Secrets Checklist

### Required for Both
- [ ] `TAILSCALE_OAUTH_CLIENT_ID`
- [ ] `TAILSCALE_OAUTH_SECRET`
- [ ] `SSH_USER` (default: actions)
- [ ] `SSH_PORT` (default: 22)

### Freddy Specific
- [ ] `FREDDY_TAILSCALE_IP`
- [ ] `SSH_KEY`
- [ ] `CLOUDFLARE_API_TOKEN`
- [ ] `CLOUDFLARE_ZONE_ID`
- [ ] `SSL_EMAIL`

### Sullivan Specific
- [ ] `SULLIVAN_TAILSCALE_IP`
- [ ] `SULLIVAN_SSH_KEY`
- [ ] `SONARR_API_KEY`
- [ ] `RADARR_API_KEY`
- [ ] `LIDARR_API_KEY`
- [ ] `DOPLARR_TOKEN`

### Optional
- [ ] `DOCKER_USERNAME`
- [ ] `DOCKER_TOKEN`
- [ ] `DISCORD_WEBHOOK_ACTIONS`

---

## 💻 Essential Commands

### Freddy Server

```bash
# SSH to Freddy
ssh actions@<FREDDY_TAILSCALE_IP>

# Check services
cd ~/freddy
docker compose ps

# View logs
docker logs nginx
docker logs photoprism
docker compose logs -f

# Restart services
./run.sh restart
docker compose restart nginx

# Check SSL certificates
docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/live/7gram.xyz/

# Test nginx config
docker exec nginx nginx -t

# Check disk space
df -h /
```

### Sullivan Server

```bash
# SSH to Sullivan
ssh actions@<SULLIVAN_TAILSCALE_IP>

# Check services
cd ~/sullivan
docker compose ps

# View logs
docker logs emby
docker logs plex
docker compose logs -f

# Restart services
./run.sh restart
docker compose restart emby

# Check firewall
sudo ufw status verbose

# Check resources
docker stats --no-stream
df -h /
free -h

# Check connectivity to Freddy
ping <FREDDY_TAILSCALE_IP>
```

---

## 🔧 Quick Troubleshooting

### Nginx 500 Error (Freddy)

```bash
# 1. Check SSL certificates exist
docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/live/7gram.xyz/

# 2. Test nginx config
docker exec nginx nginx -t

# 3. Check nginx logs
docker logs nginx --tail 100 | grep error

# 4. Check backend service
docker compose ps photoprism  # or whatever service is failing

# 5. Restart nginx
docker compose restart nginx
```

### Service Unreachable (Sullivan)

```bash
# 1. Check if container running
docker ps | grep emby

# 2. Check firewall allows Freddy
sudo ufw status | grep <FREDDY_TAILSCALE_IP>

# 3. Test port from Sullivan
curl http://localhost:8096  # Emby port

# 4. Check Tailscale connectivity
tailscale status
ping <FREDDY_TAILSCALE_IP>

# 5. Check logs
docker logs emby --tail 50
```

### Git Issues

```bash
# Freddy - reset repository
cd ~
rm -rf freddy
mkdir freddy
cd freddy
git clone https://github.com/nuniesmith/freddy.git .

# Sullivan - reset repository  
cd ~
rm -rf sullivan
mkdir sullivan
cd sullivan
git clone https://github.com/nuniesmith/sullivan.git .
```

### SSL Certificate Issues (Freddy)

```bash
# Check certificate expiry
docker run --rm -v ssl-certs:/certs:ro alpine/openssl \
  x509 -in /certs/live/7gram.xyz/fullchain.pem -noout -enddate

# Manually trigger SSL renewal
# Go to GitHub Actions → Freddy Deploy → Run workflow

# Check if volume exists
docker volume ls | grep ssl-certs

# Inspect certificate contents
docker run --rm -v ssl-certs:/certs:ro busybox cat /certs/live/7gram.xyz/fullchain.pem | head -5
```

---

## 📋 Deployment Checklist

### Freddy Deployment

- [ ] All GitHub Secrets configured
- [ ] SSL certificates generated (check Docker volume)
- [ ] DNS records point to Freddy Tailscale IP
- [ ] nginx container running and healthy
- [ ] All personal services running
- [ ] HTTPS access works for all domains
- [ ] Sullivan proxy working

### Sullivan Deployment

- [ ] All GitHub Secrets configured
- [ ] Firewall configured (UFW)
- [ ] API keys injected into .env
- [ ] All media services running
- [ ] Accessible from Freddy over Tailscale
- [ ] NOT accessible from public internet

---

## 🔄 Common Operations

### Deploy Latest Changes

```bash
# Option 1: Push to main (automatic)
git push origin main

# Option 2: Manual trigger
# GitHub → Actions → Select workflow → Run workflow
```

### Update SSL Certificates (Freddy)

```bash
# Automatic: Runs every Sunday at 3am UTC
# Manual: GitHub Actions → Freddy Deploy → Run workflow
```

### Restart All Services

```bash
# Freddy
cd ~/freddy && ./run.sh restart

# Sullivan
cd ~/sullivan && ./run.sh restart
```

### View Service Status

```bash
# Freddy
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Sullivan
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
```

### Check Resources

```bash
# Disk usage
df -h /

# Memory usage
free -h

# Container resource usage
docker stats --no-stream

# Top 5 containers by memory
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}" | head -6
```

---

## 🆘 Emergency Procedures

### Freddy Down (Total Outage)

```bash
# 1. Check if server is reachable
ping <FREDDY_TAILSCALE_IP>

# 2. SSH and check Docker
ssh actions@<FREDDY_TAILSCALE_IP>
docker ps

# 3. Check nginx specifically
docker logs nginx --tail 100

# 4. Restart all services
cd ~/freddy
./run.sh stop
./run.sh start

# 5. If still down, check Tailscale
sudo tailscale status
```

### Sullivan Down

```bash
# 1. Check from Freddy first
ssh actions@<FREDDY_TAILSCALE_IP>
ping <SULLIVAN_TAILSCALE_IP>
curl http://<SULLIVAN_TAILSCALE_IP>:8096

# 2. SSH to Sullivan directly
ssh actions@<SULLIVAN_TAILSCALE_IP>
docker ps

# 3. Restart services
cd ~/sullivan
./run.sh restart

# 4. Check logs
docker compose logs --tail 50
```

### SSL Certificate Expired

```bash
# This should never happen (auto-renewal), but if it does:

# 1. Manually trigger renewal via GitHub Actions
# 2. Or SSH to Freddy and verify volume:
docker volume inspect ssl-certs

# 3. Re-run Freddy deployment workflow
# 4. Check nginx logs after deployment
docker logs nginx --tail 100
```

---

## 📞 Getting Help

### Check These First

1. **GitHub Actions logs** - See what failed in the workflow
2. **Docker logs** - `docker compose logs <service>`
3. **Nginx logs** - `docker logs nginx`
4. **Health checks** - Workflow shows container health status

### Documentation

- Architecture: `.github/servers/ARCHITECTURE.md`
- Freddy Setup: `.github/servers/freddy/QUICKSTART.md`
- Freddy Review: `.github/servers/freddy/REVIEW-AND-FIXES.md`
- Sullivan Review: `.github/servers/sullivan/REVIEW.md`
- Summary: `.github/servers/SUMMARY.md`

### Workflow URLs

```
Freddy: https://github.com/nuniesmith/actions/actions/workflows/freddy-ci-cd.yml
Sullivan: https://github.com/nuniesmith/actions/actions/workflows/sullivan-ci-cd.yml
```

---

## 🔐 Security Notes

- ✅ Sullivan has NO public access (Tailscale only)
- ✅ Sullivan firewall only allows Freddy's IP
- ✅ All secrets stored in GitHub Secrets
- ✅ SSL certificates auto-renew weekly
- ✅ SSH key-based authentication only
- ⚠️ Rotate API keys every 90 days
- ⚠️ Review firewall logs monthly

---

## ⚡ Quick Status Check

```bash
# One-liner for Freddy health
ssh actions@<FREDDY_IP> "cd ~/freddy && docker compose ps && docker run --rm -v ssl-certs:/c:ro busybox ls /c/live/7gram.xyz/"

# One-liner for Sullivan health
ssh actions@<SULLIVAN_IP> "cd ~/sullivan && docker compose ps && df -h / && free -h"
```

---

## 🎯 Success Indicators

### Everything is working when:

**Freddy:**
- ✅ All domains resolve to Freddy Tailscale IP
- ✅ HTTPS works without certificate warnings
- ✅ nginx container healthy
- ✅ Personal services accessible
- ✅ Can proxy to Sullivan services

**Sullivan:**
- ✅ All containers running and healthy
- ✅ UFW firewall active and configured
- ✅ Reachable from Freddy only
- ✅ Media services streaming properly
- ✅ NOT reachable from public internet

**Both:**
- ✅ GitHub Actions workflows pass
- ✅ Health checks green
- ✅ No errors in logs
- ✅ Tailscale connected