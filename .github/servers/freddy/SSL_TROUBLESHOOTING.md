# SSL Certificate Troubleshooting Guide

## Current Issue: Certificate/Key Mismatch

### Problem Description

The nginx container is failing to start due to a mismatch between the SSL certificate and private key:

```
[ERROR] Certificate and private key do not match!
[DEBUG] Certificate modulus: MD5(stdin)= baf59ff7f5b05fde6799439b6f31a290
[DEBUG] Private key modulus: MD5(stdin)= d41d8cd98f00b204e9800998ecf8427e
```

The private key modulus `d41d8cd98f00b204e9800998ecf8427e` is the MD5 hash of an **empty string**, indicating the `privkey.pem` file is corrupted or empty.

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

## Solution: Force SSL Regeneration

### Quick Fix (Recommended)

Use the GitHub Actions workflow to regenerate certificates:

1. Go to: **Actions** → **🏠 Freddy Deploy** → **Run workflow**
2. Enable the option: **"Force SSL certificate regeneration (fixes corrupted certs)"**
3. Click **"Run workflow"**

This will:
- Stop the nginx container
- Remove the corrupted `ssl-certs` volume
- Generate fresh Let's Encrypt certificates
- Deploy the new certificates
- Restart all services

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

## Prevention

### Automated Renewal

The workflow runs weekly (Sundays at 3am UTC) to check and renew certificates automatically.

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

**Cause:** Mismatched cert/key pair  
**Fix:** Use `force_ssl_regen` workflow option

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
- Increase `propagation-seconds` in workflow (currently 60s)
- Check Cloudflare API token has DNS edit permissions

### Issue: Nginx won't start after cert regeneration

**Cause:** Old nginx container holding stale volume mount  
**Fix:**
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

**Last Updated:** 2025-01-29  
**Status:** Active troubleshooting for corrupted privkey.pem issue