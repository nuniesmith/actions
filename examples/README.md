# Example: Using the Standardized Actions in Your Project

This directory contains examples of how to integrate the standardized deployment actions into your own project repositories.

## 🎯 Integration Methods

### 1. Reusable Workflow (Recommended)
Reference the standardized workflow from your project:

```yaml
# .github/workflows/deploy.yml in your project repository
name: Deploy My Service
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    uses: your-org/actions/.github/workflows/deploy-service.yml@main
    with:
      service_name: my-service
      deployment_mode: full-deploy
      server_type: g6-standard-2
      target_region: ca-central
    secrets: inherit
```

### 2. Direct Action Calls
Call specific scripts from the actions repository:

```yaml
# .github/workflows/custom-deploy.yml
name: Custom Deployment
on: [workflow_dispatch]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Actions Repository
        uses: actions/checkout@v4
        with:
          repository: your-org/actions
          path: ./.actions
      
      - name: Run Custom Deployment
        run: |
          chmod +x ./.actions/scripts/linode/server-manager.sh
          ./.actions/scripts/linode/server-manager.sh create --service my-service
```

### 3. Fork and Customize
Fork the actions repository and customize for your specific needs.

## 📁 Example Files

Each example includes:
- **Workflow file** - GitHub Actions configuration
- **Service config** - Service-specific settings
- **Documentation** - Setup and usage instructions

## 🚀 Quick Start

1. **Choose your integration method** (reusable workflow recommended)
2. **Copy the appropriate example** to your project
3. **Customize the configuration** for your service
4. **Configure GitHub secrets** using the setup script
5. **Test the deployment** with a staging environment
