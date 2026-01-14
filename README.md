# Actions - Multi-Distro Server Setup & CI/CD Automation

A **template repository** for setting up fresh Ubuntu, Fedora, and Arch Linux servers with automated CI/CD deployment capabilities via GitHub Actions and Tailscale.

**Use this repo as a template** to build deployment workflows for your specific projects.

## Features

- 🐧 **Multi-Distro Support**: Ubuntu/Debian, Fedora/RHEL/CentOS, Arch Linux
- 🔗 **Tailscale Integration**: Secure server access via Tailscale VPN (no public SSH exposure)
- 🔐 **Automated Secrets Generation**: SSH keys, API keys, and secure credentials
- 🚀 **GitHub Actions Workflows**: Manual trigger with easy-to-use inputs
- 🐳 **Docker Ready**: Installs Docker and Docker Compose automatically
- 👤 **CI/CD User Setup**: Creates dedicated `actions` user for deployments
- 📋 **Easy Secret Export**: Outputs secrets in copy-friendly format
- 📁 **Simple Deploy Path**: Repos clone directly to `/home/actions/<repo-name>`

## Prerequisites

Before using this workflow, you need:

1. **Tailscale OAuth Credentials** (for GitHub Actions to connect to your network):
   - Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
   - Create an OAuth client with appropriate permissions
   - Add these as GitHub repository secrets:
     - `TAILSCALE_OAUTH_CLIENT_ID`
     - `TAILSCALE_OAUTH_SECRET`

2. **A Fresh Server** running Ubuntu, Fedora, or Arch Linux:
   - Connected to your Tailscale network
   - SSH access with a user that has sudo privileges

## Quick Start

### Step 1: Set Up Tailscale OAuth Secrets

Add these secrets to your GitHub repository (`Settings → Secrets and variables → Actions`):

| Secret Name | Description |
|-------------|-------------|
| `TAILSCALE_OAUTH_CLIENT_ID` | OAuth Client ID from Tailscale admin |
| `TAILSCALE_OAUTH_SECRET` | OAuth Secret from Tailscale admin |

### Step 2: Run the Server Setup Workflow

1. Go to **Actions** tab → Select **"🖥️ Server Setup & CI/CD"**

2. Click **"Run workflow"** and fill in:

| Input | Required | Example | Description |
|-------|----------|---------|-------------|
| `tailscale_ip` | ✅ | `100.64.0.15` | Tailscale IP of your server |
| `ssh_user` | ✅ | `jordan` | Your username on the server |
| `ssh_password` | ✅ | `********` | SSH password (masked in logs) |
| `ssh_port` | ❌ | `22` | SSH port (default: 22) |
| `repo_url` | ❌ | `https://github.com/user/repo.git` | Repository to clone after setup |
| `repo_branch` | ❌ | `main` | Branch to clone |
| `server_name` | ❌ | `production` | Friendly name for this server |

3. **Wait for completion** - the workflow will:
   - Connect to Tailscale network
   - SSH into your server
   - Install Docker and dependencies
   - Create the `actions` CI/CD user
   - Generate SSH keys and secrets
   - Output credentials for easy copying
   - Optionally clone your repository

### Step 3: Copy the Generated Secrets

After the workflow completes, check the logs for the generated secrets. Add these to your project repositories for deployments:

| Secret Name | Description |
|-------------|-------------|
| `PROD_TAILSCALE_IP` | Tailscale IP of your server |
| `PROD_SSH_KEY` | SSH private key for `actions` user |
| `PROD_SSH_PORT` | SSH port (usually `22`) |
| `PROD_SSH_USER` | SSH username (`actions`) |

## Workflow Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Server Setup Workflow                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────┐  │
│  │ 1. Tailscale     │───▶│ 2. Server Setup  │───▶│ 3. Generate  │  │
│  │    Connect       │    │    (Multi-Distro)│    │    Secrets   │  │
│  └──────────────────┘    └──────────────────┘    └──────────────┘  │
│           │                      │                      │          │
│           ▼                      ▼                      ▼          │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────┐  │
│  │ Connect via      │    │ Install Docker   │    │ Create SSH   │  │
│  │ OAuth to your    │    │ Create 'actions' │    │ Keys, Output │  │
│  │ Tailnet          │    │ user, Setup dirs │    │ for copying  │  │
│  └──────────────────┘    └──────────────────┘    └──────────────┘  │
│                                                         │          │
│                                                         ▼          │
│                                              ┌──────────────────┐  │
│                                              │ 4. Clone Repo    │  │
│                                              │    (Optional)    │  │
│                                              └──────────────────┘  │
│                                                         │          │
│                                                         ▼          │
│                                              ┌──────────────────┐  │
│                                              │ 5. Summary &     │  │
│                                              │    Cleanup       │  │
│                                              └──────────────────┘  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Manual Setup (Alternative)

If you prefer to set up manually on the server:

```bash
# Clone this repository
git clone https://github.com/YOUR_USERNAME/actions.git
cd actions/scripts

# Make scripts executable
chmod +x setup-server.sh generate-secrets.sh

# Run setup (will prompt for options)
sudo ./setup-server.sh

# Generate secrets
sudo ./generate-secrets.sh
```

## Using This as a Template

### For New Projects

1. Copy `.github/workflows/deploy-template.yml` to your project
2. Rename it to `deploy.yml` or `ci-cd.yml`
3. Update the `PROJECT_NAME` environment variable
4. Customize the deployment steps for your stack

### Required Secrets for Deployments

Add these to each project repository that deploys to your server:

| Secret Name | Description |
|-------------|-------------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth Client ID |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth Secret |
| `PROD_TAILSCALE_IP` | Tailscale IP of your server |
| `PROD_SSH_KEY` | SSH private key for `actions` user |
| `PROD_SSH_PORT` | SSH port (usually `22`) |
| `PROD_SSH_USER` | SSH username (`actions`) |

## Example Deployment Workflow

After setup, use these secrets in your deployment workflows:

```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

env:
  PROJECT_NAME: my-project  # Your repo name - deploys to /home/actions/my-project

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Connect to Tailscale
        uses: tailscale/github-action@v2
        with:
          oauth-client-id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
          tags: tag:ci

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.PROD_SSH_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -p ${{ secrets.PROD_SSH_PORT }} ${{ secrets.PROD_TAILSCALE_IP }} >> ~/.ssh/known_hosts

      - name: Deploy
        run: |
          ssh -p ${{ secrets.PROD_SSH_PORT }} \
            ${{ secrets.PROD_SSH_USER }}@${{ secrets.PROD_TAILSCALE_IP }} \
            "cd ~/${{ env.PROJECT_NAME }} && git pull && docker compose up -d"
```

> **Note**: Repositories are deployed to `/home/actions/<repo-name>` (e.g., `/home/actions/my-project`)

## Directory Structure

```
actions/
├── .github/
│   └── workflows/
│       ├── ci-cd.yml           # Main server setup workflow (Tailscale-based)
│       └── deploy-template.yml # Template for project deployments
├── scripts/
│   ├── setup-server.sh         # Multi-distro server setup
│   └── generate-secrets.sh     # Secret generation script
├── LICENSE
└── README.md
```

## Server Directory Structure (After Setup)

```
/home/actions/
├── .ssh/
│   ├── id_ed25519          # SSH private key
│   ├── id_ed25519.pub      # SSH public key
│   └── authorized_keys     # Authorized keys for SSH
├── <repo-name>/            # Each repo clones here (e.g., /home/actions/fks)
├── logs/                   # Application logs
├── backups/                # Backup storage
├── data/                   # Persistent data
└── .config/
    └── server.env          # Server environment template
```

## Supported Operating Systems

| Distribution | Version | Status |
|-------------|---------|--------|
| Ubuntu | 20.04+ | ✅ Fully Supported |
| Debian | 11+ | ✅ Fully Supported |
| Fedora | 38+ | ✅ Fully Supported |
| RHEL/CentOS | 8+ | ✅ Supported |
| Rocky Linux | 8+ | ✅ Supported |
| Arch Linux | Rolling | ✅ Fully Supported |
| Manjaro | Rolling | ✅ Supported |

## Security Best Practices

1. **Use Tailscale** for all server access - never expose SSH to the public internet

2. **Delete credentials file** after copying secrets:
   ```bash
   sudo rm /tmp/server_credentials_*.txt
   ```

3. **Rotate secrets** periodically by re-running the secret generation

4. **Use GitHub Environments** for production deployments with approval gates

5. **Enable 2FA** on your GitHub and Tailscale accounts

6. **Tag your CI runners** in Tailscale ACLs for proper access control

## Troubleshooting

### Tailscale Connection Failed

- Verify OAuth credentials are correct in GitHub Secrets
- Check that the OAuth client has proper permissions
- Ensure your Tailscale ACLs allow the `tag:ci` tag

### SSH Connection Failed

- Verify Tailscale is connected on the server: `tailscale status`
- Check if SSH is running: `sudo systemctl status sshd`
- Verify the user and password are correct

### Docker Permission Denied

Log out and back in after setup for docker group to take effect:
```bash
newgrp docker
# or
su - $USER
```

### Secrets Not Generating

Ensure the `actions` user exists:
```bash
id actions
# If not, run setup-server.sh first
```

## Deploy Path Structure

When you deploy a project, it goes to `/home/actions/<repo-name>`:

```
/home/actions/
├── fks/                    # git clone https://github.com/user/fks.git
│   ├── docker-compose.yml
│   ├── .env
│   └── ...
├── another-project/        # git clone https://github.com/user/another-project.git
│   └── ...
├── logs/
├── backups/
└── data/
```

## Example: Complete FKS-Style Deployment

This workflow pattern is based on the proven FKS Trading Platform CI/CD pipeline:

```yaml
name: 🚀 Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment:
      name: production
      url: https://your-domain.com
    
    steps:
      - uses: actions/checkout@v4

      - name: 🔌 Connect to Tailscale
        uses: tailscale/github-action@v2
        with:
          oauth-client-id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
          tags: tag:ci

      - name: 🔑 Setup SSH via Tailscale
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.PROD_SSH_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan -p ${{ secrets.PROD_SSH_PORT }} ${{ secrets.PROD_TAILSCALE_IP }} >> ~/.ssh/known_hosts

      - name: 🔍 Test SSH Connection
        run: |
          ssh -o BatchMode=yes -o ConnectTimeout=10 \
            -p ${{ secrets.PROD_SSH_PORT }} \
            ${{ secrets.PROD_SSH_USER }}@${{ secrets.PROD_TAILSCALE_IP }} \
            "echo '✅ SSH connection successful'"

      - name: 🚀 Deploy
        run: |
          ssh -p ${{ secrets.PROD_SSH_PORT }} \
            ${{ secrets.PROD_SSH_USER }}@${{ secrets.PROD_TAILSCALE_IP }} << 'DEPLOY'
            cd ~/myapp
            git pull origin main
            docker compose pull
            docker compose up -d --remove-orphans
            docker compose ps
          DEPLOY
```

> This pattern is based on the proven FKS Trading Platform CI/CD pipeline in `ci-fks.yml`.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Related Projects

- [Tailscale](https://tailscale.com/) - Zero config VPN
- [GitHub Actions](https://docs.github.com/en/actions) - CI/CD platform
- [Docker](https://www.docker.com/) - Container platform