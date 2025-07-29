# 🧪 Testing Your Updated Workflows

All three integration files have been updated to use your new unified workflow with the requested features!

## 📁 Updated Files Ready for Testing

### 1. **FKS Deploy** (`fks-deploy.yml`)
- **Server**: 8GB RAM (g6-standard-4) - Good for AI workloads
- **Features**: All unified options available
- **Best for**: Testing AI services and complex deployments

### 2. **NGINX Deploy** (`nginx-deploy.yml`)  
- **Server**: 2GB RAM (g6-standard-1) - Lightweight
- **Features**: All unified options available
- **Best for**: Quick testing (smallest resource usage)

### 3. **ATS Deploy** (`ats-deploy.yml`)
- **Server**: 4GB RAM (g6-standard-2) - Medium size
- **Features**: All unified options available  
- **Best for**: Testing game server deployments

## 🎯 Recommended Testing Order

### Start with NGINX (Easiest)
```bash
# 1. Copy to your NGINX repo
cp actions/examples/service-repo-integration/nginx-deploy.yml /path/to/nginx-repo/.github/workflows/deploy.yml

# 2. Test with health-check first (safe)
# Go to Actions tab → Run workflow → Choose "health-check"
```

**Why NGINX first?**
- ✅ Smallest server (cheapest to test)
- ✅ Simple deployment
- ✅ Quick to verify

### Then FKS (More Complex)
```bash
# Copy to your FKS repo  
cp actions/examples/service-repo-integration/fks-deploy.yml /path/to/fks-repo/.github/workflows/deploy.yml
```

### Finally ATS (Game Server)
```bash
# Copy to your ATS repo
cp actions/examples/service-repo-integration/ats-deploy.yml /path/to/ats-repo/.github/workflows/deploy.yml
```

## 🎛️ Testing Your New Options

### Test 1: Quick Code Update (Skip Everything)
```yaml
Action: deploy
Deployment Mode: code-only
Skip Tests: ✅ true
Skip Docker Build: ✅ true
Overwrite Server: ❌ false
```

### Test 2: Smart Building (Only if Changes)
```yaml
Action: deploy  
Deployment Mode: update-only
Skip Tests: ❌ false
Skip Docker Build: ❌ false
Build Docker on Changes: ✅ true  # Only builds if code changed
Overwrite Server: ❌ false
```

### Test 3: Fresh Server
```yaml
Action: deploy
Deployment Mode: full-deploy
Overwrite Server: ✅ true
Confirm Destruction: "DESTROY"  # Required!
```

### Test 4: Safe Cleanup
```yaml
Action: destroy
Destroy Scope: service-only
Confirm Destruction: "DESTROY"
```

## ✅ Pre-Test Checklist

- [ ] Secrets are configured in your standardized actions repo
- [ ] Copy the workflow file to your service repo  
- [ ] Commit and push the new workflow
- [ ] Start with "health-check" action first
- [ ] Monitor the Actions tab for results

## 🚨 Safety Tips

1. **Always test with health-check first**
2. **Use smallest server (NGINX) for initial testing**  
3. **Remember to type "DESTROY" exactly for destruction**
4. **Monitor Linode costs during testing**

Choose NGINX for your first test - it's the safest and quickest way to verify everything works!
