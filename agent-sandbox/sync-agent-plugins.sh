#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Sync agent configs from host to Docker sandbox using rsync
# ==============================================================================
# Syncs plugins, settings, credentials, and other agent configs via eeacms/rsync
# container. Uses declarative SYNC_MAP to define sources, targets, and flags.
#
# Usage: sync-agent-plugins.sh [options]
#   --dry-run    Show what would be done without making changes (uses rsync --dry-run)
#   --force      Skip confirmation prompts
#   --help       Show this help message
#
# Platform: Linux only (blocks on macOS with error)
# ==============================================================================

# Constants
readonly HOST_CLAUDE_PLUGINS_DIR="$HOME/.claude/plugins"
readonly HOST_CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
readonly HOST_CLAUDE_SETTINGS="$HOME/.claude/settings.json"
readonly DATA_VOLUME="sandbox-agent-data"

# User-specific path (auto-detected)
readonly HOST_PATH_PREFIX="$HOME/.claude/plugins/"
readonly CONTAINER_PATH_PREFIX="/home/agent/.claude/plugins/"

# ==============================================================================
# SYNC_MAP: Declarative configuration array for syncing host configs to volume
# ==============================================================================
# Format: "source:target:flags"
# Flags:
#   d = directory
#   f = file
#   j = initialize JSON with {} if empty
#   m = mirror mode (--delete to remove files not in source)
#   s = secret (600 for files, 700 for dirs)
#   x = exclude .system/ subdirectory
# ==============================================================================

SYNC_MAP=(
  # ─── Claude Code ───
  # Note: target files are NOT dot-prefixed for visibility in volume
  "/source/.claude.json:/target/claude/claude.json:fjs"
  "/source/.claude/.credentials.json:/target/claude/credentials.json:fs"
  "/source/.claude/settings.json:/target/claude/settings.json:fj"
  "/source/.claude/settings.local.json:/target/claude/settings.local.json:f"
  "/source/.claude/plugins:/target/claude/plugins:d"
  "/source/.claude/skills:/target/claude/skills:d"

  # ─── GitHub CLI ───
  "/source/.config/gh:/target/config/gh:ds"

  # ─── OpenCode (config) ───
  "/source/.config/opencode:/target/config/opencode:d"

  # ─── tmux ───
  "/source/.tmux.conf:/target/tmux/.tmux.conf:f"
  "/source/.tmux:/target/tmux/.tmux:d"
  "/source/.config/tmux:/target/config/tmux:d"

  # ─── Shell ───
  "/source/.bash_aliases:/target/shell/.bash_aliases:f"
  "/source/.bashrc.d:/target/shell/.bashrc.d:d"

  # ─── VS Code Server ───
  # Sync entire data subtrees (no overlapping entries)
  "/source/.vscode-server/extensions:/target/vscode-server/extensions:d"
  "/source/.vscode-server/data/Machine:/target/vscode-server/data/Machine:d"
  "/source/.vscode-server/data/User/mcp:/target/vscode-server/data/User/mcp:d"
  "/source/.vscode-server/data/User/prompts:/target/vscode-server/data/User/prompts:d"

  # ─── VS Code Insiders ───
  "/source/.vscode-server-insiders/extensions:/target/vscode-server-insiders/extensions:d"
  "/source/.vscode-server-insiders/data/Machine:/target/vscode-server-insiders/data/Machine:d"
  "/source/.vscode-server-insiders/data/User/mcp:/target/vscode-server-insiders/data/User/mcp:d"
  "/source/.vscode-server-insiders/data/User/prompts:/target/vscode-server-insiders/data/User/prompts:d"

  # ─── Copilot ───
  # Selective sync: config, mcp-config, skills (exclude logs/, command-history-state.json)
  "/source/.copilot/config.json:/target/copilot/config.json:f"
  "/source/.copilot/mcp-config.json:/target/copilot/mcp-config.json:f"
  "/source/.copilot/skills:/target/copilot/skills:d"

  # ─── Gemini ───
  # Selective sync: credentials + user instructions (exclude tmp/, antigravity/)
  "/source/.gemini/google_accounts.json:/target/gemini/google_accounts.json:fs"
  "/source/.gemini/oauth_creds.json:/target/gemini/oauth_creds.json:fs"
  "/source/.gemini/GEMINI.md:/target/gemini/GEMINI.md:f"

  # ─── Codex ───
  # Selective sync: config, auth, skills (exclude history.jsonl, log/, sessions/, shell_snapshots/, tmp/)
  "/source/.codex/config.toml:/target/codex/config.toml:f"
  "/source/.codex/auth.json:/target/codex/auth.json:fs"
  "/source/.codex/skills:/target/codex/skills:dx"

  # ─── OpenCode (data) ───
  # Config is covered by ~/.config symlink; only need auth from data dir
  "/source/.local/share/opencode/auth.json:/target/local/share/opencode/auth.json:fs"
)

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

# ==============================================================================
# sync_configs: Rsync-based config sync using eeacms/rsync container
# ==============================================================================
# Processes SYNC_MAP entries via docker container with rsync.
# Pass map data via environment variable to avoid shell quoting issues.
# ==============================================================================
sync_configs() {
    step "Syncing configs via rsync..."

    # Build map data as newline-separated entries
    local map_data=""
    local entry
    for entry in "${SYNC_MAP[@]}"; do
        map_data+="$entry"$'\n'
    done

    # Build environment args
    local -a env_args=()
    env_args+=(--env "SYNC_MAP_DATA=$map_data")
    if $DRY_RUN; then
        env_args+=(--env "DRY_RUN=1")
    fi

    # Run container with map data passed via environment
    docker run --rm \
        --mount type=bind,src="$HOME",dst=/source,readonly \
        --mount type=volume,src="$DATA_VOLUME",dst=/target \
        "${env_args[@]}" \
        eeacms/rsync sh -e <<'SYNC_SCRIPT'
# ==============================================================================
# Functions for rsync-based sync (runs inside eeacms/rsync container)
# ==============================================================================

# ensure: Create target path and initialize JSON if flagged
ensure() {
    local path="$1" flags="$2"

    # In dry-run mode, only print what would happen
    if [ "${DRY_RUN:-}" = "1" ]; then
        case "$flags" in
            *d*) echo "[DRY-RUN] Would create directory: $path" ;;
            *f*) echo "[DRY-RUN] Would create parent dir and touch: $path" ;;
        esac
        case "$flags" in
            *j*) echo "[DRY-RUN] Would initialize JSON if empty: $path" ;;
        esac
        return 0
    fi

    # Create directory or file with parent
    case "$flags" in
        *d*) mkdir -p "$path" ;;
        *f*) mkdir -p "$(dirname "$path")"; touch "$path" ;;
    esac

    # Initialize JSON with {} if empty and flagged
    case "$flags" in
        *j*) [ -s "$path" ] || echo "{}" > "$path" ;;
    esac
}

# copy: Rsync source to target with appropriate flags
copy() {
    local src="$1" dst="$2" flags="$3"
    local opts="-a --chown=1000:1000"

    # Add mirror flag if specified (removes files not in source)
    case "$flags" in
        *m*) opts="$opts --delete" ;;
    esac

    # Add exclude for .system/ subdirectory if flagged
    case "$flags" in
        *x*) opts="$opts --exclude=.system/" ;;
    esac

    # In dry-run mode, use rsync --dry-run with itemize-changes
    if [ "${DRY_RUN:-}" = "1" ]; then
        opts="$opts --dry-run --itemize-changes"
    fi

    # Always ensure target exists first (respects dry-run internally)
    ensure "$dst" "$flags"

    # Copy if source exists, branching by type
    if [ -e "$src" ]; then
        case "$flags" in
            *d*)
                # Directory: use trailing slashes for content sync (not rename)
                if [ -d "$src" ]; then
                    rsync $opts "$src/" "$dst/"
                fi
                ;;
            *f*)
                # File: rsync directly to target path (handles renames)
                if [ -f "$src" ]; then
                    rsync $opts "$src" "$dst"
                fi
                ;;
        esac
    fi

    # Enforce restrictive permissions for secrets (skip in dry-run)
    if [ "${DRY_RUN:-}" != "1" ]; then
        case "$flags" in
            *s*)
                case "$flags" in
                    *d*) chmod 700 "$dst" 2>/dev/null || true ;;
                    *f*) chmod 600 "$dst" 2>/dev/null || true ;;
                esac
                ;;
        esac
    fi
}

# Process map entries from environment variable
echo "$SYNC_MAP_DATA" | while IFS=: read -r src dst flags; do
    [ -z "$src" ] && continue
    copy "$src" "$dst" "$flags"
done
SYNC_SCRIPT

    if $DRY_RUN; then
        success "[dry-run] Rsync sync simulation complete"
    else
        success "Configs synced via rsync"
    fi
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

    sync_configs
    transform_installed_plugins
    transform_marketplaces
    merge_enabled_plugins
    remove_orphan_markers

    if ! $DRY_RUN; then
        show_summary
    else
        echo ""
        success "[dry-run] All checks passed. Run without --dry-run to apply changes."
    fi
}

main "$@"