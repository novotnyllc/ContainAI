#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Sync all host data to Docker volumes
# ==============================================================================
#
# Orchestrates syncing of:
#   - VS Code settings and extensions
#   - VS Code Insiders settings and extensions
#   - GitHub CLI configuration
#
# Usage: sync-all.sh [options]
#   --dry-run    Show what would be done without making changes
#   --help       Show this help message
#
# Exit codes:
#   0 - Success
#   1 - Error (permission denied, docker failure, etc.)
# ==============================================================================

# Get script directory for calling sibling scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Constants
readonly GH_VOLUME_NAME="dotnet-sandbox-gh"

# Color output helpers (consistent with sync-plugins.sh)
info() { echo "INFO: $*"; }
success() { echo "OK: $*"; }
error() { echo "ERROR: $*" >&2; }
warn() { echo "WARN: $*"; }
step() { echo "-> $*"; }

# Parse arguments
DRY_RUN=false
DRY_RUN_FLAG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            DRY_RUN_FLAG="--dry-run"
            shift
            ;;
        --help|-h)
            head -20 "$0" | tail -15
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    step "Checking prerequisites..."

    if ! command -v docker &>/dev/null; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi

    success "Prerequisites OK"
}

# Detect host OS and set gh config path
detect_gh_config_path() {
    local os_type
    os_type="$(uname -s)"

    case "$os_type" in
        Darwin|Linux)
            # Same path for macOS and Linux
            GH_CONFIG_DIR="$HOME/.config/gh"
            ;;
        *)
            error "Unsupported OS: $os_type"
            exit 1
            ;;
    esac
}

# Sync GitHub CLI config
sync_gh_config() {
    step "Syncing GitHub CLI config..."

    if [[ ! -d "$GH_CONFIG_DIR" ]]; then
        info "GitHub CLI not configured (no config at: $GH_CONFIG_DIR)"
        info "Skipping gh sync"
        return
    fi

    # Create volume if it doesn't exist
    if ! docker volume inspect "$GH_VOLUME_NAME" &>/dev/null; then
        warn "Volume does not exist, creating: $GH_VOLUME_NAME"
        if ! $DRY_RUN; then
            docker volume create "$GH_VOLUME_NAME"
        fi
    fi

    if $DRY_RUN; then
        echo "  [dry-run] Would sync gh config from: $GH_CONFIG_DIR"
        return
    fi

    # Sync entire gh config directory
    docker run --rm \
        -v "$GH_VOLUME_NAME":/target \
        -v "$GH_CONFIG_DIR":/source:ro \
        alpine sh -c "
            rm -rf /target/* 2>/dev/null || true
            cp -a /source/. /target/
            chown -R 1000:1000 /target
        "

    success "GitHub CLI config synced"
}

# Sync VS Code (regular)
sync_vscode() {
    echo ""
    echo "================================================================"
    info "Running VS Code sync..."
    echo "================================================================"

    # shellcheck disable=SC2086
    if ! "$SCRIPT_DIR/sync-vscode.sh" $DRY_RUN_FLAG; then
        warn "VS Code sync had issues (continuing anyway)"
    fi
}

# Sync VS Code Insiders
sync_vscode_insiders() {
    echo ""
    echo "================================================================"
    info "Running VS Code Insiders sync..."
    echo "================================================================"

    # shellcheck disable=SC2086
    if ! "$SCRIPT_DIR/sync-vscode-insiders.sh" $DRY_RUN_FLAG; then
        warn "VS Code Insiders sync had issues (continuing anyway)"
    fi
}

# Show summary
show_summary() {
    echo ""
    echo "================================================================"
    success "All syncs complete!"
    echo "================================================================"
    echo ""
    echo "Volumes populated:"
    echo "  - dotnet-sandbox-vscode (VS Code settings)"
    echo "  - dotnet-sandbox-gh (GitHub CLI config)"
    echo ""
    echo "Start sandbox with:"
    echo "  source $SCRIPT_DIR/aliases.sh"
    echo "  csd"
    echo ""
}

# Main
main() {
    echo "================================================================"
    info "Syncing all host data to Docker volumes"
    echo "================================================================"
    echo ""

    if $DRY_RUN; then
        warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    check_prerequisites
    detect_gh_config_path

    # Sync VS Code (regular) - always run, script handles "not installed" case
    sync_vscode

    # Sync VS Code Insiders - always run, script handles "not installed" case
    sync_vscode_insiders

    # Sync gh CLI config
    echo ""
    echo "================================================================"
    info "Syncing GitHub CLI config..."
    echo "================================================================"
    sync_gh_config

    if ! $DRY_RUN; then
        show_summary
    else
        echo ""
        success "[dry-run] All checks passed. Run without --dry-run to apply changes."
    fi
}

main "$@"
