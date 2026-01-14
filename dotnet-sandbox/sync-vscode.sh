#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Sync VS Code settings and extensions to Docker volume
# ==============================================================================
#
# Syncs VS Code User settings to dotnet-sandbox-vscode volume for use
# inside the Docker container. Detects host OS automatically.
#
# Usage: sync-vscode.sh [options]
#   --dry-run    Show what would be done without making changes
#   --help       Show this help message
#
# Exit codes:
#   0 - Success (or VS Code not installed)
#   1 - Error (permission denied, docker failure, etc.)
# ==============================================================================

# Constants
readonly VOLUME_NAME="dotnet-sandbox-vscode"

# Color output helpers (consistent with sync-plugins.sh)
info() { echo "INFO: $*"; }
success() { echo "OK: $*"; }
error() { echo "ERROR: $*" >&2; }
warn() { echo "WARN: $*"; }
step() { echo "-> $*"; }

# Parse arguments
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
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

# Detect host OS and set VS Code paths
detect_vscode_paths() {
    local os_type
    os_type="$(uname -s)"

    case "$os_type" in
        Darwin)
            # macOS
            VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
            CODE_CMD="code"
            ;;
        Linux)
            # Check if running in WSL
            if grep -qi microsoft /proc/version 2>/dev/null; then
                # WSL - need to find Windows username
                local win_user
                win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || true)
                if [[ -n "$win_user" ]]; then
                    VSCODE_USER_DIR="/mnt/c/Users/$win_user/AppData/Roaming/Code/User"
                else
                    # Fallback: try common paths
                    VSCODE_USER_DIR=""
                    for user_dir in /mnt/c/Users/*/AppData/Roaming/Code/User; do
                        if [[ -d "$user_dir" ]]; then
                            VSCODE_USER_DIR="$user_dir"
                            break
                        fi
                    done
                    # If no Windows paths found, try Linux path as last resort
                    if [[ -z "$VSCODE_USER_DIR" ]]; then
                        VSCODE_USER_DIR="$HOME/.config/Code/User"
                    fi
                fi
                CODE_CMD="code"
            else
                # Native Linux
                VSCODE_USER_DIR="$HOME/.config/Code/User"
                CODE_CMD="code"
            fi
            ;;
        *)
            error "Unsupported OS: $os_type"
            exit 1
            ;;
    esac
}

# Check if VS Code is installed (distinguishes missing from permission errors)
check_vscode_installed() {
    # First check if path exists at all
    if [[ ! -e "$VSCODE_USER_DIR" ]]; then
        info "VS Code not installed or no settings found at: $VSCODE_USER_DIR"
        info "Skipping VS Code sync"
        exit 0
    fi

    # Path exists - check if it's a directory and accessible
    if [[ ! -d "$VSCODE_USER_DIR" ]]; then
        error "Path exists but is not a directory: $VSCODE_USER_DIR"
        exit 1
    fi

    if [[ ! -r "$VSCODE_USER_DIR" ]]; then
        error "Permission denied reading VS Code settings: $VSCODE_USER_DIR"
        exit 1
    fi
}

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

    # Create volume if it doesn't exist
    if ! docker volume inspect "$VOLUME_NAME" &>/dev/null; then
        warn "Volume does not exist, creating: $VOLUME_NAME"
        if ! $DRY_RUN; then
            docker volume create "$VOLUME_NAME"
        fi
    fi

    success "Prerequisites OK"
}

# Sync settings files (settings.json, keybindings.json)
sync_settings_files() {
    step "Syncing settings files..."

    local files_to_sync=("settings.json" "keybindings.json")
    local synced=0

    for file in "${files_to_sync[@]}"; do
        local src="$VSCODE_USER_DIR/$file"
        if [[ -f "$src" ]]; then
            if $DRY_RUN; then
                echo "  [dry-run] Would sync: $file"
            else
                # Create Data/User directory structure in volume (matches VS Code Server layout)
                docker run --rm \
                    -v "$VOLUME_NAME":/target \
                    -v "$src":/source:ro \
                    alpine sh -c "
                        mkdir -p /target/data/User
                        cp /source /target/data/User/$file
                        chown -R 1000:1000 /target/data
                    "
                info "Synced: $file"
            fi
            ((synced++)) || true
        else
            info "Not found (skipping): $file"
        fi
    done

    if [[ $synced -eq 0 ]]; then
        warn "No settings files found to sync"
    else
        success "Synced $synced settings file(s)"
    fi
}

# Sync extensions list
sync_extensions_list() {
    step "Syncing extensions list..."

    if ! command -v "$CODE_CMD" &>/dev/null; then
        # VS Code settings dir exists but CLI not in PATH - this is an error
        error "VS Code CLI ($CODE_CMD) not in PATH"
        error "Please ensure VS Code is installed and 'code' command is available"
        error "On macOS: Open VS Code > Cmd+Shift+P > 'Shell Command: Install code command'"
        exit 1
    fi

    if $DRY_RUN; then
        local count
        count=$("$CODE_CMD" --list-extensions 2>/dev/null | wc -l || echo "0")
        echo "  [dry-run] Would sync $count extensions to list"
        return
    fi

    # Get extensions list - capture exit code and stderr for proper error handling
    local extensions_list
    local exit_code=0
    extensions_list=$("$CODE_CMD" --list-extensions 2>&1) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        error "Failed to list extensions (exit code $exit_code): $extensions_list"
        exit 1
    fi

    if [[ -z "$extensions_list" ]]; then
        info "No extensions installed"
        return
    fi

    # Write extensions list to volume
    printf '%s\n' "$extensions_list" | docker run --rm -i \
        -v "$VOLUME_NAME":/target \
        alpine sh -c "
            mkdir -p /target/data
            cat > /target/data/extensions.txt
            chown -R 1000:1000 /target/data
        "

    local count
    count=$(printf '%s\n' "$extensions_list" | wc -l)
    success "Synced extensions list ($count extensions)"
}

# Show summary
show_summary() {
    echo ""
    echo "================================================================"
    success "VS Code sync complete!"
    echo "================================================================"
    echo ""
    echo "  Volume: $VOLUME_NAME"
    echo "  Source: $VSCODE_USER_DIR"
    echo ""
    echo "Files synced to volume at data/User/:"
    echo "  - settings.json"
    echo "  - keybindings.json"
    echo "  - extensions.txt (list only)"
    echo ""
}

# Main
main() {
    echo "================================================================"
    info "Syncing VS Code settings to Docker volume"
    echo "================================================================"
    echo ""

    if $DRY_RUN; then
        warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    detect_vscode_paths
    check_vscode_installed
    check_prerequisites
    echo ""

    sync_settings_files
    sync_extensions_list

    if ! $DRY_RUN; then
        show_summary
    else
        echo ""
        success "[dry-run] All checks passed. Run without --dry-run to apply changes."
    fi
}

main "$@"
