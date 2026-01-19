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
| [rust-ci](#rust-ci) | Complete Rust CI pipeline with caching, protobuf, and workspace support |
| [setup-rust](#setup-rust) | Setup Rust toolchain with protobuf and caching |
| [kotlin-ci](#kotlin-ci) | Kotlin/KMP CI pipeline with Gradle |
| [ssh-deploy](#ssh-deploy) | Deploy to remote server via SSH over Tailscale |
| [health-check](#health-check) | Verify deployment health via HTTP, Docker containers, and custom commands |
| [llm-audit](#llm-audit) | LLM-powered code audits (xAI, Anthropic, Google) |
| [cloudflare-dns-update](#cloudflare-dns-update) | Create or update Cloudflare DNS records |
| [ssl-certbot-cloudflare](#ssl-certbot-cloudflare) | Generate SSL certificates with Let's Encrypt via Cloudflare DNS-01 |

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

Complete Rust CI pipeline with caching, linting, testing, building, and optional protobuf/workspace support.

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

### Advanced Usage (Workspace with Protobuf)

```yaml
- uses: nuniesmith/actions/.github/actions/rust-ci@main
  with:
    toolchain: "1.92.0"
    workspace: "true"
    pre-build-packages: "my-proto-crate"
    install-protobuf: "true"
    install-buf: "true"
    run-buf-lint: "true"
    run-buf-breaking: "true"
    proto-directory: "proto"
    clippy-args: "--workspace --lib -- -D warnings"
    test-lib-only: "true"
    test-integration: "true"
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `toolchain` | No | `stable` | Rust toolchain (`stable`, `beta`, `nightly`, or version) |
| `components` | No | `rustfmt, clippy` | Additional components |
| `targets` | No | `''` | Additional targets to install |
| `run-fmt` | No | `true` | Run `cargo fmt` check |
| `run-clippy` | No | `true` | Run `cargo clippy` |
| `run-tests` | No | `true` | Run `cargo test` |
| `run-build` | No | `true` | Run `cargo build` |
| `build-release` | No | `true` | Build in release mode |
| `clippy-args` | No | `--all-targets --all-features -- -D warnings` | Clippy arguments |
| `test-args` | No | `--verbose` | Test arguments |
| `build-args` | No | `--verbose` | Build arguments |
| `features` | No | `''` | Features to enable |
| `all-features` | No | `false` | Enable all features |
| `no-default-features` | No | `false` | Disable default features |
| `working-directory` | No | `.` | Working directory |
| `coverage` | No | `false` | Generate code coverage |
| `coverage-output-dir` | No | `./coverage` | Coverage output directory |
| `workspace` | No | `false` | Build/test entire workspace |
| `packages` | No | `''` | Specific packages to build/test |
| `exclude-packages` | No | `''` | Packages to exclude |
| `install-protobuf` | No | `false` | Install protobuf compiler |
| `install-buf` | No | `false` | Install buf CLI |
| `run-buf-lint` | No | `false` | Run buf lint on proto files |
| `run-buf-breaking` | No | `false` | Run buf breaking change detection |
| `proto-directory` | No | `proto` | Directory containing proto files |
| `buf-breaking-against` | No | `.git#branch=main` | Git ref for breaking check |
| `pre-build-packages` | No | `''` | Packages to build first |
| `test-lib-only` | No | `false` | Run only library tests |
| `test-integration` | No | `false` | Run integration tests separately |
| `install-system-deps` | No | `false` | Install common system dependencies |
| `additional-apt-packages` | No | `''` | Additional apt packages |
| `cache-key-suffix` | No | `rust-ci` | Cache key suffix |

### Outputs

| Output | Description |
|--------|-------------|
| `fmt-result` | Result of fmt check |
| `clippy-result` | Result of clippy |
| `test-result` | Result of tests |
| `build-result` | Result of build |
| `coverage-file` | Path to coverage file |
| `buf-lint-result` | Result of buf lint |

---

## cloudflare-dns-update

Create or update Cloudflare DNS A records. Supports updating multiple records in a single action.

### Usage

```yaml
- uses: nuniesmith/actions/.github/actions/cloudflare-dns-update@main
  with:
    api-token: ${{ secrets.CLOUDFLARE_API_KEY }}
    zone-id: ${{ secrets.CLOUDFLARE_ZONE_ID }}
    record-name: example.com
    record-content: 100.64.0.1
```

### Usage with Multiple Records

```yaml
- uses: nuniesmith/actions/.github/actions/cloudflare-dns-update@main
  with:
    api-token: ${{ secrets.CLOUDFLARE_API_KEY }}
    zone-id: ${{ secrets.CLOUDFLARE_ZONE_ID }}
    record-name: example.com
    record-content: 100.64.0.1
    additional-records: '[{"name": "www.example.com"}, {"name": "api.example.com", "content": "100.64.0.2"}]'
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `api-token` | Yes | - | Cloudflare API token with DNS edit permissions |
| `zone-id` | Yes | - | Cloudflare Zone ID |
| `record-name` | Yes | - | DNS record name (e.g., `example.com`) |
| `record-content` | Yes | - | IP address for the DNS record |
| `record-type` | No | `A` | DNS record type |
| `ttl` | No | `1` | TTL in seconds (1 = automatic) |
| `proxied` | No | `false` | Whether to proxy through Cloudflare |
| `additional-records` | No | `[]` | JSON array of additional records |

### Outputs

| Output | Description |
|--------|-------------|
| `updated` | Whether the DNS record was updated |
| `record-id` | The Cloudflare record ID |
| `records-updated` | Number of records updated |

---

## ssl-certbot-cloudflare

Generate SSL certificates using Let's Encrypt with Cloudflare DNS-01 challenge. Supports automatic fallback to self-signed certificates if Let's Encrypt fails (rate limits, missing credentials, etc.). Optionally deploy certificates to a remote server.

### Usage (Generate Only)

```yaml
- uses: nuniesmith/actions/.github/actions/ssl-certbot-cloudflare@main
  with:
    domain: example.com
    additional-domains: "www.example.com,api.example.com"
    cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_KEY }}
    email: admin@example.com
```

### Usage with Self-Signed Fallback

```yaml
- uses: nuniesmith/actions/.github/actions/ssl-certbot-cloudflare@main
  with:
    domain: example.com
    additional-domains: "www.example.com"
    cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_KEY }}
    email: admin@example.com
    fallback-to-self-signed: "true"
    self-signed-days: "365"
```

### Usage with Deployment

```yaml
- uses: nuniesmith/actions/.github/actions/ssl-certbot-cloudflare@main
  with:
    domain: example.com
    additional-domains: "www.example.com"
    cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_KEY }}
    email: admin@example.com
    fallback-to-self-signed: "true"
    deploy-to-server: "true"
    ssh-host: ${{ secrets.PROD_IP }}
    ssh-user: actions
    ssh-key: ${{ secrets.PROD_SSH_KEY }}
    docker-volume-name: my_ssl_certs
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `domain` | Yes | - | Primary domain for the certificate |
| `additional-domains` | No | `''` | Additional domains (comma-separated) |
| `cloudflare-api-token` | No | `''` | Cloudflare API token with DNS edit permissions |
| `email` | Yes | - | Email for Let's Encrypt notifications |
| `propagation-seconds` | No | `60` | DNS propagation wait time |
| `staging` | No | `false` | Use Let's Encrypt staging server |
| `fallback-to-self-signed` | No | `false` | Generate self-signed certs if Let's Encrypt fails |
| `self-signed-days` | No | `365` | Validity period for self-signed certificates |
| `deploy-to-server` | No | `false` | Deploy certificates to remote server |
| `ssh-host` | No | `''` | SSH host for deployment |
| `ssh-port` | No | `22` | SSH port |
| `ssh-user` | No | `actions` | SSH username |
| `ssh-key` | No | `''` | SSH private key |
| `docker-volume-name` | No | `certbot_certs` | Docker volume for certificates |
| `docker-username` | No | `''` | Docker Hub username (avoid rate limits) |
| `docker-token` | No | `''` | Docker Hub token |

### Outputs

| Output | Description |
|--------|-------------|
| `cert-ready` | Whether certificates were generated |
| `cert-type` | Type of certificate: `letsencrypt` or `self-signed` |
| `cert-path` | Path to the certificate directory |
| `expiry-date` | Certificate expiry date |
| `deployed` | Whether certificates were deployed |

### Self-Signed Fallback Behavior

When `fallback-to-self-signed: "true"` is set, the action will generate self-signed certificates if:

1. **Cloudflare API token is missing** - No credentials provided
2. **Let's Encrypt rate limits** - Too many certificate requests
3. **DNS propagation failures** - Cloudflare DNS-01 challenge fails
4. **Any certbot error** - Network issues, invalid credentials, etc.

The self-signed certificates:
- Use the same directory structure as Let's Encrypt (compatible with nginx configs)
- Include all specified domains in the SAN (Subject Alternative Name)
- Are valid for the configured number of days (default: 365)
- Will cause browser security warnings (expected for self-signed)
- Are automatically replaced with real Let's Encrypt certs on the next successful run

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

## health-check

Verify deployment health via HTTP endpoints, Docker containers, and custom commands. Supports remote health checks over SSH.

### Usage

```yaml
- uses: nuniesmith/actions/.github/actions/health-check@main
  with:
    endpoints: |
      [
        {"url": "https://example.com/health", "expected_status": 200},
        {"url": "http://localhost:3000/api/health", "expected_status": 200}
      ]
    containers: "app_postgres app_redis app_api"
    initial-delay: "30"
    retry-count: "3"
    retry-delay: "10"
```

### Usage with Remote Server

```yaml
- uses: nuniesmith/actions/.github/actions/health-check@main
  with:
    endpoints: |
      [
        {"url": "https://myapp.example.com/health", "expected_status": 200}
      ]
    containers: "myapp_web myapp_db myapp_cache"
    ssh-host: ${{ secrets.PROD_TAILSCALE_IP }}
    ssh-port: "22"
    ssh-user: actions
    ssh-key: ${{ secrets.PROD_SSH_KEY }}
    custom-command: "docker compose ps --status running | grep -c 'running'"
    initial-delay: "30"
    retry-count: "3"
    fail-on-unhealthy: "true"
```

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `endpoints` | No | `[]` | JSON array of HTTP endpoints `[{url, method, expected_status, timeout}]` |
| `containers` | No | `''` | Space-separated Docker container names to verify |
| `ssh-host` | No | `''` | SSH host for remote health checks |
| `ssh-port` | No | `22` | SSH port |
| `ssh-user` | No | `actions` | SSH username |
| `ssh-key` | No | `''` | SSH private key |
| `custom-command` | No | `''` | Custom command (must exit 0 for success) |
| `retry-count` | No | `3` | Number of retries for failed checks |
| `retry-delay` | No | `10` | Delay between retries (seconds) |
| `initial-delay` | No | `30` | Initial delay before starting checks (seconds) |
| `timeout` | No | `10` | Timeout for each check (seconds) |
| `fail-on-unhealthy` | No | `true` | Fail the step if any check fails |

### Outputs

| Output | Description |
|--------|-------------|
| `healthy` | Whether all health checks passed |
| `endpoints-healthy` | Number of healthy endpoints |
| `containers-healthy` | Number of healthy containers |
| `failed-checks` | List of failed checks |

### Endpoint Configuration

Each endpoint in the JSON array can have:

| Property | Required | Default | Description |
|----------|----------|---------|-------------|
| `url` | Yes | - | URL to check |
| `method` | No | `GET` | HTTP method |
| `expected_status` | No | `200` | Expected HTTP status code |
| `timeout` | No | (global) | Timeout for this endpoint |

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

  infrastructure:
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

      - name: 🌐 Update DNS
        uses: nuniesmith/actions/.github/actions/cloudflare-dns-update@main
        with:
          api-token: ${{ secrets.CLOUDFLARE_API_KEY }}
          zone-id: ${{ secrets.CLOUDFLARE_ZONE_ID }}
          record-name: myapp.example.com
          record-content: ${{ secrets.PROD_IP }}

      - name: 🔐 Generate SSL Certificates
        uses: nuniesmith/actions/.github/actions/ssl-certbot-cloudflare@main
        with:
          domain: myapp.example.com
          cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_KEY }}
          email: admin@example.com
          deploy-to-server: "true"
          ssh-host: ${{ secrets.PROD_IP }}
          ssh-key: ${{ secrets.PROD_SSH_KEY }}

  deploy:
    needs: infrastructure
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
| `CLOUDFLARE_API_KEY` | Cloudflare API token (DNS edit permissions) |
| `CLOUDFLARE_ZONE_ID` | Cloudflare Zone ID |
| `SSL_EMAIL` | Email for Let's Encrypt certificates |
| `DISCORD_WEBHOOK` | Discord webhook URL (optional) |

---

## License

MIT License - Feel free to use and modify these actions for your projects.