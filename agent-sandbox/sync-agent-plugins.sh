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
#   --help       Show this help message
#
# Platform: Linux only (blocks on macOS with error)
# ==============================================================================

# Constants
readonly HOST_CLAUDE_PLUGINS_DIR="$HOME/.claude/plugins"
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
# Pass map data via heredoc to avoid shell quoting issues.
# ==============================================================================
sync_configs() {
    step "Syncing configs via rsync..."

    # In dry-run mode, require volume to exist (no mutations allowed)
    if ! docker volume inspect "$DATA_VOLUME" &>/dev/null; then
        if $DRY_RUN; then
            error "Dry-run requires volume to exist: $DATA_VOLUME"
            error "Create it first with: docker volume create $DATA_VOLUME"
            return 1
        fi
        info "Creating data volume: $DATA_VOLUME"
        docker volume create "$DATA_VOLUME" >/dev/null
    fi

    # Build environment args for dry-run mode only
    local -a env_args=()
    if $DRY_RUN; then
        env_args+=(--env "DRY_RUN=1")
    fi

    # Build map data and pass via heredoc inside the script
    local script_with_data
    # shellcheck disable=SC2016
    script_with_data='
# ==============================================================================
# Functions for rsync-based sync (runs inside eeacms/rsync container)
# ==============================================================================

# ensure: Create target path and optionally init JSON if flagged
# Named to match spec; handles both path creation, JSON init, and secret perms
# Note: In dry-run mode, this is a no-op (no mutations allowed)
ensure() {
    path="$1"
    flags="$2"

    # In dry-run mode, do nothing (mutations not allowed)
    # Dry-run reporting is handled by copy() which skips rsync entirely
    if [ "${DRY_RUN:-}" = "1" ]; then
        return 0
    fi

    # Create directory or file with parent
    case "$flags" in
        *d*)
            mkdir -p "$path"
            chown 1000:1000 "$path"
            ;;
        *f*)
            mkdir -p "${path%/*}"
            chown 1000:1000 "${path%/*}"
            touch "$path"
            chown 1000:1000 "$path"
            ;;
    esac

    # Initialize JSON with {} if empty and flagged
    case "$flags" in
        *j*)
            if [ ! -s "$path" ]; then
                echo "{}" > "$path"
                chown 1000:1000 "$path"
            fi
            ;;
    esac

    # Apply secret permissions if flagged (Critical: must apply even when source missing)
    case "$flags" in
        *s*)
            case "$flags" in
                *d*) chmod 700 "$path" ;;
                *f*) chmod 600 "$path" ;;
            esac
            ;;
    esac
}

# copy: Rsync source to target with appropriate flags
# In dry-run mode, always uses rsync --dry-run --itemize-changes
copy() {
    src="$1"
    dst="$2"
    flags="$3"

    # Build rsync options using positional parameters (POSIX-safe)
    set -- -a --chown=1000:1000

    # Add mirror flag if specified (removes files not in source)
    case "$flags" in
        *m*) set -- "$@" --delete ;;
    esac

    # Add exclude for .system/ subdirectory if flagged
    case "$flags" in
        *x*) set -- "$@" "--exclude=.system/" ;;
    esac

    # In dry-run mode, use rsync --dry-run --itemize-changes
    if [ "${DRY_RUN:-}" = "1" ]; then
        set -- "$@" --dry-run --itemize-changes
    else
        # Only add --mkpath in non-dry-run mode
        set -- "$@" --mkpath
    fi

    # Only sync if source exists AND matches expected type
    if [ -e "$src" ]; then
        case "$flags" in
            *d*)
                # Directory: verify source is actually a directory
                if [ -d "$src" ]; then
                    # In non-dry-run, ensure target exists first
                    if [ "${DRY_RUN:-}" != "1" ]; then
                        ensure "$dst" "$flags"
                    fi
                    # Run rsync (in dry-run, ignore exit 3 for missing dest dirs)
                    if [ "${DRY_RUN:-}" = "1" ]; then
                        rsync "$@" "$src/" "$dst/" 2>/dev/null || true
                    else
                        rsync "$@" "$src/" "$dst/"
                    fi
                    # Enforce restrictive permissions recursively for secret dirs (non-dry-run only)
                    if [ "${DRY_RUN:-}" != "1" ]; then
                        case "$flags" in
                            *s*)
                                find "$dst" -type d -exec chmod 700 {} +
                                find "$dst" -type f -exec chmod 600 {} +
                                ;;
                        esac
                    fi
                else
                    echo "[WARN] Expected directory but found file: $src" >&2
                fi
                ;;
            *f*)
                # File: verify source is actually a file
                if [ -f "$src" ]; then
                    # In non-dry-run, ensure target exists first
                    if [ "${DRY_RUN:-}" != "1" ]; then
                        ensure "$dst" "$flags"
                    fi
                    # Run rsync (in dry-run, ignore exit 3 for missing dest dirs)
                    if [ "${DRY_RUN:-}" = "1" ]; then
                        rsync "$@" "$src" "$dst" 2>/dev/null || true
                    else
                        rsync "$@" "$src" "$dst"
                    fi
                    # Re-apply JSON init AFTER rsync (in case source was empty) - non-dry-run only
                    if [ "${DRY_RUN:-}" != "1" ]; then
                        case "$flags" in
                            *j*)
                                if [ ! -s "$dst" ]; then
                                    echo "{}" > "$dst"
                                    chown 1000:1000 "$dst"
                                fi
                                ;;
                        esac
                        # Enforce restrictive permissions for secret files
                        case "$flags" in
                            *s*)
                                if [ -e "$dst" ]; then
                                    chmod 600 "$dst"
                                else
                                    echo "[WARN] Secret target missing: $dst" >&2
                                fi
                                ;;
                        esac
                    fi
                else
                    echo "[WARN] Expected file but found directory: $src" >&2
                fi
                ;;
        esac
    else
        # Source missing: still ensure target exists if j or s flag (non-dry-run only)
        if [ "${DRY_RUN:-}" = "1" ]; then
            case "$flags" in
                *j*|*s*)
                    echo "[DRY-RUN] Source missing, would ensure target: $dst"
                    case "$flags" in *j*) echo "[DRY-RUN]   with JSON init" ;; esac
                    case "$flags" in *s*) echo "[DRY-RUN]   with secret permissions" ;; esac
                    ;;
                *)
                    echo "[DRY-RUN] Source not found, would skip: $src"
                    ;;
            esac
        else
            case "$flags" in
                *j*|*s*)
                    echo "[INFO] Source missing, ensuring target: $dst"
                    ensure "$dst" "$flags"
                    ;;
                *)
                    echo "[WARN] Source not found, skipping: $src" >&2
                    ;;
            esac
        fi
    fi
}

# Process map entries from heredoc
while IFS=: read -r src dst flags; do
    [ -z "$src" ] && continue
    copy "$src" "$dst" "$flags"
done <<'"'"'MAP_DATA'"'"'
'

    # Append SYNC_MAP entries as heredoc data
    local entry
    for entry in "${SYNC_MAP[@]}"; do
        script_with_data+="$entry"$'\n'
    done
    # Add trailing newline after MAP_DATA terminator for proper heredoc
    script_with_data+=$'MAP_DATA\n'

    # Run container with map data embedded in script via heredoc
    # Note: --network=none for security (rsync doesn't need network)
    # Note: --user 0:0 required for chown/rsync --chown to work
    docker run --rm --network=none --user 0:0 \
        --mount type=bind,src="$HOME",dst=/source,readonly \
        --mount type=volume,src="$DATA_VOLUME",dst=/target \
        "${env_args[@]}" \
        eeacms/rsync sh -e -c "$script_with_data"

    if $DRY_RUN; then
        success "[dry-run] Rsync sync simulation complete"
    else
        success "Configs synced via rsync"
    fi
}

# Transform installed_plugins.json (fix paths + scope)
transform_installed_plugins() {
    step "Transforming installed_plugins.json (fixing paths and scope)..."

    local src_file="$HOST_CLAUDE_PLUGINS_DIR/installed_plugins.json"

    if $DRY_RUN; then
        echo "  [dry-run] Would transform paths: $HOST_PATH_PREFIX → $CONTAINER_PATH_PREFIX"
        echo "  [dry-run] Would change scope: local → user"
        return
    fi

    # Guard: skip if source file doesn't exist or is invalid
    if [[ ! -f "$src_file" ]]; then
        warn "installed_plugins.json not found, skipping transform"
        return
    fi

    if ! jq -e '.' "$src_file" &>/dev/null; then
        warn "installed_plugins.json is invalid JSON, skipping transform"
        return
    fi

    jq "
        .plugins = (.plugins | to_entries | map({
            key: .key,
            value: (.value | map(
                . + {
                    scope: \"user\",
                    installPath: (.installPath | gsub(\"$HOST_PATH_PREFIX\"; \"$CONTAINER_PATH_PREFIX\"))
                } | del(.projectPath)
            ))
        }) | from_entries)
    " "$src_file" | docker run --rm -i --user 1000:1000 -v "$DATA_VOLUME":/target alpine sh -c "cat > /target/claude/plugins/installed_plugins.json"

    success "installed_plugins.json transformed"
}

# Transform known_marketplaces.json
transform_marketplaces() {
    step "Transforming known_marketplaces.json..."

    local src_file="$HOST_CLAUDE_PLUGINS_DIR/known_marketplaces.json"

    if $DRY_RUN; then
        echo "  [dry-run] Would transform marketplace paths"
        return
    fi

    # Guard: skip if source file doesn't exist or is invalid
    if [[ ! -f "$src_file" ]]; then
        warn "known_marketplaces.json not found, skipping transform"
        return
    fi

    if ! jq -e '.' "$src_file" &>/dev/null; then
        warn "known_marketplaces.json is invalid JSON, skipping transform"
        return
    fi

    # Use with_entries to preserve object structure (not map which converts to array)
    jq "
        with_entries(
            .value.installLocation = (.value.installLocation | gsub(\"$HOST_PATH_PREFIX\"; \"$CONTAINER_PATH_PREFIX\"))
        )
    " "$src_file" | docker run --rm -i --user 1000:1000 -v "$DATA_VOLUME":/target alpine sh -c "cat > /target/claude/plugins/known_marketplaces.json"

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
    # Note: path is /target/claude/settings.json to match SYNC_MAP target paths
    local existing_settings
    existing_settings=$(docker run --rm -v "$DATA_VOLUME":/target alpine cat /target/claude/settings.json 2>/dev/null || echo '{}')

    # If empty or invalid, create minimal structure
    if [[ -z "$existing_settings" ]] || ! echo "$existing_settings" | jq -e '.' &>/dev/null; then
        existing_settings='{"permissions":{"allow":[],"defaultMode":"dontAsk"},"enabledPlugins":{},"autoUpdatesChannel":"latest"}'
    fi

    # Merge and write using temp file approach (avoids broken pipe issues)
    local merged
    merged=$(echo "$existing_settings" | jq --argjson hp "$host_plugins" '.enabledPlugins = ((.enabledPlugins // {}) + $hp)')

    # Write to volume (path matches SYNC_MAP target)
    echo "$merged" | docker run --rm -i -v "$DATA_VOLUME":/target alpine sh -c "cat > /target/claude/settings.json && chown 1000:1000 /target/claude/settings.json"

    success "enabledPlugins merged"
}

# Remove .orphaned_at markers
remove_orphan_markers() {
    step "Removing .orphaned_at markers..."

    if $DRY_RUN; then
        local count
        # Run entire pipeline in container to avoid pipefail issues when cache dir missing
        count=$(docker run --rm -v "$DATA_VOLUME":/plugins alpine sh -c '
            find /plugins/claude/plugins/cache -name ".orphaned_at" 2>/dev/null | wc -l || echo 0
        ')
        echo "  [dry-run] Would remove $count orphan markers"
        return
    fi

    local removed
    removed=$(docker run --rm -v "$DATA_VOLUME":/plugins alpine sh -c '
        find /plugins/claude/plugins/cache -name ".orphaned_at" -delete -print 2>/dev/null | wc -l || echo 0
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