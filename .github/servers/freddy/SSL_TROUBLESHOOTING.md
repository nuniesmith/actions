# SSL Certificate Troubleshooting Guide

## Overview

This guide helps diagnose and fix SSL certificate issues on the Freddy server. The CI/CD workflow is **fully automated** and handles certificate cleaning, generation, verification, and deployment.

## Common Issue: Certificate/Key Mismatch

### Problem Description

The nginx container is failing to start due to a mismatch between the SSL certificate and private key:

```
[ERROR] Certificate and private key do not match!
[DEBUG] Certificate modulus: MD5(stdin)= baf59ff7f5b05fde6799439b6f31a290
[DEBUG] Private key modulus: MD5(stdin)= d41d8cd98f00b204e9800998ecf8427e
```

The private key modulus `d41d8cd98f00b204e9800998ecf8427e` is the MD5 hash of an **empty string**, indicating the `privkey.pem` file is corrupted or empty (typically ~241 bytes instead of the expected ~1.7KB).

### Root Cause

The SSL certificate files in the `ssl-certs` Docker volume are corrupted:
- `fullchain.pem` - Valid certificate (2.8K)
- `privkey.pem` - **Corrupted/empty** (241 bytes but effectively empty)

This typically happens when:
1. Certificate generation was interrupted
2. Files were manually edited/corrupted
3. Disk I/O errors during write
4. Permission issues during certificate deployment

---

## Solution: Automated SSL Regeneration

### Quick Fix (Recommended) ⭐

The GitHub Actions workflow is **fully automated** and handles everything:

1. Go to: **Actions** → **🏠 Freddy Deploy** → **Run workflow**
2. Enable the option: **"Force SSL certificate regeneration (fixes corrupted certs)"**
3. Click **"Run workflow"**

**The workflow automatically:**

1. **🧹 Comprehensive Cleanup**
   - Stops all Docker services
   - Removes nginx container completely
   - Removes corrupted `ssl-certs` Docker volume
   - Cleans host certificate directories (`/opt/ssl`, `/etc/letsencrypt`)
   - Prunes dangling volumes and containers

2. **🔍 Pre-Generation Verification**
   - Verifies ssl-certs volume is removed
   - Ensures nginx container is gone
   - Confirms clean slate before generation

3. **🔐 Certificate Generation**
   - Uses Let's Encrypt with Cloudflare DNS-01 challenge
   - Generates wildcard certificates for all domains
   - Falls back to self-signed if Let's Encrypt fails
   - Deploys directly to `ssl-certs` Docker volume

4. **✅ Post-Generation Verification**
   - Confirms certificate files exist in volume
   - **Computes and compares certificate vs private key modulus**
   - Validates certificate/key pair match
   - Checks certificate validity and expiration date
   - **FAILS the deployment if verification fails**

5. **🚀 Deployment**
   - Only deploys if certificates are verified
   - Starts all services with fresh certificates
   - Runs health checks on all containers

### Manual Fix (If workflow fails)

SSH into Freddy and run:

```bash
# Stop nginx to release the volume
docker stop nginx
docker rm nginx

# Remove corrupted volume
docker volume rm ssl-certs

# Recreate with fresh certificates
cd ~/freddy
docker compose down
docker compose up -d
```

The nginx container will automatically request new certificates on startup.

---

## Verification

After regeneration, verify the certificates match:

```bash
# SSH into Freddy
ssh actions@freddy

# Check certificate and key match
docker exec nginx sh -c '
  CERT_MOD=$(openssl x509 -noout -modulus -in /etc/nginx/ssl/fullchain.pem | openssl md5)
  KEY_MOD=$(openssl rsa -noout -modulus -in /etc/nginx/ssl/privkey.pem | openssl md5)
  echo "Certificate: $CERT_MOD"
  echo "Private Key: $KEY_MOD"
  [ "$CERT_MOD" = "$KEY_MOD" ] && echo "✅ MATCH" || echo "❌ MISMATCH"
'
```

Expected output:
```
Certificate: MD5(stdin)= <hash>
Private Key: MD5(stdin)= <hash>
✅ MATCH
```

---

## Prevention & Monitoring

### Automated Certificate Renewal

The workflow includes:
- **Weekly scheduled runs** (Sundays at 3am UTC) for automatic renewal
- **Pre-deployment verification** ensures certificates are valid before deploying
- **Post-deployment health checks** confirm nginx starts successfully
- **Automatic fallback** to self-signed certificates if Let's Encrypt fails

### Monitoring

Check certificate status:

```bash
# View certificate expiry
docker exec nginx openssl x509 -in /etc/nginx/ssl/fullchain.pem -noout -dates

# Check certificate issuer
docker exec nginx openssl x509 -in /etc/nginx/ssl/fullchain.pem -noout -issuer

# View nginx logs for certificate issues
docker logs nginx
```

---

## Troubleshooting Common Issues

### Issue: "Certificate verification failed"

**Cause:** Mismatched cert/key pair or corrupted files  
**Fix:** 
1. Use `force_ssl_regen` workflow option (recommended)
2. The workflow will automatically clean, regenerate, and verify certificates
3. If verification fails again, check the workflow logs for specific errors

### Issue: "Rate limit exceeded" from Let's Encrypt

**Cause:** Too many certificate requests  
**Fix:** 
- Wait 1 hour (Let's Encrypt has rate limits)
- Use staging mode temporarily:
  - Edit `ci-cd.yml` line ~192: `staging: true`
  - Generate staging cert
  - Test deployment
  - Switch back to `staging: false`

### Issue: "DNS validation failed"

**Cause:** Cloudflare DNS records not propagating  
**Fix:**
- Verify DNS records at: https://www.whatsmydns.net/
- The workflow uses 60s propagation delay (configurable in `ci-cd.yml` line 340)
- Check Cloudflare API token has DNS edit permissions in Cloudflare dashboard

### Issue: Nginx won't start after cert regeneration

**Cause:** Old nginx container holding stale volume mount  
**Fix:**
- **Automatic:** The workflow's pre-deploy cleanup handles this
- **Manual (if needed):**
```bash
docker stop nginx && docker rm nginx
docker volume rm ssl-certs
cd ~/freddy && docker compose up -d nginx
```

---

## Certificate Details

- **Domain:** `7gram.xyz`
- **Additional Domains:**
  - `*.7gram.xyz`
  - `nc.7gram.xyz`
  - `photo.7gram.xyz`
  - `home.7gram.xyz`
  - `audiobook.7gram.xyz`
  - `sullivan.7gram.xyz`
  - `*.sullivan.7gram.xyz`

- **Issuer:** Let's Encrypt (Production CA: E7)
- **Validity:** 90 days
- **Renewal:** Automated weekly checks
- **Storage:** Docker volume `ssl-certs`
- **Mount Path:** `/etc/nginx/ssl/`

---

## Related Files

- Workflow: `.github/servers/freddy/ci-cd.yml`
- SSL Action: `.github/actions/ssl-certbot-cloudflare/`
- Nginx Config: `servers/freddy/nginx/` (in freddy repo)
- Docker Compose: `servers/freddy/docker-compose.yml` (in freddy repo)

---

## Support

If issues persist after following this guide:

1. Check GitHub Actions logs: [Actions Tab](https://github.com/nuniesmith/actions/actions)
2. Review nginx container logs: `docker logs nginx`
3. Verify Cloudflare DNS: Check DNS records are pointing to Freddy's Tailscale IP
4. Check secrets: Ensure all GitHub secrets are configured correctly

---

## Workflow Configuration

The CI/CD pipeline (`ci-cd.yml`) includes three SSL-related jobs:

1. **dns-update**: Updates Cloudflare DNS records
2. **ssl-generate**: Cleans, generates, and verifies certificates
3. **deploy**: Deploys with verified certificates and runs health checks

All jobs use shared actions from `.github/actions/`:
- `cloudflare-dns-update@main`
- `ssl-certbot-cloudflare@main`
- `tailscale-connect@main`
- `ssh-deploy@main`
- `health-check@main`

---

## Summary

✅ **The workflow is fully automated** - just trigger it with `force_ssl_regen` enabled  
✅ **Automatic cleanup** - removes all corrupted certificates and volumes  
✅ **Automatic verification** - ensures cert/key match before deployment  
✅ **Automatic fallback** - uses self-signed certificates if Let's Encrypt fails  
✅ **Weekly renewals** - scheduled automatic certificate renewal checks  

**For 99% of SSL issues: Just run the workflow with `force_ssl_regen` enabled!**

---

**Last Updated:** 2026-01-30  
**Status:** ✅ Workflow fully configured with comprehensive cleanup and verification