#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Sync all host data to Docker volumes
# ==============================================================================
#
# Orchestrates syncing of:
#   - VS Code settings and extensions
#   - VS Code Insiders settings and extensions (if installed)
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

# Track failures for aggregate exit code
HAD_ERROR=false

# Check prerequisites
check_prerequisites() {
    step "Checking prerequisites..."

    if ! command -v docker &>/dev/null; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        error "jq is not installed (required for JSON processing)"
        exit 1
    fi

    success "Prerequisites OK"
}

# Detect host OS and set paths for VS Code installations
detect_vscode_paths() {
    local os_type
    os_type="$(uname -s)"

    case "$os_type" in
        Darwin)
            # macOS
            VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
            VSCODE_INSIDERS_USER_DIR="$HOME/Library/Application Support/Code - Insiders/User"
            GH_CONFIG_DIR="$HOME/.config/gh"
            ;;
        Linux)
            # Check if running in WSL
            if grep -qi microsoft /proc/version 2>/dev/null; then
                # WSL - need to find Windows username
                local win_user
                win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || true)
                if [[ -n "$win_user" ]]; then
                    VSCODE_USER_DIR="/mnt/c/Users/$win_user/AppData/Roaming/Code/User"
                    VSCODE_INSIDERS_USER_DIR="/mnt/c/Users/$win_user/AppData/Roaming/Code - Insiders/User"
                else
                    # Fallback to Linux paths
                    VSCODE_USER_DIR="$HOME/.config/Code/User"
                    VSCODE_INSIDERS_USER_DIR="$HOME/.config/Code - Insiders/User"
                fi
            else
                # Native Linux
                VSCODE_USER_DIR="$HOME/.config/Code/User"
                VSCODE_INSIDERS_USER_DIR="$HOME/.config/Code - Insiders/User"
            fi
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
        return 0
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
        return 0
    fi

    # Sync entire gh config directory (including dotfiles)
    # Use find to remove all files including hidden ones, then copy fresh
    docker run --rm \
        -v "$GH_VOLUME_NAME":/target \
        -v "$GH_CONFIG_DIR":/source:ro \
        alpine sh -c "
            find /target -mindepth 1 -delete 2>/dev/null || true
            cp -a /source/. /target/
            chown -R 1000:1000 /target
        "

    success "GitHub CLI config synced"
}

# Sync VS Code (regular) - only if installed
sync_vscode() {
    if [[ ! -d "$VSCODE_USER_DIR" ]]; then
        info "VS Code not installed (no settings at: $VSCODE_USER_DIR)"
        info "Skipping VS Code sync"
        return 0
    fi

    echo ""
    echo "================================================================"
    info "Running VS Code sync..."
    echo "================================================================"

    # shellcheck disable=SC2086
    if ! "$SCRIPT_DIR/sync-vscode.sh" $DRY_RUN_FLAG; then
        error "VS Code sync failed"
        HAD_ERROR=true
        return 1
    fi
    return 0
}

# Sync VS Code Insiders - only if installed
sync_vscode_insiders() {
    if [[ ! -d "$VSCODE_INSIDERS_USER_DIR" ]]; then
        info "VS Code Insiders not installed (no settings at: $VSCODE_INSIDERS_USER_DIR)"
        info "Skipping VS Code Insiders sync"
        return 0
    fi

    echo ""
    echo "================================================================"
    info "Running VS Code Insiders sync..."
    echo "================================================================"

    # shellcheck disable=SC2086
    if ! "$SCRIPT_DIR/sync-vscode-insiders.sh" $DRY_RUN_FLAG; then
        error "VS Code Insiders sync failed"
        HAD_ERROR=true
        return 1
    fi
    return 0
}

# Show summary
show_summary() {
    echo ""
    echo "================================================================"
    if $HAD_ERROR; then
        warn "Syncs completed with errors (see above)"
    else
        success "All syncs complete!"
    fi
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
    detect_vscode_paths

    # Sync VS Code (regular) - only if installed
    sync_vscode || true

    # Sync VS Code Insiders - only if installed
    sync_vscode_insiders || true

    # Sync gh CLI config
    echo ""
    echo "================================================================"
    info "Syncing GitHub CLI config..."
    echo "================================================================"
    if ! sync_gh_config; then
        HAD_ERROR=true
    fi

    if ! $DRY_RUN; then
        show_summary
    else
        echo ""
        if $HAD_ERROR; then
            warn "[dry-run] Checks completed with warnings. Review errors above."
        else
            success "[dry-run] All checks passed. Run without --dry-run to apply changes."
        fi
    fi

    # Exit with error if any sync failed
    if $HAD_ERROR; then
        exit 1
    fi
}

main "$@"
