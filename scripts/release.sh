#!/usr/bin/env bash
# =============================================================================
# Release Script for nuniesmith/actions
# =============================================================================
# This script creates versioned releases of composite actions using Git tags.
#
# Usage:
#   ./scripts/release.sh <version> [--dry-run]
#
# Examples:
#   ./scripts/release.sh 1.0.0          # Creates v1.0.0 and updates v1 tag
#   ./scripts/release.sh 1.2.0 --dry-run # Shows what would happen
#   ./scripts/release.sh 2.0.0          # Creates v2.0.0 and new v2 tag
#
# Versioning Strategy:
#   - Full version tags: v1.0.0, v1.1.0, v1.2.3 (immutable)
#   - Major version tags: v1, v2, v3 (floating, always points to latest)
#   - Users reference @v1 to get latest stable v1.x.x
#   - Users reference @v1.2.3 to pin to exact version
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
DRY_RUN=false
VERSION=""

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

usage() {
    cat << EOF
Usage: $(basename "$0") <version> [options]

Arguments:
    version     Semantic version (e.g., 1.0.0, 1.2.3, 2.0.0-beta.1)

Options:
    --dry-run   Show what would happen without making changes
    -h, --help  Show this help message

Examples:
    $(basename "$0") 1.0.0              # Release v1.0.0
    $(basename "$0") 1.2.0 --dry-run    # Preview release
    $(basename "$0") 2.0.0              # Major version bump

EOF
    exit 1
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

validate_version() {
    local version="$1"
    # Validate semantic versioning (with optional pre-release)
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        log_error "Invalid version format: $version. Use semantic versioning (e.g., 1.0.0, 2.1.0-beta.1)"
    fi
}

extract_major_version() {
    local version="$1"
    echo "${version%%.*}"
}

check_git_status() {
    cd "$REPO_ROOT"

    # Check if we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository"
    fi

    # Check for uncommitted changes
    if [[ -n $(git status --porcelain) ]]; then
        log_error "Working directory has uncommitted changes. Commit or stash them first."
    fi

    # Check if on main branch
    local current_branch
    current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "main" ]]; then
        log_warn "Not on main branch (currently on: $current_branch)"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_tag_exists() {
    local tag="$1"
    if git rev-parse "refs/tags/$tag" > /dev/null 2>&1; then
        return 0
    fi
    return 1
}

create_release() {
    local version="$1"
    local full_tag="v$version"
    local major_version
    major_version=$(extract_major_version "$version")
    local major_tag="v$major_version"

    cd "$REPO_ROOT"

    echo ""
    echo "=========================================="
    echo " Release: $full_tag"
    echo "=========================================="
    echo ""

    # Check if full version tag already exists
    if check_tag_exists "$full_tag"; then
        log_error "Tag $full_tag already exists. Choose a different version."
    fi

    # Show what will happen
    log_info "Full version tag: $full_tag (new)"
    if check_tag_exists "$major_tag"; then
        log_info "Major version tag: $major_tag (will be updated)"
    else
        log_info "Major version tag: $major_tag (new)"
    fi

    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN - No changes will be made"
        echo ""
        echo "Would execute:"
        echo "  git tag -a $full_tag -m \"Release $full_tag\""
        echo "  git tag -fa $major_tag -m \"Update $major_tag to $full_tag\""
        echo "  git push origin $full_tag"
        echo "  git push origin $major_tag --force"
        echo ""
        return
    fi

    # Confirm release
    echo "This will:"
    echo "  1. Create tag $full_tag"
    echo "  2. Update tag $major_tag to point to this commit"
    echo "  3. Push both tags to origin"
    echo ""
    read -p "Proceed with release? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Release cancelled"
        exit 0
    fi

    echo ""

    # Create full version tag
    log_info "Creating tag $full_tag..."
    git tag -a "$full_tag" -m "Release $full_tag"
    log_success "Created tag $full_tag"

    # Create/update major version tag
    log_info "Updating tag $major_tag..."
    git tag -fa "$major_tag" -m "Update $major_tag to $full_tag"
    log_success "Updated tag $major_tag"

    # Push tags
    log_info "Pushing tags to origin..."
    git push origin "$full_tag"
    git push origin "$major_tag" --force
    log_success "Pushed tags to origin"

    echo ""
    echo "=========================================="
    log_success "Release $full_tag complete!"
    echo "=========================================="
    echo ""
    echo "Users can now reference your actions as:"
    echo ""
    echo "  # Latest $major_tag.x.x (recommended)"
    echo "  uses: nuniesmith/actions/.github/actions/ACTION_NAME@$major_tag"
    echo ""
    echo "  # Pinned to exact version"
    echo "  uses: nuniesmith/actions/.github/actions/ACTION_NAME@$full_tag"
    echo ""
}

list_releases() {
    cd "$REPO_ROOT"

    echo ""
    echo "Current releases:"
    echo ""

    # List all version tags
    git tag -l "v*" --sort=-v:refname | head -20

    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -l|--list)
            list_releases
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            ;;
        *)
            if [[ -z "$VERSION" ]]; then
                VERSION="$1"
            else
                log_error "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate inputs
if [[ -z "$VERSION" ]]; then
    usage
fi

validate_version "$VERSION"
check_git_status
create_release "$VERSION"
