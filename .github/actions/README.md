# 🚀 Reusable GitHub Actions

This repository contains reusable composite actions for CI/CD pipelines. These actions are designed to work together for deploying applications to servers over Tailscale VPN.

## 📋 Quick Start

Looking for ready-to-use workflows? Check out our **[Workflow Templates](../templates/README.md)**:

| Template | Description |
|----------|-------------|
| [rust-project.yml](../templates/rust-project.yml) | Complete Rust CI/CD pipeline |
| [kotlin-project.yml](../templates/kotlin-project.yml) | Kotlin/KMP CI with multi-platform builds |
| [nodejs-project.yml](../templates/nodejs-project.yml) | Node.js/TypeScript CI pipeline |
| [python-project.yml](../templates/python-project.yml) | Python CI with pip/poetry/pipenv |
| [simple-deploy.yml](../templates/simple-deploy.yml) | Minimal deployment-only workflow |

---

## Available Actions

| Action | Description |
|--------|-------------|
| [discord-notify](#discord-notify) | Send rich embed notifications to Discord |
| [tailscale-connect](#tailscale-connect) | Connect to Tailscale network and verify connectivity |
| [docker-build-push](#docker-build-push) | Build and push multi-arch Docker images |
| [rust-ci](#rust-ci) | Complete Rust CI pipeline with caching |
| [setup-rust](#setup-rust) | Setup Rust toolchain with protobuf and caching |
| [kotlin-ci](#kotlin-ci) | Kotlin/KMP CI pipeline with Gradle |
| [ssh-deploy](#ssh-deploy) | Deploy to remote server via SSH over Tailscale |
| [llm-audit](#llm-audit) | LLM-powered code audits (xAI, Anthropic, Google) |

---

## discord-notify

Send rich embed notifications to Discord webhooks.

### Usage

```yaml
- uses: nuniesmith/actions/.github/actions/discord-notify@main
  with:
    webhook-url: ${{ secrets.DISCORD_WEBHOOK }}
    title: "🚀 Deployment Started"
    description: "Deploying version ${{ github.sha }}"
    status: started
    include-repo-info: "true"
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `webhook-url` | Yes | - | Discord webhook URL |
| `title` | Yes | - | Embed title |
| `description` | No | `''` | Embed description |
| `status` | No | `info` | Status type: `success`, `failure`, `info`, `warning`, `started` |
| `color` | No | auto | Embed color (auto-set by status) |
| `fields` | No | `[]` | JSON array of field objects `[{name, value, inline}]` |
| `footer` | No | `''` | Footer text |
| `include-timestamp` | No | `true` | Include timestamp in embed |
| `include-repo-info` | No | `false` | Include repository, branch, and commit info |

### Outputs

| Output | Description |
|--------|-------------|
| `sent` | Whether the notification was sent successfully |

---

## tailscale-connect

Connect to Tailscale network and optionally verify connectivity to a target server.

### Usage

```yaml
- uses: nuniesmith/actions/.github/actions/tailscale-connect@main
  with:
    oauth-client-id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
    oauth-secret: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
    target-ip: ${{ secrets.PROD_TAILSCALE_IP }}
    target-ssh-port: "22"
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `oauth-client-id` | Yes | - | Tailscale OAuth Client ID |
| `oauth-secret` | Yes | - | Tailscale OAuth Secret |
| `tags` | No | `tag:ci` | Tailscale ACL tags |
| `version` | No | `''` | Tailscale version to install |
| `target-ip` | No | `''` | Target Tailscale IP to verify connectivity |
| `target-ssh-port` | No | `22` | SSH port to check on target |
| `wait-time` | No | `5` | Seconds to wait for Tailscale to connect |

### Outputs

| Output | Description |
|--------|-------------|
| `connected` | Whether Tailscale connected successfully |
| `tailscale-ip` | Our Tailscale IPv4 address |
| `target-reachable` | Whether the target IP is reachable |
| `ssh-reachable` | Whether SSH port is reachable on target |

---

## docker-build-push

Build and push multi-architecture Docker images to a registry.

### Usage

```yaml
- uses: nuniesmith/actions/.github/actions/docker-build-push@main
  with:
    image-name: myuser/myimage
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_TOKEN }}
    dockerfile: docker/Dockerfile
    platforms: linux/amd64,linux/arm64
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `image-name` | Yes | - | Full image name (e.g., `username/image`) |
| `username` | Yes | - | Registry username |
| `password` | Yes | - | Registry password or token |
| `registry` | No | `docker.io` | Docker registry |
| `dockerfile` | No | `Dockerfile` | Path to Dockerfile |
| `context` | No | `.` | Build context path |
| `platforms` | No | `linux/amd64,linux/arm64` | Target platforms |
| `push` | No | `true` | Push image to registry |
| `tags` | No | auto | Custom tags (multiline) |
| `build-args` | No | `''` | Build arguments (multiline `KEY=VALUE`) |
| `cache-from` | No | auto | Cache source |
| `cache-to` | No | auto | Cache destination |
| `labels` | No | `''` | Custom labels |

### Outputs

| Output | Description |
|--------|-------------|
| `image-id` | Image ID |
| `digest` | Image digest |
| `tags` | Generated tags |
| `labels` | Generated labels |

---

## rust-ci

Complete Rust CI pipeline with caching, linting, testing, and building.

### Usage

```yaml
- uses: nuniesmith/actions/.github/actions/rust-ci@main
  with:
    toolchain: stable
    run-fmt: "true"
    run-clippy: "true"
    run-tests: "true"
    run-build: "true"
    build-release: "true"
    coverage: "true"
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `toolchain` | No | `stable` | Rust toolchain (`stable`, `beta`, `nightly`) |
| `components` | No | `rustfmt, clippy` | Additional components |
| `targets` | No | `''` | Additional targets to install |
| `run-fmt` | No | `true` | Run `cargo fmt` check |
| `run-clippy` | No | `true` | Run `cargo clippy` |
| `run-tests` | No | `true` | Run `cargo test` |
| `run-build` | No | `true` | Run `cargo build` |
| `build-release` | No | `true` | Build in release mode |
| `clippy-args` | No | `--all-targets --all-features -- -D warnings` | Additional clippy arguments |
| `test-args` | No | `--verbose` | Additional test arguments |
| `build-args` | No | `--verbose` | Additional build arguments |
| `features` | No | `''` | Features to enable |
| `all-features` | No | `false` | Enable all features |
| `no-default-features` | No | `false` | Disable default features |
| `working-directory` | No | `.` | Working directory |
| `coverage` | No | `false` | Generate code coverage with cargo-tarpaulin |
| `coverage-output-dir` | No | `./coverage` | Coverage output directory |

### Outputs

| Output | Description |
|--------|-------------|
| `fmt-result` | Result of fmt check |
| `clippy-result` | Result of clippy |
| `test-result` | Result of tests |
| `build-result` | Result of build |
| `coverage-file` | Path to coverage file |

---

## ssh-deploy

Deploy to a remote server via SSH over Tailscale. Supports Docker Compose deployments with automatic service management.

### Usage

```yaml
- uses: nuniesmith/actions/.github/actions/ssh-deploy@main
  with:
    host: ${{ secrets.PROD_TAILSCALE_IP }}
    port: "22"
    username: actions
    ssh-key: ${{ secrets.PROD_SSH_KEY }}
    project-path: ~/myproject
    docker-compose-file: docker-compose.prod.yml
    docker-services: web api
    git-pull: "true"
    docker-pull: "true"
    docker-prune: "true"
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `host` | Yes | - | Target host (Tailscale IP or hostname) |
| `username` | Yes | - | SSH username |
| `project-path` | Yes | - | Path to project on remote server |
| `port` | No | `22` | SSH port |
| `ssh-key` | No | `''` | SSH private key |
| `password` | No | `''` | SSH password (fallback) |
| `deploy-command` | No | `''` | Custom deploy command |
| `pre-deploy-command` | No | `''` | Command to run before deployment |
| `post-deploy-command` | No | `''` | Command to run after deployment |
| `docker-compose-file` | No | `docker-compose.yml` | Docker compose file |
| `docker-services` | No | `''` | Space-separated services (empty = all) |
| `git-pull` | No | `true` | Pull latest changes from git |
| `git-branch` | No | `main` | Git branch to checkout/pull |
| `docker-pull` | No | `true` | Pull latest Docker images |
| `docker-prune` | No | `true` | Prune unused Docker resources |
| `env-files` | No | `''` | JSON object of env files to create |
| `timeout` | No | `30` | SSH connection timeout |
| `use-tailscale-ssh` | No | `true` | Try Tailscale SSH first |

### Outputs

| Output | Description |
|--------|-------------|
| `deployed` | Whether deployment was successful |
| `ssh-method` | SSH method used (`tailscale`/`key`/`password`) |
| `services-started` | Services that were started |

---

## Complete Example

Here's a complete CI/CD pipeline using all the actions:

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: 📣 Notify started
        uses: nuniesmith/actions/.github/actions/discord-notify@main
        with:
          webhook-url: ${{ secrets.DISCORD_WEBHOOK }}
          title: "🔨 Build Started"
          status: started
          include-repo-info: "true"

      - name: 🦀 Run Rust CI
        uses: nuniesmith/actions/.github/actions/rust-ci@main
        with:
          coverage: "true"

  build:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - name: 🐳 Build Docker Image
        uses: nuniesmith/actions/.github/actions/docker-build-push@main
        with:
          image-name: myuser/myapp
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_TOKEN }}

  deploy:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - name: 🔌 Connect to Tailscale
        uses: nuniesmith/actions/.github/actions/tailscale-connect@main
        with:
          oauth-client-id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
          oauth-secret: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
          target-ip: ${{ secrets.PROD_IP }}

      - name: 🚀 Deploy
        uses: nuniesmith/actions/.github/actions/ssh-deploy@main
        with:
          host: ${{ secrets.PROD_IP }}
          username: actions
          ssh-key: ${{ secrets.PROD_SSH_KEY }}
          project-path: ~/myapp
          docker-compose-file: docker-compose.prod.yml

      - name: ✅ Notify success
        if: success()
        uses: nuniesmith/actions/.github/actions/discord-notify@main
        with:
          webhook-url: ${{ secrets.DISCORD_WEBHOOK }}
          title: "🚀 Deployment Successful"
          status: success
```

---

## Required Secrets

For a complete setup, you'll need these repository secrets:

| Secret | Description |
|--------|-------------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth Client ID |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth Secret |
| `PROD_TAILSCALE_IP` | Production server Tailscale IP |
| `PROD_SSH_KEY` | SSH private key for deployment |
| `PROD_SSH_USER` | SSH username (default: `actions`) |
| `PROD_SSH_PORT` | SSH port (default: `22`) |
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_TOKEN` | Docker Hub access token |
| `DISCORD_WEBHOOK` | Discord webhook URL (optional) |

---

## License

MIT License - Feel free to use and modify these actions for your projects.