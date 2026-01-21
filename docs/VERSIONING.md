# Versioning Guide for nuniesmith/actions

This repository uses **semantic versioning** with Git tags to provide stable, versioned releases of composite actions.

## Version Format

We follow [Semantic Versioning](https://semver.org/):

```
MAJOR.MINOR.PATCH

Example: 1.2.3
```

- **MAJOR**: Breaking changes (incompatible API changes)
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes (backwards compatible)

## How to Reference Actions

### Recommended: Major Version Tag (floating)

```yaml
uses: nuniesmith/actions/.github/actions/tailscale-connect@v1
```

This always gets the latest `v1.x.x` release. You get bug fixes and new features automatically while maintaining compatibility.

### Pinned: Exact Version Tag

```yaml
uses: nuniesmith/actions/.github/actions/tailscale-connect@v1.2.3
```

Use this when you need reproducible builds or are in a regulated environment.

### Not Recommended: Branch Reference

```yaml
uses: nuniesmith/actions/.github/actions/tailscale-connect@main
```

⚠️ **Avoid this in production** - `@main` can change at any time and may introduce breaking changes.

## Tag Structure

| Tag | Type | Description |
|-----|------|-------------|
| `v1.0.0` | Immutable | Exact version, never changes |
| `v1.2.3` | Immutable | Exact version, never changes |
| `v1` | Floating | Always points to latest `v1.x.x` |
| `v2` | Floating | Always points to latest `v2.x.x` |

## Creating a Release

### Using the Release Script

```bash
# Preview what would happen
./scripts/release.sh 1.0.0 --dry-run

# Create a release
./scripts/release.sh 1.0.0

# Create a minor release
./scripts/release.sh 1.1.0

# Create a major release (breaking changes)
./scripts/release.sh 2.0.0

# List existing releases
./scripts/release.sh --list
```

### Manual Release Process

```bash
# Ensure you're on main with no uncommitted changes
git checkout main
git pull origin main

# Create the full version tag
git tag -a v1.2.0 -m "Release v1.2.0"

# Update the major version tag
git tag -fa v1 -m "Update v1 to v1.2.0"

# Push both tags
git push origin v1.2.0
git push origin v1 --force
```

## When to Bump Versions

### Patch Release (1.0.0 → 1.0.1)
- Bug fixes
- Documentation updates
- Internal refactoring with no behavior change

### Minor Release (1.0.0 → 1.1.0)
- New optional inputs
- New outputs
- New features that don't break existing usage

### Major Release (1.0.0 → 2.0.0)
- Renamed or removed inputs
- Changed default behavior
- Renamed or removed outputs
- Any breaking change

## Migration Guide Template

When releasing a major version, create a migration guide:

```markdown
## Migrating from v1 to v2

### Breaking Changes

1. **Input `old-name` renamed to `new-name`**
   ```yaml
   # Before (v1)
   with:
     old-name: value
   
   # After (v2)
   with:
     new-name: value
   ```

2. **Output `result` format changed**
   - v1: Returns string "true" or "false"
   - v2: Returns JSON object `{"success": true, "message": "..."}`
```

## Current Releases

Run `./scripts/release.sh --list` or check the [releases page](https://github.com/nuniesmith/actions/tags).

## Best Practices

1. **Always test before releasing** - Run workflows that use the actions
2. **Write clear commit messages** - They appear in release notes
3. **Update CHANGELOG.md** - Document what changed
4. **Don't delete tags** - Users may depend on them
5. **Use pre-release tags for testing** - e.g., `v2.0.0-beta.1`
