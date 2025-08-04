# Tailscale OAuth Migration - Stage2 Connection Fix

## Issues Identified

Your GitHub Actions workflow was failing to connect to Tailscale in the stage2 systemd process due to several OAuth migration issues:

### 1. **Mixed Authentication Methods**
- Workflow partially migrated from auth keys to OAuth
- Some sections still referenced old `TAILSCALE_AUTH_KEY` environment variable
- Inconsistent API authentication across different cleanup jobs

### 2. **OAuth Error Handling**
- Limited error checking for OAuth token requests
- No retry logic for Tailscale connection attempts
- Poor debugging information when OAuth fails

### 3. **Placeholder Replacement Issues**
- Stage2 script OAuth credentials might not be properly replaced
- No validation that placeholders were successfully substituted

## Fixes Applied

### 1. **Enhanced OAuth Error Handling**
```bash
# Added comprehensive OAuth token request with error checking
OAUTH_RESPONSE=$(curl -s -X POST https://api.tailscale.com/api/v2/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=$TS_OAUTH_CLIENT_ID" \
  -d "client_secret=$TS_OAUTH_SECRET" 2>/dev/null || echo "CURL_FAILED")

# Better error messages and fallback handling
if [[ -z "$OAUTH_TOKEN" || "$OAUTH_TOKEN" == "null" || "$OAUTH_TOKEN" == "empty" ]]; then
  echo "❌ Failed to get OAuth access token"
  echo "🔍 OAuth response: $OAUTH_RESPONSE"
  ERROR_MSG=$(echo "$OAUTH_RESPONSE" | jq -r '.error_description // .error // empty' 2>/dev/null || echo "")
  if [[ -n "$ERROR_MSG" ]]; then
    echo "🔍 OAuth error: $ERROR_MSG"
  fi
  exit 1
fi
```

### 2. **Improved Tailscale Connection**
```bash
# Added connection retries with proper cleanup between attempts
CONNECTION_SUCCESS=false
for attempt in {1..3}; do
  echo "🔗 Tailscale connection attempt $attempt/3..."
  
  if timeout 300 tailscale up --authkey="$AUTH_KEY" --hostname="$SERVICE_NAME" --accept-routes --reset; then
    echo "✅ Tailscale connected successfully on attempt $attempt"
    CONNECTION_SUCCESS=true
    break
  else
    # Logout and reset for clean retry
    tailscale logout 2>/dev/null || true
    sleep 5
  fi
done
```

### 3. **Enhanced Stage2 Debugging**
```bash
# Added comprehensive debugging for systemd service
echo '📋 OAuth credential check in stage2 script:'
grep -E '(TS_OAUTH|PLACEHOLDER)' /usr/local/bin/stage2-post-reboot.sh | head -5 || echo 'No OAuth lines found'

# Manual execution with enhanced logging
timeout 300 bash -x /usr/local/bin/stage2-post-reboot.sh 2>&1 | tee /tmp/stage2_manual_output.log
```

### 4. **Complete OAuth Migration**
- Updated all cleanup sections to use OAuth instead of auth keys
- Fixed environment variable references in destroy jobs
- Consistent API authentication across all workflow sections

## Testing Your OAuth Setup

### 1. **Test OAuth Credentials Locally**
Use the provided test script:
```bash
# Set your environment variables
export TS_OAUTH_CLIENT_ID="your_client_id"
export TS_OAUTH_SECRET="your_client_secret"
export TAILSCALE_TAILNET="your_tailnet_or_leave_empty"

# Run the test script
chmod +x scripts/test-oauth-connection.sh
./scripts/test-oauth-connection.sh
```

### 2. **GitHub Secrets Verification**
Ensure these secrets are set in your repository:
- `TS_OAUTH_CLIENT_ID` - Your Tailscale OAuth client ID
- `TS_OAUTH_SECRET` - Your Tailscale OAuth client secret  
- `TAILSCALE_TAILNET` - Your tailnet name (can be empty for personal accounts)

### 3. **OAuth Client Requirements**
Your Tailscale OAuth client needs these permissions:
- **Devices: Write** - To create auth keys and manage devices
- **Write devices** - To register new devices
- **Write device names** - To set hostname

## Next Steps

1. **Verify Secrets**: Make sure your GitHub repository has the correct OAuth secrets
2. **Test Deployment**: Run a fresh deployment and monitor the stage2 logs
3. **Check Debug Output**: The enhanced logging will show exactly where OAuth fails if issues persist

## Debugging Commands

If issues persist, check these in your server:
```bash
# Check systemd service status
systemctl status stage2-setup.service

# View service logs
journalctl -u stage2-setup.service --no-pager -l

# Check if OAuth credentials were replaced
grep -E "(TS_OAUTH|PLACEHOLDER)" /usr/local/bin/stage2-post-reboot.sh

# Test Tailscale daemon
systemctl status tailscaled
tailscale status
```

## OAuth vs Auth Key Differences

| Method | Pros | Cons |
|--------|------|------|
| **OAuth** | Secure, short-lived tokens, fine-grained permissions | More complex setup, requires API calls |
| **Auth Key** | Simple, direct connection | Long-lived secrets, broader permissions |

The OAuth method is more secure and is the recommended approach for CI/CD environments.
