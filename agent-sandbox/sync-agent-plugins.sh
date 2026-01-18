#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Sync Claude Code plugins from host to Docker sandbox
# ==============================================================================
# From: https://github.com/kaldown/dotfiles/blob/macos/.claude/scripts/sandbox/sync-plugins.sh
#
# Syncs plugins, settings, and removes orphan markers so plugins work correctly
# in the Docker sandbox environment.
#
# Usage: sync-plugins.sh [options]
#   --dry-run    Show what would be done without making changes
#   --force      Skip confirmation prompts
#   --help       Show this help message
# ==============================================================================

# Constants
readonly HOST_CLAUDE_PLUGINS_DIR="$HOME/.claude/plugins"
readonly HOST_CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
readonly HOST_CLAUDE_SETTINGS="$HOME/.claude/settings.json"
readonly DATA_VOLUME="sandbox-agent-data"

# User-specific path (auto-detected)
readonly HOST_PATH_PREFIX="$HOME/.claude/plugins/"
readonly CONTAINER_PATH_PREFIX="/home/agent/.claude/plugins/"

# Color output helpers
info() { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
error() { echo "❌ $*" >&2; }
warn() { echo "⚠️  $*"; }
step() { echo "→ $*"; }

# Platform guard - blocks on macOS, allows Linux/WSL only
check_platform() {
    local platform
    platform="$(uname -s)"
    case "$platform" in
        Linux)
            return 0  # Includes WSL
            ;;
        Darwin)
            echo "ERROR: macOS is not supported by sync-agent-plugins.sh yet" >&2
            return 1
            ;;
        *)
            echo "ERROR: Unsupported platform: $platform" >&2
            return 1
            ;;
    esac
}

# Parse arguments - called from main() after platform check
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force|-f)
                FORCE=true
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
}

# Global flags (set by parse_args)
DRY_RUN=false
FORCE=false

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    if [[ ! -d "$HOST_CLAUDE_PLUGINS_DIR" ]]; then
        error "Host plugins directory not found: $HOST_CLAUDE_PLUGINS_DIR"
        exit 1
    fi

    if [[ ! -f "$HOST_CLAUDE_SETTINGS" ]]; then
        error "Host settings file not found: $HOST_CLAUDE_SETTINGS"
        exit 1
    fi

    if ! command -v docker &>/dev/null; then
        error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! command -v jq &>/dev/null; then
        error "jq is not installed (required for JSON processing)"
        exit 1
    fi

    # Check if volume exists, create if not
    if ! docker volume inspect "$DATA_VOLUME" &>/dev/null; then
        warn "Data volume does not exist, creating..."
        $DRY_RUN || docker volume create "$DATA_VOLUME"
    fi

    success "Prerequisites OK"
}

# Copy plugin cache and marketplaces
copy_plugin_files() {
    step "Copying plugin cache and marketplaces..."

    if $DRY_RUN; then
        echo "  [dry-run] "
        return
    fi

    docker run --rm \
        -v "$DATA_VOLUME":/target \
        -v "$HOME":/source:ro \
        alpine sh -c "
            rm -rf /target/*
            mkdir -p /mnt/agent-data/claude/plugins /mnt/agent-data/claude/skills
            mkdir -p /mnt/agent-data/vscode-server/extensions /mnt/agent-data/vscode-server/data/Machine /mnt/agent-data/vscode-server/data/User /mnt/agent-data/vscode-server/data/User/mcp /mnt/agent-data/vscode-server/data/User/prompts 
            mkdir -p /mnt/agent-data/vscode-server-insiders/extensions /mnt/agent-data/vscode-server-insiders/data/Machine /mnt/agent-data/vscode-server-insiders/data/User /mnt/agent-data/vscode-server-insiders/data/User/mcp /mnt/agent-data/vscode-server-insiders/data/User/prompts 
            mkdir -p /mnt/agent-data/copilot
            mkdir -p /mnt/agent-data/codex/skills
            mkdir -p /mnt/agent-data/gemini
            mkdir -p /mnt/agent-data/opencode

            touch /mnt/agent-data/vscode-server/data/Machine/settings.json /mnt/agent-data/vscode-server/data/User/mcp.json
            touch /mnt/agent-data/vscode-server-insiders/data/Machine/settings.json /mnt/agent-data/vscode-server-insiders/data/User/mcp.json
            touch /mnt/agent-data/claude/claude.json /mnt/agent-data/claude/.credentials.json /mnt/agent-data/claude/settings.json
            touch /mnt/agent-data/gemini/google_accounts.json /mnt/agent-data/gemini/oauth_creds.json /mnt/agent-data/gemini/settings.json
            touch /mnt/agent-data/codex/auth.json /mnt/agent-data/codex/config.toml

            cp -a /source/.claude/plugins/cache /source/.claude/plugins/marketplaces /target/claude/plugins 
            cp -a /source/.claude/skills /target/claude/skills 
            
        "

    success "Plugin files copied"
}

# Transform installed_plugins.json (fix paths + scope)
transform_installed_plugins() {
    step "Transforming installed_plugins.json (fixing paths and scope)..."

    local host_prefix="${HOST_PATH_PREFIX//\//\\/}"
    local container_prefix="${CONTAINER_PATH_PREFIX//\//\\/}"

    if $DRY_RUN; then
        echo "  [dry-run] Would transform paths: $HOST_PATH_PREFIX → $CONTAINER_PATH_PREFIX"
        echo "  [dry-run] Would change scope: local → user"
        return
    fi

    cat "$HOST_CLAUDE_PLUGINS_DIR/installed_plugins.json" | jq "
        .plugins = (.plugins | to_entries | map({
            key: .key,
            value: (.value | map(
                . + {
                    scope: \"user\",
                    installPath: (.installPath | gsub(\"$HOST_PATH_PREFIX\"; \"$CONTAINER_PATH_PREFIX\"))
                } | del(.projectPath)
            ))
        }) | from_entries)
    " | docker run --rm -i -v "$DATA_VOLUME":/target alpine sh -c "cat > /target/claude/plugins/installed_plugins.json"

    success "installed_plugins.json transformed"
}

# Transform known_marketplaces.json
transform_marketplaces() {
    step "Transforming known_marketplaces.json..."

    if $DRY_RUN; then
        echo "  [dry-run] Would transform marketplace paths"
        return
    fi

    # Use with_entries to preserve object structure (not map which converts to array)
    cat "$HOST_CLAUDE_PLUGINS_DIR/known_marketplaces.json" | jq "
        with_entries(
            .value.installLocation = (.value.installLocation | gsub(\"$HOST_PATH_PREFIX\"; \"$CONTAINER_PATH_PREFIX\"))
        )
    " | docker run --rm -i -v "$DATA_VOLUME":/target alpine sh -c "cat > /target/claude/plugins/known_marketplaces.json"

    success "known_marketplaces.json transformed"
}

# Merge enabledPlugins into sandbox settings
merge_enabled_plugins() {
    step "Merging enabledPlugins into sandbox settings..."

    if $DRY_RUN; then
        local count
        count=$(jq '.enabledPlugins | length' "$HOST_CLAUDE_SETTINGS")
        echo "  [dry-run] Would merge $count enabled plugins"
        return
    fi

    local host_plugins
    host_plugins=$(jq '.enabledPlugins' "$HOST_CLAUDE_SETTINGS")

    # Get existing sandbox settings or create minimal structure
    local existing_settings
    existing_settings=$(docker run --rm -v "$DATA_VOLUME":/data alpine cat /data/settings.json 2>/dev/null || echo '{}')

    # If empty or invalid, create minimal structure
    if [[ -z "$existing_settings" ]] || ! echo "$existing_settings" | jq -e '.' &>/dev/null; then
        existing_settings='{"permissions":{"allow":[],"defaultMode":"dontAsk"},"enabledPlugins":{},"autoUpdatesChannel":"latest"}'
    fi

    # Merge and write using temp file approach (avoids broken pipe issues)
    local merged
    merged=$(echo "$existing_settings" | jq --argjson hp "$host_plugins" '.enabledPlugins = ((.enabledPlugins // {}) + $hp)')

    # Write to volume
    echo "$merged" | docker run --rm -i -v "$DATA_VOLUME":/data alpine sh -c "cat > /data/settings.json && chown 1000:1000 /data/settings.json"

    success "enabledPlugins merged"
}

# Remove .orphaned_at markers
remove_orphan_markers() {
    step "Removing .orphaned_at markers..."

    if $DRY_RUN; then
        local count
        count=$(docker run --rm -v "$DATA_VOLUME":/plugins alpine find /plugins/claude/plugins/cache -name ".orphaned_at" 2>/dev/null | wc -l)
        echo "  [dry-run] Would remove $count orphan markers"
        return
    fi

    local removed
    removed=$(docker run --rm -v "$DATA_VOLUME":/plugins alpine sh -c '
        find /plugins/claude/plugins/cache -name ".orphaned_at" -delete -print 2>/dev/null | wc -l
    ')

    success "Removed $removed orphan markers"
}

# Fix ownership
fix_ownership() {
    step "Fixing ownership (UID 1000 for agent user)..."

    if $DRY_RUN; then
        echo "  [dry-run] Would chown 1000:1000 on volumes"
        return
    fi

    docker run --rm -v "$DATA_VOLUME":/plugins alpine chown -R 1000:1000 /plugins
    docker run --rm -v "$DATA_VOLUME":/data alpine chown 1000:1000 -R /data 

    success "Ownership fixed"
}

# Show summary
show_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    success "Sync complete!"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""

    # Count plugins
    local plugin_count
    plugin_count=$(jq '.plugins | length' "$HOST_CLAUDE_PLUGINS_DIR/installed_plugins.json" 2>/dev/null || echo "?")

    local enabled_count
    enabled_count=$(jq '[.enabledPlugins | to_entries[] | select(.value == true)] | length' "$HOST_CLAUDE_SETTINGS" 2>/dev/null || echo "?")

    echo "  📦 Plugins synced: $plugin_count"
    echo "  ✓ Enabled: $enabled_count"
    echo ""
    echo "To use the sandbox with plugins:"
    echo ""
    echo "  asb                                   # Start with plugins"
    echo "  asbd                                   # Start detached with plugins"
    echo ""


}

# Main
main() {
    # Platform guard - must run before any operations (including argument parsing)
    check_platform || exit 1

    # Parse arguments after platform check
    parse_args "$@"

    echo "═══════════════════════════════════════════════════════════════════"
    info "Syncing Claude Code plugins from host to Docker sandbox"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""

    if $DRY_RUN; then
        warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    check_prerequisites
    echo ""

    copy_plugin_files
    transform_installed_plugins
    transform_marketplaces
    merge_enabled_plugins
    remove_orphan_markers
    fix_ownership

    if ! $DRY_RUN; then
        show_summary
    else
        echo ""
        success "[dry-run] All checks passed. Run without --dry-run to apply changes."
    fi
}

main "$@"