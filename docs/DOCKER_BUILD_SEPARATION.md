# FKS Docker Build Separation Implementation

## Overview
Separated Docker image building from server deployment to optimize the workflow. Docker images are now built once and can be used across multiple server deployments.

## New Workflow Structure

### 🐳 **Docker Build Job (build-docker-images)**
**Purpose**: Build all FKS service images independently
**Runs**: When `action_type` is 'deploy' and `skip_docker_build` is not true
**Output**: Tagged Docker images ready for deployment

#### **Images Built:**
- `fks-auth:latest` - Authentication service
- `fks-api:latest` - API service 
- `fks-web:latest` - React web frontend
- `fks-worker:latest` - Background worker service
- `fks-data:latest` - Data processing service

#### **Features:**
- **Smart Building**: Detects code changes and only builds when necessary
- **Consistent Tagging**: Uses branch name + git SHA for reliable versioning
- **Multi-Service Support**: Builds all services with appropriate configurations
- **Docker Hub Integration**: Pushes to your Docker registry for reuse

### 🚀 **Server Deployment Jobs**
**Purpose**: Deploy physical servers and pull pre-built images
**Dependencies**: Each depends on `build-docker-images` job completion

#### **Modified Deployment Flow:**
1. **build-docker-images** ➜ Builds all Docker images
2. **deploy-fks-auth** ➜ Creates auth server, pulls pre-built images
3. **deploy-fks-api** ➜ Creates API server, pulls pre-built images  
4. **deploy-fks-web** ➜ Creates web server, pulls pre-built images
5. **deployment-summary** ➜ Updates DNS and shows summary

## Benefits

### ⚡ **Performance Improvements**
- **Parallel Building**: All images build simultaneously instead of per-server
- **Build Once, Deploy Many**: Images can be reused across multiple servers
- **Faster Deployments**: Servers just pull pre-built images instead of building

### 🔄 **Workflow Efficiency**
- **Independent Concerns**: Building and deployment are separate responsibilities
- **Reusable Artifacts**: Built images can be used for testing, staging, production
- **Selective Building**: Only builds when code actually changes

### 🛠️ **Maintenance Benefits**
- **Cleaner Logs**: Build logs separate from deployment logs
- **Better Debugging**: Easier to identify build vs deployment issues
- **Resource Optimization**: GitHub Actions runners used more efficiently

## Configuration Changes

### **Deployment Jobs Updated:**
```yaml
with:
  skip_docker_build: true          # Skip building in deployment
  build_docker_on_changes: false  # Not needed anymore
```

### **Dependencies Updated:**
```yaml
needs: [build-docker-images, previous-job]  # Wait for images + previous server
```

### **Conditional Logic:**
- Build job only runs for 'deploy' actions
- Deployment jobs proceed even if build is skipped (reuse existing images)
- DNS updates only run if at least one deployment succeeds

## Image Versioning Strategy

### **Tags Generated:**
- **Versioned**: `fks-auth:main-a1b2c3d4` (branch + 8-char SHA)
- **Latest**: `fks-auth:latest` (always points to newest)

### **Advantages:**
- **Reproducible Deployments**: Exact image versions are trackable
- **Rollback Capability**: Can deploy specific versions if needed
- **Development Support**: Different branches get different tags

## Environment Variables

### **Build-Time Variables:**
- `SERVICE_TYPE`: Configures which service to build (auth, api, web, worker, data)
- `SERVICE_PORT`: Sets the service port
- `BUILD_ENV`: Set to 'production' for optimized builds
- `NODE_VERSION`: Node.js version for web service (20)

### **Runtime Variables:**
- All existing environment variables still work
- Docker images are pre-configured but can be overridden at runtime

## Usage

### **Normal Deployment** (builds images + deploys):
```bash
# Workflow will build images first, then deploy servers
gh workflow run fks-deploy.yml --ref main -f action_type=deploy
```

### **Skip Docker Build** (use existing images):
```bash
# Skip building, use existing latest images
gh workflow run fks-deploy.yml --ref main -f action_type=deploy -f skip_docker_build=true
```

### **Infrastructure Only** (servers without new images):
```bash
# Deploy infrastructure but skip building new images
gh workflow run fks-deploy.yml --ref main -f action_type=deploy -f skip_docker_build=true
```

## Next Steps

1. **Test the new workflow** with a deployment
2. **Verify images** are built and pushed to Docker Hub
3. **Check server deployments** pull the correct images
4. **Monitor performance** improvements in build/deploy times

This separation makes the workflow more modular, efficient, and easier to maintain while supporting your multi-service architecture on dedicated servers!
