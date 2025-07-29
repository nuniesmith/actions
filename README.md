# 🚀 Standardized GitHub Actions Deployment Repository

This repository provides standardized GitHub Actions workflows and deployment scripts for deploying applications to Linode servers with Tailscale VPN, Netdata monitoring, and proper user management.

## 🎯 Supported Projects

- **FKS Trading Systems** - Multi-container trading platform
- **NGINX Reverse Proxy** - Load balancer and SSL termination
- **ATS Game Servers** - American Truck Simulator dedicated servers
- **Custom Applications** - Extensible for any Docker-based project

## 🏗️ Architecture Overview

### User Management Strategy
- **`root`** - Default system admin (emergency access)
- **`jordan`** - Personal admin account (sudo privileges)
- **`actions_user`** - GitHub Actions deployment account (sudo privileges)
- **`{SERVICE}_user`** - Service-specific account (non-sudo, docker group)

### Infrastructure Components
- **Linode VPS** - Cloud server hosting
- **Tailscale VPN** - Secure private networking
- **Netdata** - System monitoring and alerting
- **Docker** - Container orchestration
- **NGINX** - Reverse proxy and SSL termination

## 🚀 Quick Start

### 1. Setup Repository Secrets
```bash
# Run the interactive setup script
./scripts/setup-github-secrets.sh
```

### 2. Deploy Your Service
```bash
# Use the standardized workflow
gh workflow run deploy-service.yml \
  -f service_name=your-service \
  -f deployment_mode=full-deploy \
  -f create_new_server=true
```

### 3. Access Your Service
- **Web Interface**: `https://your-service.7gram.xyz` (via Tailscale)
- **SSH Access**: `ssh jordan@your-service.tail-scale-ip`
- **Monitoring**: `https://your-service.7gram.xyz:19999` (Netdata)

## 📁 Repository Structure

```
actions/
├── .github/workflows/          # Reusable GitHub Actions workflows
│   ├── deploy-service.yml      # Main deployment workflow
│   ├── destroy-service.yml     # Service cleanup workflow
│   └── health-check.yml        # Service monitoring workflow
├── scripts/                    # Deployment and utility scripts
│   ├── linode/                 # Linode server management
│   ├── tailscale/              # VPN configuration
│   ├── monitoring/             # Netdata setup
│   ├── users/                  # User management
│   └── services/               # Service-specific deployments
├── templates/                  # Reusable configuration templates
│   ├── docker-compose/         # Docker Compose templates
│   ├── nginx/                  # NGINX configuration templates
│   └── systemd/                # SystemD service templates
├── docs/                       # Documentation
└── examples/                   # Example configurations
```

## 🔧 Features

### ✅ Standardized Deployment
- Consistent server setup across all projects
- Automated user account creation with proper permissions
- Standardized directory structure and ownership

### ✅ Security First
- Tailscale VPN for secure access
- SSH key-based authentication
- Proper sudo configuration
- Service isolation with dedicated users

### ✅ Monitoring & Observability
- Netdata monitoring with cloud integration
- Discord notifications for deployment status
- Health checks and automated recovery

### ✅ Multi-Service Support
- Deploy multiple services on the same server
- Service isolation with user separation
- Shared infrastructure components (NGINX, monitoring)

### ✅ Development Workflow
- Staging and production environments
- Automated testing and validation
- Rollback capabilities

## 🎯 Service Types

### 1. **Container Services** (FKS, Custom Apps)
- Docker Compose orchestration
- Service-specific user accounts
- Environment variable management
- Health checks and auto-restart

### 2. **Reverse Proxy** (NGINX)
- SSL termination and certificate management
- Load balancing and request routing
- Security headers and rate limiting
- Static file serving

### 3. **Game Servers** (ATS, Game Hosting)
- Steam integration and mod support
- Save game management
- Performance optimization
- Player management interfaces

## 📋 Prerequisites

### Required GitHub Secrets
```bash
# Linode Infrastructure
LINODE_TOKEN                 # Linode API access token
SERVICE_ROOT_PASSWORD        # Root password for new servers

# User Accounts
JORDAN_PASSWORD             # Admin user password
ACTIONS_USER_PASSWORD       # CI/CD user password

# VPN & Networking
TAILSCALE_AUTH_KEY          # Tailscale authentication key

# Monitoring (Optional)
NETDATA_CLAIM_TOKEN         # Netdata Cloud integration
NETDATA_CLAIM_ROOM          # Netdata room ID

# DNS Management (Optional)
CLOUDFLARE_API_TOKEN        # Cloudflare API access
CLOUDFLARE_ZONE_ID          # DNS zone ID

# Container Registry (Optional)
DOCKER_USERNAME             # Docker Hub username
DOCKER_TOKEN                # Docker Hub access token

# Notifications (Optional)
DISCORD_WEBHOOK             # Discord webhook URL
```

### Local Requirements
- GitHub CLI (`gh`) for workflow management
- SSH client for server access
- Tailscale client for VPN access

## 🔗 Integration Examples

### Using in Your Project Repository
```yaml
# .github/workflows/deploy.yml
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
    secrets: inherit
```

### Custom Service Configuration
```yaml
# services/my-service/config.yml
service:
  name: my-service
  type: container
  domain: my-service.7gram.xyz
  user: my_service_user
  
deployment:
  compose_file: docker-compose.yml
  env_template: .env.template
  health_check: /api/health
  
infrastructure:
  server_type: g6-standard-2
  region: ca-central
  backup_enabled: true
```

## 📚 Documentation

- [**Deployment Guide**](docs/DEPLOYMENT_GUIDE.md) - Step-by-step deployment instructions
- [**Security Model**](docs/SECURITY.md) - Security architecture and best practices
- [**Service Configuration**](docs/SERVICE_CONFIG.md) - Service-specific configuration options
- [**Troubleshooting**](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [**API Reference**](docs/API_REFERENCE.md) - Workflow inputs and outputs

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-service-type`
3. Test your changes with a staging deployment
4. Submit a pull request with detailed description

## 📝 License

MIT License - see [LICENSE](LICENSE) for details.

---

**Built with ❤️ by Jordan for consistent, secure, and scalable deployments**
