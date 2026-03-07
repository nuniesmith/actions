# nuniesmith/actions

A monorepo of reusable GitHub Actions composite actions and CI/CD workflow templates shared across all `nuniesmith/*` projects.

---

## Table of Contents

- [Repository Layout](#repository-layout)
- [Quick Start](#quick-start)
- [Composite Actions](#composite-actions)
  - [rust-ci](#rust-ci)
  - [setup-rust](#setup-rust)
  - [docker-build-push](#docker-build-push)
  - [ssh-deploy](#ssh-deploy)
  - [tailscale-connect](#tailscale-connect)
  - [health-check](#health-check)
  - [discord-notify](#discord-notify)
  - [cloudflare-dns-update](#cloudflare-dns-update)
  - [ssl-certbot-cloudflare](#ssl-certbot-cloudflare)
  - [ssl-check](#ssl-check)
  - [latex-setup](#latex-setup)
  - [latex-lint](#latex-lint)
  - [latex-build](#latex-build)
  - [llm-audit](#llm-audit)
  - [kotlin-ci](#kotlin-ci)
- [Workflow Templates](#workflow-templates)
- [Per-Repo Workflows](#per-repo-workflows)
- [Versioning](#versioning)
- [Required Secrets](#required-secrets)

---

## Repository Layout

```
.github/
  actions/              # Composite actions (one sub-directory each)
    rust-ci/
    setup-rust/
    docker-build-push/
    ssh-deploy/
    tailscale-connect/
    health-check/
    discord-notify/
    cloudflare-dns-update/
    ssl-certbot-cloudflare/
    ssl-check/
    latex-setup/
    latex-lint/
    latex-build/
    llm-audit/
    kotlin-ci/
  repos/                # Ready-to-copy workflow files per project
    rustassistant/
    fks/
    freddy/
    sullivan/
    futures/
    technical_papers/
  templates/            # Generic starter templates by project type
    rust-project.yml
    kotlin-project.yml
    nodejs-project.yml
    python-project.yml
    latex-project.yml
    simple-deploy.yml
    soak-test.yml
  workflows/            # Workflows that run in this repo itself
    setup-server.yml
docs/
  VERSIONING.md         # Release and tagging guide
scripts/
  release.sh            # Tag and publish a new version
  generate-secrets.sh   # Bootstrap secrets for a new server
  setup-dev-server.sh
  setup-prod-server.sh
```

---

## Quick Start

### 1. Referencing an action

```yaml
# Pinned to a major version (recommended)
uses: nuniesmith/actions/.github/actions/rust-ci@v1

# Pinned to an exact version (for reproducible builds)
uses: nuniesmith/actions/.github/actions/rust-ci@v1.2.3

# Floating main branch (avoid in production)
uses: nuniesmith/actions/.github/actions/rust-ci@main
```

### 2. Start from a template

Copy the template that matches your stack into your repo and edit the `env:` block at the top:

```bash
# Rust project
curl -o .github/workflows/ci-cd.yml \
  https://raw.githubusercontent.com/nuniesmith/actions/main/.github/templates/rust-project.yml
```

See [Workflow Templates](#workflow-templates) for the full list.

---

## Composite Actions

### `rust-ci`

> Complete Rust CI pipeline: `fmt` → `clippy` (with SARIF) → `test` → `build` → coverage.

```yaml
- uses: nuniesmith/actions/.github/actions/rust-ci@v1
  with:
    toolchain: stable          # Rust toolchain (stable, nightly, 1.82.0, …)
    run-fmt: "true"
    run-clippy: "true"
    run-tests: "true"
    run-build: "true"
    build-release: "true"      # Build with --release
    coverage: "false"          # Generate lcov + cobertura coverage report
```

**Key inputs**

| Input | Default | Description |
|---|---|---|
| `toolchain` | `stable` | Rust toolchain version |
| `components` | `rustfmt,clippy` | Toolchain components |
| `targets` | `""` | Cross-compilation targets |
| `run-fmt` | `true` | Run `cargo fmt --check` |
| `run-clippy` | `true` | Run `cargo clippy` |
| `run-tests` | `true` | Run `cargo test` |
| `run-build` | `true` | Run `cargo build` |
| `build-release` | `false` | Build with `--release` |
| `coverage` | `false` | Generate code coverage |
| `clippy-args` | `""` | Extra args passed to clippy |
| `features` | `""` | Feature flags |
| `all-features` | `false` | Pass `--all-features` |
| `workspace` | `false` | Pass `--workspace` |
| `install-protobuf` | `false` | Install `protoc` |
| `install-buf` | `false` | Install `buf` CLI |
| `run-buf-lint` | `false` | Run `buf lint` |
| `run-buf-breaking` | `false` | Run `buf breaking` |
| `test-lib-only` | `false` | Test `--lib` only |
| `test-integration` | `false` | Run integration tests separately |
| `pre-build-packages` | `""` | Space-separated crates to `cargo build` before main build |
| `additional-apt-packages` | `""` | Extra apt packages to install |
| `cache-key-suffix` | `default` | Differentiates cache keys between jobs |
| `working-directory` | `.` | Working directory |

**Outputs**

| Output | Description |
|---|---|
| `fmt-result` | `success`, `failure`, or `skipped` |
| `clippy-result` | `success`, `failure`, or `skipped` |
| `test-result` | `success`, `failure`, or `skipped` |
| `build-result` | `success`, `failure`, or `skipped` |
| `coverage-file` | Path to the coverage file (if generated) |
| `buf-lint-result` | `success`, `failure`, or `skipped` |
| `clippy-sarif-file` | Path to SARIF file (uploaded to Security tab) |

**Advanced example — workspace with protobuf**

```yaml
- uses: nuniesmith/actions/.github/actions/rust-ci@v1
  with:
    toolchain: stable
    workspace: "true"
    install-protobuf: "true"
    install-buf: "true"
    run-buf-lint: "true"
    run-buf-breaking: "true"
    proto-directory: proto/
    pre-build-packages: my-proto-crate
    test-lib-only: "true"
    test-integration: "true"
    clippy-args: "--all-targets --all-features -- -D warnings"
    cache-key-suffix: workspace
```

---

### `setup-rust`

> Lightweight toolchain + cache setup. Use this when you need Rust available but don't want the full `rust-ci` pipeline (e.g., in a dedicated security-audit job).

```yaml
- uses: nuniesmith/actions/.github/actions/setup-rust@v1
  with:
    rust-version: stable
    components: "rustfmt,clippy"
    install-protobuf: "true"
    cache-key-suffix: security
```

**Outputs:** `rust-version`, `cache-hit-registry`, `cache-hit-build`

---

### `docker-build-push`

> Multi-arch Docker build with registry push, layer caching, and auto-generated OCI labels.

```yaml
- uses: nuniesmith/actions/.github/actions/docker-build-push@v1
  with:
    image-name: myuser/myapp
    username: ${{ secrets.DOCKER_USERNAME }}
    password: ${{ secrets.DOCKER_TOKEN }}
    platforms: linux/amd64,linux/arm64
    dockerfile: docker/Dockerfile
    push: "true"
```

**Key inputs**

| Input | Default | Description |
|---|---|---|
| `registry` | `docker.io` | Docker registry host |
| `image-name` | — | Full image name (required) |
| `username` | — | Registry username (required) |
| `password` | — | Registry password / token (required) |
| `dockerfile` | `Dockerfile` | Path to Dockerfile |
| `context` | `.` | Build context path |
| `platforms` | `linux/amd64` | Comma-separated target platforms |
| `push` | `true` | Push after build |
| `tags` | `""` | Custom tags (one per line); auto-generated if empty |
| `build-args` | `""` | `KEY=VALUE` build arguments |
| `target` | `""` | Multi-stage build target |
| `cache-from` | auto | Cache source |
| `cache-to` | auto | Cache destination |

**Outputs:** `image-id`, `digest`, `tags`, `labels`

---

### `ssh-deploy`

> Deploy to a server over SSH. Supports key-based auth and Tailscale SSH, `git pull`, Docker Compose orchestration (pull-only, build, or pre-built image strategies), secret injection, and pre/post hooks.

```yaml
- uses: nuniesmith/actions/.github/actions/ssh-deploy@v1
  with:
    host: ${{ secrets.PROD_TAILSCALE_IP }}
    username: actions
    ssh-key: ${{ secrets.PROD_SSH_KEY }}
    project-path: ~/myapp
    git-pull: "true"
    git-branch: main
    build-strategy: pull        # pull | build | none
    compose-files: docker-compose.yml
    app-services: web api
    docker-prune: "true"
```

**Key inputs**

| Input | Default | Description |
|---|---|---|
| `host` | — | SSH hostname or IP (required) |
| `port` | `22` | SSH port |
| `username` | — | SSH user (required) |
| `ssh-key` | `""` | SSH private key |
| `password` | `""` | SSH password (if no key) |
| `use-tailscale-ssh` | `false` | Use Tailscale SSH instead of standard SSH |
| `project-path` | — | Remote project path (required) |
| `git-pull` | `true` | Run `git pull` before deploy |
| `git-branch` | `main` | Branch to pull |
| `build-strategy` | `pull` | `pull` (pre-built), `build` (build on server), `none` |
| `compose-files` | `docker-compose.yml` | Compose file(s) |
| `app-services` | `""` | Services to restart |
| `infra-services` | `""` | Infrastructure services (restarted separately) |
| `pre-deploy-command` | `""` | Command to run before deploy |
| `post-deploy-command` | `""` | Command to run after deploy |
| `docker-prune` | `true` | Run `docker system prune` |
| `env-inject-secrets` | `""` | Newline-separated `KEY=VALUE` secrets to write to `.env` |
| `ssh-retries` | `3` | SSH connection retry count |

**Outputs:** `deployed`, `ssh-method`, `services-started`, `build-strategy-used`

---

### `tailscale-connect`

> Join the Tailscale network and optionally verify connectivity + SSH reachability to a target host before deployment.

```yaml
- uses: nuniesmith/actions/.github/actions/tailscale-connect@v1
  with:
    oauth-client-id: ${{ secrets.TAILSCALE_OAUTH_CLIENT_ID }}
    oauth-secret: ${{ secrets.TAILSCALE_OAUTH_SECRET }}
    target-ip: ${{ secrets.PROD_TAILSCALE_IP }}
    target-ssh-port: "22"
    tags: tag:ci
```

**Outputs:** `connected`, `tailscale-ip`, `target-reachable`, `ssh-reachable`

Tailscale is automatically logged out in a cleanup step that runs on `always()`.

---

### `health-check`

> Verify deployment health via HTTP endpoints, Docker container status, and arbitrary custom commands. Supports local and remote (SSH) checks with configurable retry logic.

```yaml
- uses: nuniesmith/actions/.github/actions/health-check@v1
  with:
    endpoints: |
      [
        {"url": "https://myapp.example.com/health", "expected_status": 200},
        {"url": "https://myapp.example.com/ready",  "expected_status": 200, "timeout": 15}
      ]
    containers: "web api redis"
    initial-delay: "30"
    retry-count: "5"
    retry-delay: "10"
    fail-on-unhealthy: "true"
```

**Remote server checks**

```yaml
- uses: nuniesmith/actions/.github/actions/health-check@v1
  with:
    ssh-host: ${{ secrets.PROD_TAILSCALE_IP }}
    ssh-user: actions
    ssh-key: ${{ secrets.PROD_SSH_KEY }}
    containers: "web api"
    custom-command: "cd ~/myapp && docker compose exec api healthcheck.sh"
```

**Outputs:** `healthy`, `endpoints-healthy`, `containers-healthy`, `failed-checks`

---

### `discord-notify`

> Send rich embed notifications to a Discord webhook with automatic status-based colouring, repo info fields, and retry on 429 rate limits.

```yaml
- uses: nuniesmith/actions/.github/actions/discord-notify@v1
  with:
    webhook-url: ${{ secrets.DISCORD_WEBHOOK }}
    title: "🚀 Deployed to production"
    description: "Version `${{ github.sha }}` is live."
    status: success             # success | failure | warning | info | started
    include-repo-info: "true"
    fields: |
      [
        {"name": "Environment", "value": "production", "inline": true},
        {"name": "Actor",       "value": "${{ github.actor }}", "inline": true}
      ]
```

**Status colours**

| Status | Colour |
|---|---|
| `success` | Green |
| `failure` | Red |
| `warning` | Yellow |
| `started` / `info` | Blue |

**Outputs:** `sent` (`true`/`false`)

---

### `cloudflare-dns-update`

> Create or update Cloudflare DNS A records (or any record type). Supports updating multiple records in a single step. Validates IPv4 format before calling the API.

```yaml
- uses: nuniesmith/actions/.github/actions/cloudflare-dns-update@v1
  with:
    api-token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
    zone-id: ${{ secrets.CLOUDFLARE_ZONE_ID }}
    record-name: myapp.example.com
    record-content: ${{ steps.tailscale.outputs.tailscale-ip }}
    proxied: "false"
```

**Updating multiple records**

```yaml
    additional-records: |
      [
        {"name": "www.example.com",  "content": "1.2.3.4"},
        {"name": "api.example.com",  "content": "1.2.3.4"}
      ]
```

**Outputs:** `updated`, `record-id`, `records-updated`

---

### `ssl-certbot-cloudflare`

> Issue Let's Encrypt certificates via Certbot with the Cloudflare DNS-01 challenge, with an optional self-signed fallback and automatic deployment to a remote server via SSH (host filesystem or Docker volume).

```yaml
- uses: nuniesmith/actions/.github/actions/ssl-certbot-cloudflare@v1
  with:
    domain: myapp.example.com
    additional-domains: "www.myapp.example.com"
    cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
    email: admin@example.com
    fallback-to-self-signed: "true"   # Issue self-signed cert if Certbot fails
    deploy-to-server: "true"
    ssh-host: ${{ secrets.PROD_IP }}
    ssh-user: actions
    ssh-key: ${{ secrets.PROD_SSH_KEY }}
    docker-volume-name: my_ssl_certs  # Deploy into a Docker volume
```

**Outputs:** `cert-ready`, `cert-type` (`letsencrypt`/`self-signed`), `cert-path`, `expiry-date`, `cert-source`, `deployed`

---

### `ssl-check`

> Inspect an existing TLS certificate on a remote server (Docker volume or host filesystem) and report validity, days remaining, and whether renewal is needed. Designed to gate `ssl-certbot-cloudflare` so certificates are only re-issued when actually expiring.

```yaml
- id: ssl
  uses: nuniesmith/actions/.github/actions/ssl-check@v1
  with:
    ssh-host: ${{ secrets.PROD_IP }}
    ssh-key: ${{ secrets.PROD_SSH_KEY }}
    domain: myapp.example.com
    renewal-threshold-days: "30"

- name: 🔐 Renew SSL if needed
  if: steps.ssl.outputs.skip-generation != 'true'
  uses: nuniesmith/actions/.github/actions/ssl-certbot-cloudflare@v1
  with:
    domain: myapp.example.com
    cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
    email: admin@example.com
```

**Outputs:** `cert-exists`, `cert-type`, `days-remaining`, `total-days`, `pct-used`, `expiry-date`, `needs-renewal`, `skip-generation`, `issuer`, `cert-source`

---

### `latex-setup`

> Install and cache TeX Live with a configurable package set. Supports `small`, `medium`, `full`, and `custom` schemes with individual package selection via `tlmgr`.

```yaml
- uses: nuniesmith/actions/.github/actions/latex-setup@v1
  with:
    scheme: custom              # small | medium | full | custom
    install-biber: "true"       # For biblatex
    install-chktex: "true"      # For latex-lint
    install-latexmk: "true"
    extra-packages: "pgf tikz-cd"
    cache-enabled: "true"
```

**Outputs:** `texlive-version`, `cache-hit`, `install-path`

---

### `latex-lint`

> Run LaTeX quality checks: `chktex`, `lacheck`, and built-in custom rules (TODO detection, overlong lines, encoding, missing bibliography entries).

```yaml
- uses: nuniesmith/actions/.github/actions/latex-lint@v1
  with:
    working-directory: papers/
    run-chktex: "true"
    run-lacheck: "true"
    run-custom-checks: "true"
    check-bibliography: "true"
    fail-on-warnings: "false"
```

**Outputs:** `chktex-warnings`, `lacheck-warnings`, `custom-warnings`, `total-warnings`, `lint-result`

---

### `latex-build`

> Compile LaTeX documents to PDF. Supports `pdflatex`, `xelatex`, and `lualatex` engines, automatic bibliography processing (`bibtex`/`biber`), multi-pass compilation, and `latexmk` mode.

```yaml
- id: build
  uses: nuniesmith/actions/.github/actions/latex-build@v1
  with:
    working-directory: papers/
    engine: pdflatex            # pdflatex | xelatex | lualatex
    bib-engine: auto            # auto | bibtex | biber | none
    compile-passes: "2"
    halt-on-error: "true"
    clean-aux: "true"
    keep-log-on-failure: "true"
    output-directory: dist/

# Advanced — latexmk with XeLaTeX
- uses: nuniesmith/actions/.github/actions/latex-build@v1
  with:
    engine: xelatex
    latexmk: "true"
    shell-escape: "true"
    fail-on-warnings: "false"
```

**Outputs:** `pdf-count`, `fail-count`, `pdf-files`, `total-warnings`, `build-result`

**Full LaTeX pipeline example**

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: nuniesmith/actions/.github/actions/latex-setup@v1
    with:
      scheme: custom
      install-biber: "true"
      install-chktex: "true"

  - uses: nuniesmith/actions/.github/actions/latex-lint@v1
    with:
      run-chktex: "true"
      check-bibliography: "true"

  - id: build
    uses: nuniesmith/actions/.github/actions/latex-build@v1
    with:
      engine: pdflatex
      bib-engine: auto
      clean-aux: "true"

  - uses: actions/upload-artifact@v4
    with:
      name: pdfs
      path: ${{ steps.build.outputs.pdf-files }}
```

---

### `llm-audit`

> Run an LLM-powered code audit against a directory of source files. Supports xAI (Grok), Anthropic (Claude), and Google (Gemini) as providers and outputs a structured JSON report with severity-ranked findings.

```yaml
- uses: nuniesmith/actions/.github/actions/llm-audit@v1
  with:
    provider: xai               # xai | anthropic | google
    audit-mode: regular         # regular | full
    source-path: ./src
    file-patterns: "*.rs *.toml"
    xai-api-key: ${{ secrets.XAI_API_KEY }}
    commit-results: "false"
    upload-artifacts: "true"
```

**Outputs:** `audit-completed`, `files-audited`, `issues-found`, `critical-issues`, `high-issues`, `report-path`

For the full multi-mode workflow (todo-analyze → todo-plan → todo-work → todo-review), see `.github/repos/rustassistant/llm-audit.yml`.

---

### `kotlin-ci`

> Kotlin Multiplatform CI pipeline using Gradle: detekt linting, build, unit tests, JUnit report publishing, and test-failure threshold enforcement.

```yaml
- uses: nuniesmith/actions/.github/actions/kotlin-ci@v1
  with:
    java-version: "21"
    test-module: ":shared"
    test-task: testDebugUnitTest
    build-task: assemble
    run-detekt: "true"
    known-test-failures: "0"    # Allow N expected failures before failing CI
    upload-test-results: "true"
```

**Outputs:** `build-result`, `test-result`, `detekt-result`, `total-tests`, `failed-tests`, `passed-tests`

---

## Workflow Templates

Ready-to-use workflow files in `.github/templates/`. Copy one to `.github/workflows/ci-cd.yml` in your project and edit the `env:` block.

| Template | Stack | What it covers |
|---|---|---|
| `rust-project.yml` | Rust | fmt, clippy, tests, coverage, security audit, Docker build, SSH deploy |
| `kotlin-project.yml` | Kotlin / KMP | Java setup, Gradle build, detekt, unit tests, JUnit reports |
| `nodejs-project.yml` | Node.js / TypeScript | npm/yarn/pnpm, lint, test, build, Docker |
| `python-project.yml` | Python | pip/poetry/pipenv, lint, pytest, Docker |
| `latex-project.yml` | LaTeX | TeX Live setup, chktex lint, multi-engine build, PDF artifacts |
| `simple-deploy.yml` | Any | Tailscale + SSH deploy only — no build steps |
| `soak-test.yml` | Any | Long-running scheduled test with Discord reporting |

---

## Per-Repo Workflows

Production workflow files maintained here and synced into each target repository:

| Path | Target repo | Covers |
|---|---|---|
| `repos/rustassistant/ci-cd.yml` | `nuniesmith/rustassistant` | Rust CI → Docker → Raspberry Pi deploy |
| `repos/rustassistant/llm-audit.yml` | `nuniesmith/rustassistant` | Full LLM audit suite (analyze / plan / work / review) |
| `repos/fks/ci-cd.yml` | `nuniesmith/fks` | CI + deploy |
| `repos/fks/ssl-renew.yml` | `nuniesmith/fks` | Scheduled SSL certificate renewal |
| `repos/freddy/ci-cd.yml` | `nuniesmith/freddy` | CI + deploy |
| `repos/sullivan/ci-cd.yml` | `nuniesmith/sullivan` | CI + deploy |
| `repos/futures/ci-cd.yml` | `nuniesmith/futures` | CI + deploy |
| `repos/technical_papers/ci-cd.yml` | `nuniesmith/technical_papers` | LaTeX build + PDF artifact publish |

To apply changes: copy the file from this repo into the target repo's `.github/workflows/` directory.

---

## Versioning

This repo uses semantic versioning with both floating major tags (`v1`) and pinned exact tags (`v1.2.3`).

| Reference | Behaviour |
|---|---|
| `@v1` | Floating — always the latest `v1.x.x` patch/minor. Recommended for most use. |
| `@v1.2.3` | Pinned — never changes. Use for regulated or reproducible builds. |
| `@main` | Floating branch — may receive breaking changes. Avoid in production. |

### Creating a release

```bash
# Dry-run first
./scripts/release.sh 1.2.0 --dry-run

# Publish
./scripts/release.sh 1.2.0
```

This tags `v1.2.0` and force-moves the `v1` floating tag. See `docs/VERSIONING.md` for full guidance including major-version migration guide templates.

---

## Required Secrets

Secrets are configured at the organisation or repository level. Not every workflow needs all of them.

| Secret | Used by | Description |
|---|---|---|
| `GH_PAT` | `llm-audit.yml` | GitHub PAT for cloning private repos and opening PRs |
| `DOCKER_USERNAME` | `docker-build-push` | Docker Hub username |
| `DOCKER_TOKEN` | `docker-build-push` | Docker Hub access token |
| `TAILSCALE_OAUTH_CLIENT_ID` | `tailscale-connect` | Tailscale OAuth client ID |
| `TAILSCALE_OAUTH_SECRET` | `tailscale-connect` | Tailscale OAuth secret |
| `PROD_TAILSCALE_IP` | deploy workflows | Tailscale IP of production server |
| `PROD_SSH_KEY` | `ssh-deploy`, `health-check`, `ssl-*` | SSH private key for the deploy user |
| `PROD_SSH_USER` | deploy workflows | SSH username (typically `actions`) |
| `PROD_SSH_PORT` | deploy workflows | SSH port (typically `22`) |
| `CLOUDFLARE_API_TOKEN` | `cloudflare-dns-update`, `ssl-certbot-cloudflare` | Cloudflare API token with DNS edit permission |
| `CLOUDFLARE_ZONE_ID` | `cloudflare-dns-update` | Cloudflare Zone ID |
| `DISCORD_WEBHOOK` | `discord-notify` | Discord webhook URL |
| `XAI_API_KEY` | `llm-audit` | xAI (Grok) API key |
| `ANTHROPIC_API_KEY` | `llm-audit` | Anthropic (Claude) API key |
| `GOOGLE_API_KEY` | `llm-audit` | Google (Gemini) API key |
| `CODECOV_TOKEN` | `rust-project.yml` template | Codecov upload token (optional) |

### Bootstrap a new server

```bash
# Generate all secrets for a fresh host and print them for copying into GitHub
./scripts/generate-secrets.sh

# Interactive guided setup over SSH
./scripts/setup-prod-server.sh
```

---

## License

MIT — see [LICENSE](./LICENSE).