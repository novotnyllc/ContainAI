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
readonly HOST_PLUGINS_DIR="$HOME/.claude/plugins"
readonly HOST_SETTINGS="$HOME/.claude/settings.json"
readonly PLUGINS_VOLUME="sandbox-agent-data"
readonly DATA_VOLUME="docker-claude-sandbox-data"
readonly CONTAINER_PLUGINS_PATH="/home/agent/.claude/plugins"

# User-specific path (auto-detected)
readonly HOST_PATH_PREFIX="$HOME/.claude/plugins/"
readonly CONTAINER_PATH_PREFIX="/home/agent/.claude/plugins/"

# Color output helpers
info() { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
error() { echo "❌ $*" >&2; }
warn() { echo "⚠️  $*"; }
step() { echo "→ $*"; }

# Parse arguments
DRY_RUN=false
FORCE=false

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

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    if [[ ! -d "$HOST_PLUGINS_DIR" ]]; then
        error "Host plugins directory not found: $HOST_PLUGINS_DIR"
        exit 1
    fi

    if [[ ! -f "$HOST_SETTINGS" ]]; then
        error "Host settings file not found: $HOST_SETTINGS"
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

    # Check if volumes exist, create if not
    if ! docker volume inspect "$PLUGINS_VOLUME" &>/dev/null; then
        warn "Plugins volume does not exist, creating..."
        $DRY_RUN || docker volume create "$PLUGINS_VOLUME"
    fi

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
        echo "  [dry-run] Would copy: cache/, marketplaces/"
        return
    fi

    docker run --rm \
        -v "$PLUGINS_VOLUME":/target \
        -v "$HOST_PLUGINS_DIR":/source:ro \
        alpine sh -c "
            rm -rf /target/claude /target/vscode-server /target/vscode-server-insiders 
            mkdir -p /target/claude/plugins 
            mkdir -p /target/vscode-server/extensions /target/vscode-server/data/Machine /target/vscode-server/data/User /target/vscode-server/data/User/mcp /target/vscode-server/data/User/prompts || true
            mkdir -p /target/vscode-server-insiders/extensions /target/vscode-server-insiders/data/Machine /target/vscode-server-insiders/data/User /target/vscode-server-insiders/data/User/mcp /target/vscode-server-insiders/data/User/prompts || true
            touch /target/vscode-server/data/Machine/settings.json /target/vscode-server/data/User/mcp.json
            touch /target/vscode-server-insiders/data/Machine/settings.json /target/vscode-server-insiders/data/User/mcp.json
            cp -a /source/cache /source/marketplaces /target/claude/plugins 
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

    cat "$HOST_PLUGINS_DIR/installed_plugins.json" | jq "
        .plugins = (.plugins | to_entries | map({
            key: .key,
            value: (.value | map(
                . + {
                    scope: \"user\",
                    installPath: (.installPath | gsub(\"$HOST_PATH_PREFIX\"; \"$CONTAINER_PATH_PREFIX\"))
                } | del(.projectPath)
            ))
        }) | from_entries)
    " | docker run --rm -i -v "$PLUGINS_VOLUME":/target alpine sh -c "cat > /target/claude/plugins/installed_plugins.json"

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
    cat "$HOST_PLUGINS_DIR/known_marketplaces.json" | jq "
        with_entries(
            .value.installLocation = (.value.installLocation | gsub(\"$HOST_PATH_PREFIX\"; \"$CONTAINER_PATH_PREFIX\"))
        )
    " | docker run --rm -i -v "$PLUGINS_VOLUME":/target alpine sh -c "cat > /target/claude/plugins/known_marketplaces.json"

    success "known_marketplaces.json transformed"
}

# Merge enabledPlugins into sandbox settings
merge_enabled_plugins() {
    step "Merging enabledPlugins into sandbox settings..."

    if $DRY_RUN; then
        local count
        count=$(jq '.enabledPlugins | length' "$HOST_SETTINGS")
        echo "  [dry-run] Would merge $count enabled plugins"
        return
    fi

    local host_plugins
    host_plugins=$(jq '.enabledPlugins' "$HOST_SETTINGS")

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
        count=$(docker run --rm -v "$PLUGINS_VOLUME":/plugins alpine find /plugins/claude/plugins/cache -name ".orphaned_at" 2>/dev/null | wc -l)
        echo "  [dry-run] Would remove $count orphan markers"
        return
    fi

    local removed
    removed=$(docker run --rm -v "$PLUGINS_VOLUME":/plugins alpine sh -c '
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

    docker run --rm -v "$PLUGINS_VOLUME":/plugins alpine chown -R 1000:1000 /plugins
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
    plugin_count=$(jq '.plugins | length' "$HOST_PLUGINS_DIR/installed_plugins.json" 2>/dev/null || echo "?")

    local enabled_count
    enabled_count=$(jq '[.enabledPlugins | to_entries[] | select(.value == true)] | length' "$HOST_SETTINGS" 2>/dev/null || echo "?")

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