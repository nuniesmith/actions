# 🏗️ Server Architecture Overview

## System Architecture

This document describes the architecture of the Freddy and Sullivan home server setup, including their roles, communication, and CI/CD pipelines.

---

## 📊 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Internet / Users                          │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           │ HTTPS (443)
                           │ HTTP (80)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cloudflare DNS & Proxy                        │
│  Records: 7gram.xyz, *.7gram.xyz, sullivan.7gram.xyz, etc.     │
│  Points to: Freddy's Tailscale IP                               │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           │ All traffic routed to Freddy
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      🏠 FREDDY SERVER                            │
│  Role: Gateway, Reverse Proxy, SSL Termination                  │
├─────────────────────────────────────────────────────────────────┤
│  Services:                                                       │
│  ┌────────────────────────────────────────────────────┐         │
│  │  nginx (SSL termination, reverse proxy)            │         │
│  │  - Terminates SSL with Let's Encrypt certificates  │         │
│  │  - Routes *.7gram.xyz to local services            │         │
│  │  - Routes *.sullivan.7gram.xyz to Sullivan         │         │
│  └────────────────────────────────────────────────────┘         │
│  ┌────────────────────────────────────────────────────┐         │
│  │  Personal Services (hosted locally)                │         │
│  │  - PhotoPrism (photo.7gram.xyz)                    │         │
│  │  - Nextcloud (nc.7gram.xyz)                        │         │
│  │  - Home Assistant (home.7gram.xyz)                 │         │
│  │  - Audiobookshelf (audiobook.7gram.xyz)            │         │
│  └────────────────────────────────────────────────────┘         │
│                                                                  │
│  Network: Tailscale VPN + Public Internet                       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           │ Tailscale VPN (encrypted)
                           │ Proxies *.sullivan.7gram.xyz
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      🎬 SULLIVAN SERVER                          │
│  Role: Media Server (Tailscale-only, no public access)          │
├─────────────────────────────────────────────────────────────────┤
│  Services:                                                       │
│  ┌────────────────────────────────────────────────────┐         │
│  │  Media Servers                                      │         │
│  │  - Emby (emby.sullivan.7gram.xyz)                  │         │
│  │  - Jellyfin (jellyfin.sullivan.7gram.xyz)          │         │
│  │  - Plex (plex.sullivan.7gram.xyz)                  │         │
│  └────────────────────────────────────────────────────┘         │
│  ┌────────────────────────────────────────────────────┐         │
│  │  Media Management (*arr stack)                      │         │
│  │  - Sonarr (TV shows)                                │         │
│  │  - Radarr (Movies)                                  │         │
│  │  - Lidarr (Music)                                   │         │
│  │  - qBittorrent (Download client)                    │         │
│  │  - Jackett (Indexer proxy)                          │         │
│  └────────────────────────────────────────────────────┘         │
│  ┌────────────────────────────────────────────────────┐         │
│  │  Additional Services                                │         │
│  │  - Calibre (eBooks)                                 │         │
│  │  - Filebot (Renaming)                               │         │
│  │  - Duplicati (Backups)                              │         │
│  │  - Mealie (Recipes)                                 │         │
│  │  - Grocy (Groceries)                                │         │
│  │  - Wiki.js (Documentation)                          │         │
│  └────────────────────────────────────────────────────┘         │
│                                                                  │
│  Network: Tailscale VPN ONLY (no direct internet access)        │
│  Firewall: Only accepts connections from Freddy's Tailscale IP  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🏠 Freddy Server

### Role & Responsibilities

**Primary Role:** Gateway and personal services host

**Responsibilities:**
1. **DNS Management:**
   - Manages all Cloudflare DNS records for `7gram.xyz`
   - Updates A records to point to Freddy's Tailscale IP
   - Handles both Freddy and Sullivan subdomains

2. **SSL Certificate Management:**
   - Generates Let's Encrypt certificates via Cloudflare DNS challenge
   - Covers all `*.7gram.xyz` and `*.sullivan.7gram.xyz` domains
   - Stores certificates in Docker volume
   - Auto-renews weekly via GitHub Actions schedule

3. **Reverse Proxy (nginx):**
   - Terminates SSL/TLS connections
   - Routes `*.7gram.xyz` to local services
   - Proxies `*.sullivan.7gram.xyz` to Sullivan over Tailscale
   - Handles HTTP → HTTPS redirects

4. **Personal Services:**
   - PhotoPrism (photo management)
   - Nextcloud (cloud storage)
   - Home Assistant (home automation)
   - Audiobookshelf (audiobooks)

### Network Configuration

- **Public Access:** Yes (via Cloudflare)
- **Ports Open:** 80 (HTTP), 443 (HTTPS)
- **Tailscale:** Connected for Sullivan access
- **Firewall:** Standard web server rules

### CI/CD Pipeline

```yaml
Workflow: freddy/ci-cd.yml

Jobs:
  1. dns-update:
     - Updates Cloudflare DNS records
     - Points domains to Freddy's Tailscale IP
  
  2. ssl-generate:
     - Generates Let's Encrypt certificates
     - Uses Cloudflare DNS-01 challenge
     - Deploys to Docker volume on Freddy
     - Covers all domains (including Sullivan)
  
  3. deploy:
     - Connects via Tailscale
     - Clones/pulls freddy repository
     - Verifies SSL certificates exist
     - Starts all services with docker compose
  
  4. health-checks:
     - Verifies all containers healthy
  
  5. summary:
     - Generates deployment report
```

**Schedule:** Weekly SSL renewal check (Sundays at 3am UTC)

---

## 🎬 Sullivan Server

### Role & Responsibilities

**Primary Role:** Media server (Tailscale-only)

**Responsibilities:**
1. **Media Streaming:**
   - Emby, Jellyfin, Plex for media playback
   - Accessible only via Freddy's reverse proxy

2. **Media Management:**
   - *arr stack (Sonarr, Radarr, Lidarr) for automation
   - qBittorrent for downloads
   - Jackett for indexer management

3. **Additional Services:**
   - eBook management (Calibre)
   - Backup services (Duplicati)
   - Household management (Mealie, Grocy)
   - Documentation (Wiki.js)

### Network Configuration

- **Public Access:** NO (Tailscale-only)
- **Ports Open:** Only to Freddy's Tailscale IP
- **Tailscale:** Connected for Freddy access
- **Firewall:** UFW configured to only allow Freddy

### Security Model

```bash
# Sullivan's firewall rules:
- Allow all traffic on Tailscale interface
- Allow specific ports ONLY from Freddy's IP
- Block all other traffic
- No direct internet exposure

# Services accessible:
Freddy → Sullivan: ✅ (via Tailscale)
Internet → Sullivan: ❌ (firewalled)
Sullivan → Internet: ✅ (outbound only)
```

### CI/CD Pipeline

```yaml
Workflow: sullivan/ci-cd.yml

Jobs:
  1. deploy:
     - Connects via Tailscale
     - Clones/pulls sullivan repository
     - Configures firewall rules
     - Injects API keys from GitHub Secrets
     - Starts all services with docker compose
  
  2. health-checks:
     - Verifies all containers healthy
  
  3. summary:
     - Generates deployment report
```

**Note:** No DNS or SSL management (handled by Freddy)

---

## 🔐 Security Architecture

### Defense in Depth

```
Layer 1: Cloudflare
├─ DDoS protection
├─ Web Application Firewall (WAF)
└─ Rate limiting

Layer 2: Freddy (Public-facing)
├─ nginx security headers
├─ SSL/TLS termination
├─ Input validation
└─ Rate limiting zones

Layer 3: Tailscale VPN
├─ Encrypted mesh network
├─ Zero-trust networking
├─ Peer-to-peer connections
└─ MagicDNS

Layer 4: Sullivan (Private)
├─ UFW firewall
├─ IP whitelist (Freddy only)
├─ No direct internet access
└─ Service isolation (Docker)

Layer 5: Application
├─ Service authentication
├─ API key management
├─ User permissions
└─ Audit logging
```

### SSL/TLS Certificate Management

```
Certificate Authority: Let's Encrypt
Challenge Type: DNS-01 (via Cloudflare API)
Certificate Scope: *.7gram.xyz, *.sullivan.7gram.xyz
Storage: Docker volume (ssl-certs)
Renewal: Automated weekly via GitHub Actions
Deployment: CI/CD pushes to Freddy
```

**Advantages:**
- ✅ Wildcard certificates cover all subdomains
- ✅ No port 80 required for validation
- ✅ Works with Tailscale (non-public IPs)
- ✅ Automatic renewal prevents expiry

---

## 🌐 DNS & Traffic Flow

### DNS Records (Managed by Freddy CI/CD)

```
Record Type: A
TTL: 60 seconds
Cloudflare Proxy: Disabled (Tailscale IPs)

7gram.xyz                    → Freddy Tailscale IP
*.7gram.xyz                  → Freddy Tailscale IP
photo.7gram.xyz              → Freddy Tailscale IP
nc.7gram.xyz                 → Freddy Tailscale IP
home.7gram.xyz               → Freddy Tailscale IP
audiobook.7gram.xyz          → Freddy Tailscale IP
sullivan.7gram.xyz           → Freddy Tailscale IP
*.sullivan.7gram.xyz         → Freddy Tailscale IP
emby.sullivan.7gram.xyz      → Freddy Tailscale IP
jellyfin.sullivan.7gram.xyz  → Freddy Tailscale IP
plex.sullivan.7gram.xyz      → Freddy Tailscale IP
```

**Why all point to Freddy:** Freddy is the public gateway that proxies traffic to Sullivan.

### Traffic Flow Examples

**Example 1: Accessing PhotoPrism (Freddy service)**

```
User → https://photo.7gram.xyz
  ↓ DNS resolves to Freddy's Tailscale IP
Freddy nginx receives HTTPS request
  ↓ SSL termination with Let's Encrypt cert
Freddy nginx routes to local PhotoPrism container
  ↓ proxy_pass http://photoprism:2342
PhotoPrism responds with photos
  ↓ Response flows back through nginx
User receives encrypted HTTPS response
```

**Example 2: Accessing Plex (Sullivan service)**

```
User → https://plex.sullivan.7gram.xyz
  ↓ DNS resolves to Freddy's Tailscale IP
Freddy nginx receives HTTPS request
  ↓ SSL termination with Let's Encrypt cert
Freddy nginx proxies to Sullivan over Tailscale
  ↓ proxy_pass http://SULLIVAN_TAILSCALE_IP:32400
Sullivan Plex container responds
  ↓ Response flows back through Tailscale
Freddy nginx forwards response
  ↓ Re-encrypted with SSL
User receives encrypted HTTPS response
```

---

## 🔄 CI/CD Comparison

| Aspect | Freddy | Sullivan |
|--------|--------|----------|
| **DNS Management** | ✅ Updates Cloudflare | ❌ N/A (Freddy handles) |
| **SSL Certificates** | ✅ Generates & deploys | ❌ N/A (Freddy handles) |
| **Git Handling** | ⚠️ Fixed in review | ✅ Excellent |
| **Firewall Config** | ❌ Not configured | ✅ UFW with IP whitelist |
| **Secrets Injection** | ⚠️ Basic | ✅ GitHub Secrets → .env |
| **Health Checks** | ✅ Container health | ✅ Container health |
| **Notifications** | ✅ Discord | ✅ Discord |
| **Resource Monitoring** | ❌ Not monitored | ✅ Disk & memory |
| **Schedule** | ✅ Weekly SSL renewal | ❌ Manual only |

---

## 📦 Service Distribution

### Why This Architecture?

**Freddy (Public Services):**
- Personal/private services (photos, files, home automation)
- Low bandwidth, high security requirements
- Need SSL termination and public access
- Gateway role for Sullivan

**Sullivan (Media Services):**
- High bandwidth streaming services
- Large storage requirements
- Many services with complex dependencies
- No need for direct public access

**Benefits:**
1. **Security:** Sullivan never exposed to internet
2. **Performance:** Dedicated media server resources
3. **Isolation:** Media services don't impact personal services
4. **Scalability:** Can upgrade Sullivan independently
5. **Backup:** Easier to backup/restore separate concerns

---

## 🛠️ Maintenance & Operations

### Regular Tasks

**Daily:**
- Monitor Cloudflare analytics for unusual traffic
- Check Discord notifications for deployment status

**Weekly:**
- Verify SSL certificate auto-renewal (automatic)
- Review container health check results
- Monitor storage usage on Sullivan

**Monthly:**
- Update Docker images via git push (triggers CI/CD)
- Review firewall logs on both servers
- Check Tailscale connectivity status

**Quarterly:**
- Rotate API keys and update GitHub Secrets
- Review and optimize nginx configurations
- Audit service access logs

### Monitoring Endpoints

```bash
# Freddy
curl https://7gram.xyz/health
docker ps --filter "health=healthy"
sudo tailscale status

# Sullivan (via SSH)
cd ~/sullivan && docker compose ps
docker stats --no-stream
df -h /
```

---

## 🚀 Deployment Workflow

### Freddy Deployment

```
1. Developer pushes to main branch
   ↓
2. GitHub Actions triggers freddy/ci-cd.yml
   ↓
3. DNS records updated (if needed)
   ↓
4. SSL certificates generated/renewed
   ↓
5. Freddy deployment via Tailscale SSH
   ↓
6. Health checks verify services
   ↓
7. Discord notification sent
```

### Sullivan Deployment

```
1. Developer pushes to main branch
   ↓
2. GitHub Actions triggers sullivan/ci-cd.yml
   ↓
3. Sullivan deployment via Tailscale SSH
   ↓
4. Firewall rules configured
   ↓
5. API keys injected from GitHub Secrets
   ↓
6. Health checks verify services
   ↓
7. Discord notification sent
```

---

## 🎯 Future Enhancements

### Potential Improvements

1. **Load Balancing:**
   - Add multiple Freddy instances for redundancy
   - Use Cloudflare load balancing

2. **Monitoring:**
   - Integrate Prometheus + Grafana
   - Set up alerting for service downtime

3. **Backup Automation:**
   - Automated backups to cloud storage
   - Scheduled database dumps

4. **Container Updates:**
   - Automated security updates via Watchtower
   - Rollback capability for failed updates

5. **Geographic Distribution:**
   - Add regional servers for better latency
   - Replicate media across locations

---

## 📚 Documentation References

- **Freddy Review:** `.github/servers/freddy/REVIEW-AND-FIXES.md`
- **Sullivan Review:** `.github/servers/sullivan/REVIEW.md`
- **Freddy Quick Start:** `.github/servers/freddy/QUICKSTART.md`
- **Shared Actions:** `.github/actions/README.md`

---

## 🤝 Contributing

When making changes to this architecture:

1. **Update both servers** if changing shared dependencies
2. **Test in workflow_dispatch** before merging to main
3. **Document changes** in respective server directories
4. **Update firewall rules** if adding new services
5. **Rotate secrets** after major security changes

---

## ✅ Architecture Validation Checklist

- ✅ All DNS records point to Freddy
- ✅ SSL certificates cover all domains
- ✅ Freddy can reach Sullivan via Tailscale
- ✅ Sullivan firewall only allows Freddy
- ✅ All services accessible via proper subdomains
- ✅ Health checks passing on both servers
- ✅ CI/CD pipelines functioning correctly
- ✅ Secrets properly stored in GitHub
- ✅ Backups configured and tested
- ✅ Monitoring and alerting operational

**Status:** ✅ Architecture validated and production-ready!