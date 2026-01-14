# 📋 Workflow Templates

Ready-to-use CI/CD workflow templates for different project types. These templates use the reusable composite actions from this repository.

## Available Templates

| Template | Description | Language/Framework |
|----------|-------------|-------------------|
| [rust-project.yml](./rust-project.yml) | Complete Rust CI/CD with Docker & deploy | Rust |
| [kotlin-project.yml](./kotlin-project.yml) | Kotlin/KMP CI with multi-platform builds | Kotlin, KMP |
| [nodejs-project.yml](./nodejs-project.yml) | Node.js/TypeScript CI with npm/yarn/pnpm | Node.js, TypeScript |
| [python-project.yml](./python-project.yml) | Python CI with pip/poetry/pipenv | Python |
| [simple-deploy.yml](./simple-deploy.yml) | Minimal deployment-only workflow | Any |

---

## Quick Start

### 1. Choose a Template

Select the template that matches your project type.

### 2. Copy to Your Repository

```bash
# Example: Copy Rust template
curl -o .github/workflows/ci-cd.yml \
  https://raw.githubusercontent.com/nuniesmith/actions/main/.github/templates/rust-project.yml
```

Or manually copy the file to `.github/workflows/ci-cd.yml` in your repository.

### 3. Customize Environment Variables

Each template has an `env:` section at the top. Edit these values for your project:

```yaml
env:
  # Project settings
  PROJECT_NAME: my-project          # Your project name
  
  # Docker settings (leave empty to skip)
  DOCKER_IMAGE: myuser/my-project   # Docker Hub image name
  
  # Deployment settings
  DEPLOY_PATH: ~/my-project         # Path on server
```

### 4. Add Required Secrets

Go to your repository's **Settings → Secrets and variables → Actions** and add the required secrets.

---

## Required Secrets

### Minimum (for CI only)

No secrets required! The workflows will run tests without any configuration.

### For Docker Builds

| Secret | Description |
|--------|-------------|
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_TOKEN` | Docker Hub access token |

### For Deployment via Tailscale

| Secret | Description |
|--------|-------------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth Client ID |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth Secret |
| `PROD_TAILSCALE_IP` | Server's Tailscale IP (100.x.x.x) |
| `PROD_SSH_KEY` | SSH private key for `actions` user |
| `PROD_SSH_USER` | SSH username (default: `actions`) |
| `PROD_SSH_PORT` | SSH port (default: `22`) |

### Optional Enhancements

| Secret | Description |
|--------|-------------|
| `DISCORD_WEBHOOK` | Discord webhook for notifications |
| `CODECOV_TOKEN` | Codecov token for coverage reports |

---

## Template Features

### 🦀 Rust Template (`rust-project.yml`)

- **Stages**: Test → Security Audit → Docker Build → Deploy
- **Features**:
  - Formatting check with `rustfmt`
  - Linting with `clippy`
  - Unit and integration tests
  - Code coverage with `cargo-tarpaulin`
  - Security audit with `cargo-audit`
  - Multi-arch Docker builds
  - Tailscale SSH deployment

### 🎯 Kotlin Template (`kotlin-project.yml`)

- **Stages**: Test → Build Platforms → Docker → Publish → Deploy
- **Features**:
  - Detekt linting
  - JUnit test reporting
  - Multi-platform builds (Android, JVM, iOS, JS)
  - Maven publishing support
  - Known test failure threshold
  - Gradle caching

### 📦 Node.js Template (`nodejs-project.yml`)

- **Stages**: Test → E2E → Security → Docker → NPM Publish → Deploy
- **Features**:
  - Support for npm, yarn, and pnpm
  - ESLint/TypeScript checking
  - Jest/Vitest testing with coverage
  - Playwright/Cypress E2E support
  - npm audit security scanning
  - NPM registry publishing

### 🐍 Python Template (`python-project.yml`)

- **Stages**: Lint → Test → Security → Docker → PyPI Publish → Deploy
- **Features**:
  - Support for pip, poetry, and pipenv
  - Ruff/flake8/pylint linting
  - mypy type checking
  - pytest with coverage
  - Multi-version Python testing
  - pip-audit, safety, bandit security
  - PyPI/TestPyPI publishing

### 🚀 Simple Deploy Template (`simple-deploy.yml`)

- **Stages**: Connect → Deploy
- **Features**:
  - Minimal configuration
  - Manual trigger with environment selection
  - Git pull or deploy current state
  - Docker Compose deployment

---

## Customization Guide

### Skip Certain Stages

Set environment variables to skip stages:

```yaml
env:
  RUN_LINT: "false"      # Skip linting
  RUN_TESTS: "false"     # Skip tests
  DOCKER_IMAGE: ""       # Skip Docker build (empty string)
```

### Enable Deployment

Deployment is disabled by default. To enable:

1. Add a repository variable `ENABLE_DEPLOY` with value `true`
2. Configure deployment secrets (Tailscale, SSH)

### Add Custom Steps

Add steps after the reusable actions:

```yaml
- name: 🦀 Run Rust CI
  uses: nuniesmith/actions/.github/actions/rust-ci@main
  with:
    toolchain: stable

- name: 📝 Custom Step
  run: |
    echo "Add your custom logic here"
```

### Change Notification Style

Customize Discord notifications:

```yaml
- name: 📣 Custom notification
  uses: nuniesmith/actions/.github/actions/discord-notify@main
  with:
    webhook-url: ${{ secrets.DISCORD_WEBHOOK }}
    title: "🎉 Custom Title"
    description: "Your message here"
    status: success
    fields: '[{"name": "Custom Field", "value": "Custom Value", "inline": true}]'
```

---

## Enabling Features

### Code Coverage (Codecov)

1. Sign up at [codecov.io](https://codecov.io)
2. Add `CODECOV_TOKEN` secret
3. Coverage is automatically uploaded when the secret exists

### Discord Notifications

1. Create a webhook in your Discord server
2. Add `DISCORD_WEBHOOK` secret
3. Notifications are automatically sent when the secret exists

### Deployment Protection

1. Go to **Settings → Environments**
2. Create a `production` environment
3. Add protection rules:
   - Required reviewers
   - Wait timer
   - Restrict to specific branches

---

## Troubleshooting

### Workflow Not Triggering

- Check that the workflow file is in `.github/workflows/`
- Verify the branch names in `on.push.branches` match your branches
- Check `paths-ignore` isn't excluding your changes

### Docker Build Fails

- Ensure `DOCKER_USERNAME` and `DOCKER_TOKEN` secrets are set
- Verify the Dockerfile path is correct
- Check that the image name doesn't contain invalid characters

### Deployment Fails

- Verify Tailscale secrets are correct
- Check that the server is connected to Tailscale
- Ensure the `actions` user exists and has SSH access
- Verify the SSH key matches the one on the server

### Tests Skip Unexpectedly

- Check the `if:` conditions on jobs
- Verify `inputs.skip_tests` isn't set to `true`
- Check that dependent jobs didn't fail

---

## Getting Help

- [Actions README](../../actions/README.md) - Documentation for individual actions
- [Setup Server Workflow](../workflows/setup-server.yml) - Server provisioning
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

---

## Contributing

To add a new template:

1. Create the template file in this directory
2. Follow the existing template structure
3. Include comprehensive comments
4. Update this README with the new template
5. Test the template in a real repository