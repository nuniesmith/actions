# Let's Encrypt Rate Limit Notice

## 🔴 Current Status: Rate Limited

Your domain has hit Let's Encrypt's rate limit:

```
too many certificates (5) already issued for this exact set of identifiers 
in the last 168h0m0s, retry after 2026-02-04 15:12:13 UTC
```

**What this means:**
- You've requested 5 certificates for `7gram.xyz,*.7gram.xyz,*.sullivan.7gram.xyz` in the past week
- Let's Encrypt allows maximum 5 certificates per week for the same domain set
- You must wait until **February 4, 2026 at 15:12 UTC** before requesting more production certificates

---

## ✅ Immediate Solutions

### Option 1: Use Staging Certificates (Testing Only)

Staging certificates work exactly like production but show a warning in browsers. Perfect for testing.

**To use staging certificates:**

1. Go to GitHub Actions → 🏠 Freddy Deploy
2. Click "Run workflow"
3. Enable: ✅ **Use Let's Encrypt staging certificates**
4. Enable: ✅ **Force SSL regeneration**
5. Click "Run workflow"

**Result:**
- Certificates will be issued immediately (no rate limit)
- Browser will show "Not Secure" warning (expected for staging)
- Everything else works normally
- Perfect for testing the deployment process

### Option 2: Use Self-Signed Certificates (Current Fallback)

The workflow automatically falls back to self-signed certificates when Let's Encrypt fails.

**Status:**
- ✅ Self-signed certificates are already being generated
- ✅ HTTPS works (but shows browser warning)
- ⚠️ Browsers show "Not Secure" warning
- ✅ Perfect for internal testing

### Option 3: Wait for Rate Limit Reset

**Wait until:** February 4, 2026 at 15:12 UTC

Then run the workflow normally:
- Uncheck "Use staging certificates"
- Enable "Force SSL regeneration"
- Production Let's Encrypt certificates will be issued

---

## 📊 Understanding Rate Limits

Let's Encrypt has several rate limits to prevent abuse:

| Limit Type | Maximum | Time Window |
|------------|---------|-------------|
| **Certificates per Registered Domain** | 50 | 7 days |
| **Duplicate Certificate** | 5 | 7 days |
| **Failed Validations** | 5 | 1 hour |
| **Accounts per IP** | 10 | 3 hours |

**You hit:** Duplicate Certificate limit (5 certificates for exact same domain set in 7 days)

**Why this happened:**
- Multiple test runs with `force_ssl_regen` enabled
- Each test requested a new certificate from Let's Encrypt
- Testing deployment process triggered multiple certificate requests

---

## 🛡️ Prevention Strategies

### 1. Use Staging for Testing

**Always use staging certificates when testing:**

```yaml
# In workflow inputs
use_staging_certs: true  # For testing
use_staging_certs: false # For production only
```

**Benefits:**
- Unlimited requests
- Tests the entire certificate generation process
- No rate limit impact
- Identical to production (except trust)

### 2. Check Before Regenerating

Only use `force_ssl_regen` when necessary:

- ✅ Migrating from Docker volume to host path
- ✅ Certificates are corrupted
- ✅ Changing domain configuration
- ❌ Regular deployments (certificates auto-renew)
- ❌ Testing workflow changes (use staging)

### 3. Use Existing Certificates

The workflow checks for existing certificates before requesting new ones:

```bash
# On Freddy server
sudo ls -la /etc/letsencrypt/live/7gram.xyz/

# If certificates exist and are valid, workflow uses them
# No need to force regeneration
```

### 4. Monitor Certificate Expiry

Certificates expire after 90 days. The workflow includes automatic renewal:

```yaml
# Runs weekly to renew certificates
schedule:
  - cron: '0 2 * * 0'  # Every Sunday at 2 AM
```

This only requests new certificates if existing ones expire in < 30 days.

---

## 🔧 Current Workflow Status

### What's Working:
- ✅ Certificate generation (staging or self-signed)
- ✅ Certificate deployment to `/etc/letsencrypt`
- ✅ Nginx configuration
- ✅ HTTPS enabled
- ✅ Automatic deployment via CI/CD

### What's Limited:
- ❌ Production Let's Encrypt certificates (rate limited until Feb 4)
- ⚠️ Browser shows warning (using self-signed or staging)

---

## 📋 Recommended Actions

### For Immediate Testing:

1. **Enable staging certificates:**
   ```
   GitHub Actions → Freddy Deploy
   ✅ Use staging certificates
   ✅ Force SSL regeneration
   ```

2. **Verify deployment works:**
   ```bash
   ssh actions@freddy
   sudo ls -la /etc/letsencrypt/live/7gram.xyz/
   # Should show cert files
   ```

3. **Test in browser:**
   - Visit https://7gram.xyz
   - Click through warning (expected for staging)
   - Verify site works

### For Production:

1. **Wait until:** February 4, 2026 15:12 UTC

2. **Then run with production certs:**
   ```
   GitHub Actions → Freddy Deploy
   ⬜ Use staging certificates (UNCHECKED)
   ✅ Force SSL regeneration (CHECKED)
   ```

3. **Verify production cert:**
   ```bash
   openssl s_client -connect 7gram.xyz:443 -servername 7gram.xyz < /dev/null 2>&1 | grep issuer
   # Should show: O=Let's Encrypt (not STAGING)
   ```

---

## 🆘 If You Need Production Certs NOW

### Option A: Request Fewer Domains

Instead of requesting all domains at once, request them separately:

**Current (rate limited):**
- `7gram.xyz,*.7gram.xyz,*.sullivan.7gram.xyz`

**Split into separate certificates:**
1. `7gram.xyz`
2. `*.7gram.xyz`
3. `*.sullivan.7gram.xyz`

Each is a different "set of identifiers" with separate rate limits.

**How to do this:**
Modify `ci-cd.yml`:
```yaml
# Request only main domain
domain: 7gram.xyz
additional-domains: ""  # Empty - no wildcards
```

Run workflow, then update to:
```yaml
# Request wildcard
domain: "*.7gram.xyz"
additional-domains: ""
```

### Option B: Use DNS CAA Records

Add CAA records to increase rate limit (from 5 to 50 per week):

1. Go to Cloudflare DNS settings
2. Add CAA record:
   ```
   Type: CAA
   Name: @
   Tag: issue
   Value: letsencrypt.org
   ```

This won't help immediately but increases future limits.

---

## 📖 Additional Resources

- **Let's Encrypt Rate Limits:** https://letsencrypt.org/docs/rate-limits/
- **Staging Environment:** https://letsencrypt.org/docs/staging-environment/
- **Best Practices:** https://letsencrypt.org/docs/integration-guide/

---

## ✅ Summary

**Current Status:**
- ⏳ Rate limited until Feb 4, 2026 15:12 UTC
- ✅ Workflow working with self-signed certificates
- ✅ Deployment process fixed and tested

**Recommended Next Steps:**
1. Use staging certificates for any testing
2. Wait for rate limit reset for production certs
3. Never use `force_ssl_regen` with production certs for testing
4. Set up automatic renewal (already configured)

**When Rate Limit Resets:**
- Run workflow with production certs (uncheck staging)
- Browser will show valid Let's Encrypt certificate
- No more warnings
- Automatic renewal every 60 days

---

**Last Updated:** February 3, 2025  
**Rate Limit Resets:** February 4, 2026 15:12 UTC  
**Status:** Awaiting rate limit reset or using staging/self-signed certificates