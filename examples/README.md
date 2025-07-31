# Examples: Using the Unified Service Management Actions

This directory contains examples of how to integrate the unified deployment and management actions into your own project repositories.

## 🎯 Integration Methods

### 1. Unified Workflow (Recommended)
Reference the unified workflow from your project:

```yaml
# .github/workflows/deploy.yml in your project repository
name: Manage My Service
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      action_type:
        type: choice
        options: ['deploy', 'destroy', 'health-check', 'restart']
        default: 'deploy'
      skip_tests:
        type: boolean
        default: false
      skip_docker_build:
        type: boolean
        default: false
      overwrite_server:
        type: boolean
        default: false

jobs:
  manage-service:
    uses: nuniesmith/actions/.github/workflows/deploy.yml@main
    with:
      service_name: my-service
      action_type: ${{ github.event.inputs.action_type || 'deploy' }}
      deployment_mode: update-only
      skip_tests: ${{ github.event.inputs.skip_tests || false }}
      skip_docker_build: ${{ github.event.inputs.skip_docker_build || false }}
      build_docker_on_changes: true
      overwrite_server: ${{ github.event.inputs.overwrite_server || false }}
      server_type: g6-standard-2
      target_region: ca-central
    secrets:
      LINODE_CLI_TOKEN: ${{ secrets.LINODE_CLI_TOKEN }}
      SERVICE_ROOT_PASSWORD: ${{ secrets.MY_SERVICE_ROOT_PASSWORD }}
      JORDAN_PASSWORD: ${{ secrets.JORDAN_PASSWORD }}
      ACTIONS_USER_PASSWORD: ${{ secrets.ACTIONS_USER_PASSWORD }}
      TAILSCALE_AUTH_KEY: ${{ secrets.TAILSCALE_AUTH_KEY }}
      TAILSCALE_OAUTH_CLIENT_ID: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
      TAILSCALE_OAUTH_SECRET: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ZONE_ID: ${{ secrets.CLOUDFLARE_ZONE_ID }}
      DOCKER_USERNAME: ${{ secrets.DOCKER_USERNAME }}
      DOCKER_TOKEN: ${{ secrets.DOCKER_TOKEN }}
      DISCORD_WEBHOOK: ${{ secrets.DISCORD_WEBHOOK }}
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
          repository: nuniesmith/actions
          path: ./.actions
      
      - name: Run Custom Deployment
        run: |
          chmod +x ./.actions/scripts/server-manager.sh
          ./.actions/scripts/server-manager.sh create --service my-service
```

### 3. Fork and Customize
Fork the actions repository and customize for your specific needs.

## � New Unified Features

The unified workflow now includes all the options you requested:

- **Skip Tests**: `skip_tests: true/false`
- **Skip Docker Build**: `skip_docker_build: true/false`  
- **Smart Docker Building**: `build_docker_on_changes: true/false`
- **Server Overwrite**: `overwrite_server: true/false`
- **Multiple Actions**: deploy, destroy, health-check, restart
- **Change Detection**: Only builds when code/Docker files change

## �📁 Example Files

Each example includes:

- **Workflow file** - GitHub Actions configuration
- **Service config** - Service-specific settings  
- **Documentation** - Setup and usage instructions

## 🚀 Quick Start

1. **Choose your integration method** (unified workflow recommended)
2. **Copy the appropriate example** to your project
3. **Customize the configuration** for your service
4. **Configure GitHub secrets** using the setup script
5. **Test the deployment** with health-check mode first

## 🎯 Ready-to-Use Examples

- `fks-deploy.yml` - For FKS AI service (8GB RAM)
- `nginx-deploy.yml` - For NGINX reverse proxy (2GB RAM)  
- `ats-deploy.yml` - For ATS game server (4GB RAM)

All examples now use the unified workflow with your requested options!
