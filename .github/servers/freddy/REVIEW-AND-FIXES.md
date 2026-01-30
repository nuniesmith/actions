# 🔍 Freddy CI/CD Review & Fixes

## Critical Issues Found

### 1. ❌ Git Clone/Pull Logic Issue

**Problem:** The pre-deploy-command tries to `cd ${{ env.PROJECT_PATH }}` before verifying the directory exists.

```yaml
# Current (BROKEN):
cd ${{ env.PROJECT_PATH }}  # Fails if ~/freddy doesn't exist yet!
if git status >/dev/null 2>&1; then
  # update repo
else
  # clone repo - but we're already in a non-existent dir!
fi
```

**Fix:** Check if directory exists first, create it if needed:

```bash
# Create project directory if it doesn't exist
mkdir -p ${{ env.PROJECT_PATH }}
cd ${{ env.PROJECT_PATH }}

# Check if it's a git repository
if [ -d .git ] && git status >/dev/null 2>&1; then
  echo "📥 Updating existing repository..."
  git fetch origin
  git checkout ${{ github.ref_name }}
  git pull origin ${{ github.ref_name }}
else
  echo "📥 Cloning repository (first deployment)..."
  cd ..
  rm -rf ${{ env.PROJECT_PATH }}
  git clone https://github.com/${{ github.repository }}.git ${{ env.PROJECT_PATH }}
  cd ${{ env.PROJECT_PATH }}
  git checkout ${{ github.ref_name }}
fi
```

### 2. ❌ SSL Certificate Path Mismatch

**Problem:** Multiple SSL paths causing confusion:
- Environment: `/opt/ssl/7gram.xyz` (host filesystem)
- Pre-deploy checks: `/opt/ssl/7gram.xyz` (host filesystem)
- ssl-certbot-cloudflare action: Deploys to Docker volume `ssl-certs`
- Nginx needs: SSL certs inside container

**Current Flow (BROKEN):**
```
1. Check /opt/ssl/7gram.xyz (host) ❌
2. Run scripts/letsencrypt.sh (doesn't exist in actions repo) ❌
3. Nginx container tries to read certs... but where are they? ❌
```

**Fix:** Use Docker volumes consistently:

```yaml
# In ci-cd.yml env:
SSL_DOCKER_VOLUME: ssl-certs
DOMAIN: 7gram.xyz
```

### 3. ❌ Missing SSL Certificate Generation

**Problem:** The ci-cd.yml doesn't call the `ssl-certbot-cloudflare` action! It references a non-existent `scripts/letsencrypt.sh` file.

**Fix:** Add SSL certificate generation job before deployment.

### 4. ❌ Nginx Can't Access SSL Certs

**Problem:** Nginx container needs to mount the Docker volume where SSL certs are stored.

**Fix:** Ensure nginx mounts the `ssl-certs` Docker volume.

---

## 📋 Complete Fixed CI/CD Workflow

Here's the updated `ci-cd.yml` with all fixes:

### Key Changes:
1. ✅ Added `ssl-generate` job to generate/renew certificates
2. ✅ Fixed git clone/pull logic
3. ✅ Use Docker volumes for SSL certs consistently
4. ✅ Proper dependency chain: DNS → SSL → Deploy
5. ✅ SSL certs generated BEFORE deployment

### Add This New Job (After dns-update, Before deploy):

```yaml
  # ==========================================================================
  # SSL CERTIFICATE GENERATION
  # ==========================================================================
  ssl-generate:
      name: 🔐 Generate/Renew SSL Certificates
      runs-on: ubuntu-latest
      timeout-minutes: 15
      needs: [dns-update]
      # Run if: not skipping deploy, and (manual trigger OR scheduled OR DNS was updated)
      if: |
          inputs.skip_deploy != true && (
            github.event_name == 'schedule' ||
            github.event_name == 'workflow_dispatch' ||
            needs.dns-update.outputs.dns-updated == 'true'
          )
      
      outputs:
          cert-ready: ${{ steps.certbot.outputs.cert-ready }}
          cert-type: ${{ steps.certbot.outputs.cert-type }}
      
      steps:
          - name: 📥 Checkout code
            uses: actions/checkout@v4

          - name: 🔌 Connect to Tailscale
            id: tailscale
            uses: nuniesmith/actions/.github/actions/tailscale-connect@main
            with:
                oauth-client-id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
                oauth-secret: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
                target-ip: ${{ secrets.FREDDY_TAILSCALE_IP }}
                target-ssh-port: ${{ secrets.SSH_PORT || '22' }}

          - name: 🔐 Generate SSL Certificates (Let's Encrypt + Cloudflare DNS)
            id: certbot
            uses: nuniesmith/actions/.github/actions/ssl-certbot-cloudflare@main
            with:
                domain: ${{ env.DOMAIN }}
                additional-domains: "*.7gram.xyz,nc.7gram.xyz,photo.7gram.xyz,home.7gram.xyz,audiobook.7gram.xyz,sullivan.7gram.xyz,*.sullivan.7gram.xyz"
                cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
                email: ${{ secrets.SSL_EMAIL }}
                propagation-seconds: 60
                staging: false
                fallback-to-self-signed: true
                deploy-to-server: true
                ssh-host: ${{ secrets.FREDDY_TAILSCALE_IP }}
                ssh-port: ${{ secrets.SSH_PORT || '22' }}
                ssh-user: ${{ secrets.SSH_USER || 'actions' }}
                ssh-key: ${{ secrets.SSH_KEY }}
                docker-volume-name: ssl-certs
                docker-username: ${{ secrets.DOCKER_USERNAME }}
                docker-token: ${{ secrets.DOCKER_TOKEN }}

          - name: 📋 SSL Summary
            run: |
                echo "## 🔐 SSL Certificates" >> $GITHUB_STEP_SUMMARY
                echo "" >> $GITHUB_STEP_SUMMARY
                echo "| Property | Value |" >> $GITHUB_STEP_SUMMARY
                echo "|----------|-------|" >> $GITHUB_STEP_SUMMARY
                echo "| Domain | \`${{ env.DOMAIN }}\` |" >> $GITHUB_STEP_SUMMARY
                echo "| Status | ${{ steps.certbot.outputs.cert-ready == 'true' && '✅ Ready' || '❌ Failed' }} |" >> $GITHUB_STEP_SUMMARY
                echo "| Type | \`${{ steps.certbot.outputs.cert-type }}\` |" >> $GITHUB_STEP_SUMMARY
                echo "| Expires | ${{ steps.certbot.outputs.expiry-date }} |" >> $GITHUB_STEP_SUMMARY
```

### Update the Deploy Job:

Change the `needs` line to include SSL:

```yaml
  deploy:
      name: 🚀 Deploy to Freddy
      runs-on: ubuntu-latest
      timeout-minutes: 30
      needs: [dns-update, ssl-generate]  # ← Add ssl-generate here
      if: |
          inputs.skip_deploy != true && (
            github.event_name == 'push' ||
            github.event_name == 'pull_request' ||
            github.event_name == 'workflow_dispatch' ||
            needs.ssl-generate.outputs.cert-ready == 'true'
          )
```

### Fix the Pre-Deploy-Command:

Replace lines 201-248 with:

```yaml
                  pre-deploy-command: |
                      echo "🏠 Deploying to Freddy server..."

                      # Create project directory if it doesn't exist
                      echo "📁 Ensuring project directory exists..."
                      mkdir -p ${{ env.PROJECT_PATH }}
                      
                      # Stop existing services to release file locks
                      echo "🛑 Stopping existing services..."
                      if [ -d "${{ env.PROJECT_PATH }}" ]; then
                        cd ${{ env.PROJECT_PATH }}
                        ./run.sh stop 2>/dev/null || docker compose down 2>/dev/null || true
                        cd ~
                      fi

                      # Handle git repository setup
                      cd ${{ env.PROJECT_PATH }}
                      
                      if [ -d .git ] && git status >/dev/null 2>&1; then
                        echo "📥 Updating existing repository..."
                        git fetch origin
                        git checkout ${{ github.ref_name }}
                        git pull origin ${{ github.ref_name }} || {
                          echo "⚠️ Git pull failed, doing hard reset..."
                          git reset --hard origin/${{ github.ref_name }}
                        }
                      else
                        echo "📥 Cloning repository (first deployment)..."
                        cd ~
                        rm -rf ${{ env.PROJECT_PATH }}
                        git clone https://github.com/${{ github.repository }}.git ${{ env.PROJECT_PATH }}
                        cd ${{ env.PROJECT_PATH }}
                        git checkout ${{ github.ref_name }}
                      fi

                      # Ensure run.sh is executable
                      chmod +x ./run.sh 2>/dev/null || true

                      # Check SSL certificates in Docker volume
                      echo "🔍 Checking SSL certs in Docker volume..."
                      CERT_EXISTS=$(docker run --rm -v ssl-certs:/certs:ro busybox:latest test -f /certs/live/${{ env.DOMAIN }}/fullchain.pem && echo "yes" || echo "no")
                      
                      if [ "$CERT_EXISTS" = "yes" ]; then
                        echo "✅ SSL certificates found in Docker volume"
                        docker run --rm -v ssl-certs:/certs:ro busybox:latest ls -lah /certs/live/${{ env.DOMAIN }}/
                      else
                        echo "⚠️ SSL certificates not found in Docker volume"
                        echo "   They should have been generated in the ssl-generate job"
                      fi

                      # Load environment variables
                      if [ -f .env ]; then
                        set -a && source .env && set +a
                        echo "✓ Environment loaded"
                      fi
```

---

## 🐳 Nginx Docker Configuration

### Option 1: Docker Compose with Volume Mount (Recommended)

In your `docker-compose.yml` on Freddy server:

```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      # SSL certificates from Docker volume
      - ssl-certs:/etc/letsencrypt:ro
      # Nginx configuration
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  ssl-certs:
    external: true  # Created by ssl-certbot-cloudflare action
```

### Option 2: Custom Nginx Dockerfile (If you need to bake certs in)

**Note:** This is NOT recommended for SSL certs (they expire!). Use volume mounts instead.

If you still want a custom Dockerfile for other nginx customizations:

```dockerfile
# nginx/Dockerfile
FROM nginx:alpine

# Install openssl for SSL testing
RUN apk add --no-cache openssl

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY conf.d/ /etc/nginx/conf.d/

# Health check script
RUN echo '#!/bin/sh' > /healthcheck.sh && \
    echo 'wget -q --spider http://localhost/health || exit 1' >> /healthcheck.sh && \
    chmod +x /healthcheck.sh

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD ["/healthcheck.sh"]

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
```

Then in `docker-compose.yml`:

```yaml
services:
  nginx:
    build:
      context: ./nginx
      dockerfile: Dockerfile
    container_name: nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ssl-certs:/etc/letsencrypt:ro  # Still mount certs as volume!
    restart: unless-stopped
```

---

## 📝 Nginx Configuration for SSL

Create `nginx/conf.d/ssl.conf`:

```nginx
# SSL configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;

# Certificates (from Docker volume)
ssl_certificate /etc/letsencrypt/live/7gram.xyz/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/7gram.xyz/privkey.pem;
```

Create `nginx/conf.d/7gram.xyz.conf`:

```nginx
# HTTP to HTTPS redirect
server {
    listen 80;
    server_name 7gram.xyz *.7gram.xyz;
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    location / {
        return 301 https://$host$request_uri;
    }
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    server_name 7gram.xyz;
    
    include /etc/nginx/conf.d/ssl.conf;
    
    # Your application config
    location / {
        proxy_pass http://your-app:port;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}

# Photoprism
server {
    listen 443 ssl http2;
    server_name photo.7gram.xyz;
    
    include /etc/nginx/conf.d/ssl.conf;
    
    location / {
        proxy_pass http://photoprism:2342;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Nextcloud
server {
    listen 443 ssl http2;
    server_name nc.7gram.xyz;
    
    include /etc/nginx/conf.d/ssl.conf;
    
    client_max_body_size 512M;
    
    location / {
        proxy_pass http://nextcloud:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Home Assistant
server {
    listen 443 ssl http2;
    server_name home.7gram.xyz;
    
    include /etc/nginx/conf.d/ssl.conf;
    
    location / {
        proxy_pass http://homeassistant:8123;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for Home Assistant
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Audiobookshelf
server {
    listen 443 ssl http2;
    server_name audiobook.7gram.xyz;
    
    include /etc/nginx/conf.d/ssl.conf;
    
    location / {
        proxy_pass http://audiobookshelf:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## 🔧 Debugging Nginx 500 Errors

### Check SSL Certificates Inside Container:

```bash
# On Freddy server:
docker exec -it nginx sh

# Inside container:
ls -la /etc/letsencrypt/live/7gram.xyz/
cat /etc/letsencrypt/live/7gram.xyz/fullchain.pem | head -5
openssl x509 -in /etc/letsencrypt/live/7gram.xyz/fullchain.pem -noout -text
```

### Check Nginx Error Logs:

```bash
docker logs nginx --tail 100
docker exec -it nginx cat /var/log/nginx/error.log
```

### Test Nginx Configuration:

```bash
docker exec -it nginx nginx -t
```

### Common 500 Error Causes:

1. **SSL cert file not found**: Volume not mounted correctly
2. **Permission issues**: Cert files not readable
3. **Upstream backend down**: photoprism, nextcloud, etc. not running
4. **Nginx config syntax error**: Test with `nginx -t`
5. **Port conflicts**: Another service using 80/443

### Verify Docker Volume:

```bash
# Check if ssl-certs volume exists
docker volume ls | grep ssl-certs

# Inspect volume
docker volume inspect ssl-certs

# Check contents
docker run --rm -v ssl-certs:/certs:ro busybox:latest ls -lah /certs/live/7gram.xyz/
```

---

## 📋 Summary of Changes Needed

1. **Update ci-cd.yml**:
   - ✅ Add `ssl-generate` job
   - ✅ Fix git clone/pull logic in pre-deploy-command
   - ✅ Update deploy job to depend on ssl-generate
   - ✅ Change SSL checks to use Docker volume

2. **On Freddy Server**:
   - ✅ Ensure `docker-compose.yml` mounts `ssl-certs` volume to nginx
   - ✅ Update nginx config to reference `/etc/letsencrypt/live/7gram.xyz/`
   - ✅ Create health check endpoint at `/health`

3. **GitHub Secrets** (verify these exist):
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ZONE_ID`
   - `SSL_EMAIL`
   - `FREDDY_TAILSCALE_IP`
   - `SSH_USER`
   - `SSH_KEY`
   - `SSH_PORT`
   - `TAILSCALE_OAUTH_CLIENT_ID`
   - `TAILSCALE_OAUTH_SECRET`
   - `DOCKER_USERNAME`
   - `DOCKER_TOKEN`

---

## 🚀 Testing the Fix

1. **Trigger workflow manually**: Go to Actions → Freddy Deploy → Run workflow
2. **Check SSL job**: Should generate/deploy certificates
3. **Check deploy job**: Should pull/clone repo correctly
4. **Verify nginx**: Should start with SSL certificates mounted
5. **Test HTTPS**: Visit https://7gram.xyz (should work!)

---

## 📞 Need Help?

If you're still seeing 500 errors after these fixes:

1. Check nginx logs: `docker logs nginx`
2. Verify SSL certs in volume: `docker run --rm -v ssl-certs:/certs:ro busybox ls -la /certs/live/`
3. Test nginx config: `docker exec nginx nginx -t`
4. Check backend services: `docker compose ps`
