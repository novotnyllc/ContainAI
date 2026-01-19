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

# Default volume name (can be overridden via CLI, env, or config)
readonly _SYNC_DEFAULT_VOLUME="sandbox-agent-data"

# Script directory for locating parse-toml.py
_SYNC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# ==============================================================================
# Volume name resolution functions
# ==============================================================================

# Validate Docker volume name pattern
# Pattern: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
# Length: 1-255 characters
# Returns: 0=valid, 1=invalid
_sync_validate_volume_name() {
    local name="$1"

    # Check length
    if [[ -z "$name" ]] || [[ ${#name} -gt 255 ]]; then
        return 1
    fi

    # Check pattern: must start with alphanumeric, followed by alphanumeric, underscore, dot, or dash
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        return 1
    fi

    return 0
}

# Find config file by walking up from $PWD
# Checks: .containai/config.toml then falls back to XDG_CONFIG_HOME
# Outputs: config file path (or empty if not found)
_sync_find_config() {
    local dir config_file git_root_found

    dir="$PWD"
    git_root_found=false

    # Walk up directory tree looking for .containai/config.toml
    while [[ "$dir" != "/" ]]; do
        config_file="$dir/.containai/config.toml"
        if [[ -f "$config_file" ]]; then
            printf '%s' "$config_file"
            return 0
        fi

        # Check for git root (stop walking up after git root)
        # Use -e to handle both .git directory and .git file (worktrees/submodules)
        if [[ -e "$dir/.git" ]]; then
            git_root_found=true
            break
        fi

        dir=$(dirname "$dir")
    done

    # Only check root directory if we actually walked to / (no git root found)
    if [[ "$git_root_found" == "false" && -f "/.containai/config.toml" ]]; then
        printf '%s' "/.containai/config.toml"
        return 0
    fi

    # Fall back to XDG_CONFIG_HOME
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    config_file="$xdg_config/containai/config.toml"
    if [[ -f "$config_file" ]]; then
        printf '%s' "$config_file"
        return 0
    fi

    # Not found
    return 0
}

# Resolve volume from config file
# Arguments: $1 = explicit config path (optional)
# Outputs: data_volume value (or empty if not found/no config)
_sync_resolve_config_volume() {
    local explicit_config="${1:-}"
    local config_file config_dir

    # Find config file
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
    else
        config_file=$(_sync_find_config)
    fi

    # No config file found - return empty (caller uses default)
    if [[ -z "$config_file" ]]; then
        return 0
    fi

    config_dir=$(dirname "$config_file")

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        echo "[WARN] Python not found, cannot parse config. Using default." >&2
        return 0
    fi

    # Call parse-toml.py in workspace matching mode (workspace = $PWD)
    # Use if-construct to avoid set -e terminating on non-zero exit
    local result parse_stderr
    parse_stderr=$(mktemp)
    # Cleanup temp file on function return (normal exit paths only)
    trap 'rm -f "$parse_stderr"' RETURN

    if ! result=$(python3 "$_SYNC_SCRIPT_DIR/parse-toml.py" "$config_file" --workspace "$PWD" --config-dir "$config_dir" 2>"$parse_stderr"); then
        echo "[WARN] Failed to parse config file: $config_file" >&2
        if [[ -s "$parse_stderr" ]]; then
            cat "$parse_stderr" >&2
        fi
        return 0  # Fall back to default, don't fail hard
    fi

    printf '%s' "$result"
}

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
            --volume)
                if [[ -z "${2:-}" ]]; then
                    error "--volume requires a value"
                    exit 1
                fi
                CLI_VOLUME="$2"
                shift 2
                ;;
            --volume=*)
                CLI_VOLUME="${1#--volume=}"
                if [[ -z "$CLI_VOLUME" ]]; then
                    error "--volume requires a value"
                    exit 1
                fi
                shift
                ;;
            --config)
                if [[ -z "${2:-}" ]]; then
                    error "--config requires a value"
                    exit 1
                fi
                EXPLICIT_CONFIG="$2"
                shift 2
                ;;
            --config=*)
                EXPLICIT_CONFIG="${1#--config=}"
                if [[ -z "$EXPLICIT_CONFIG" ]]; then
                    error "--config requires a value"
                    exit 1
                fi
                shift
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Print help message
print_help() {
    cat <<EOF
Usage: sync-agent-plugins.sh [OPTIONS]

Syncs agent plugins, configs, and credentials from host to Docker sandbox volume.

Options:
  --volume <name>    Docker volume name for agent data (default: $_SYNC_DEFAULT_VOLUME)
  --config <path>    Explicit config file path (disables discovery)
  --dry-run          Show what would be synced without executing
  --help             Show this help message

Environment:
  CONTAINAI_DATA_VOLUME    Volume name (overridden by --volume)
  CONTAINAI_CONFIG         Config file path (overridden by --config)

Note: Config discovery uses current directory (\$PWD) as root.
EOF
}

# Global flags (set by parse_args)
DRY_RUN=false
CLI_VOLUME=""
EXPLICIT_CONFIG=""

# DATA_VOLUME is set after resolve_data_volume() is called (then made readonly)
DATA_VOLUME=""

# Initialize EXPLICIT_CONFIG from environment if set
# CONTAINAI_CONFIG env var can be overridden by --config flag
_init_config_from_env() {
    if [[ -z "$EXPLICIT_CONFIG" && -n "${CONTAINAI_CONFIG:-}" ]]; then
        EXPLICIT_CONFIG="$CONTAINAI_CONFIG"
    fi
}

# Resolve data volume with precedence:
# 1. --volume CLI flag (skips config parsing)
# 2. CONTAINAI_DATA_VOLUME env var (skips config parsing)
# 3. Config file value (from $PWD discovery)
# 4. Default: sandbox-agent-data
resolve_data_volume() {
    local volume=""

    # 1. CLI flag always wins - SKIP all config parsing
    if [[ -n "$CLI_VOLUME" ]]; then
        if ! _sync_validate_volume_name "$CLI_VOLUME"; then
            error "Invalid volume name: $CLI_VOLUME"
            exit 1
        fi
        DATA_VOLUME="$CLI_VOLUME"
        return 0
    fi

    # 2. Environment variable - SKIP all config parsing
    if [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
        if ! _sync_validate_volume_name "$CONTAINAI_DATA_VOLUME"; then
            error "Invalid volume name in CONTAINAI_DATA_VOLUME: $CONTAINAI_DATA_VOLUME"
            exit 1
        fi
        DATA_VOLUME="$CONTAINAI_DATA_VOLUME"
        return 0
    fi

    # 3. Try config discovery from $PWD
    # Use if-construct to avoid set -e terminating on non-zero exit
    if ! volume=$(_sync_resolve_config_volume "$EXPLICIT_CONFIG"); then
        # Explicit config was specified but not found - exit with error
        exit 1
    fi

    if [[ -n "$volume" ]]; then
        if ! _sync_validate_volume_name "$volume"; then
            error "Invalid volume name in config: $volume"
            exit 1
        fi
        DATA_VOLUME="$volume"
        return 0
    fi

    # 4. Default
    DATA_VOLUME="$_SYNC_DEFAULT_VOLUME"
}

# Finalize DATA_VOLUME as readonly after resolution
_finalize_data_volume() {
    readonly DATA_VOLUME
}

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
        if $DRY_RUN; then
            error "Data volume does not exist: $DATA_VOLUME"
            error "Create it first with: docker volume create $DATA_VOLUME"
            exit 1
        fi
        warn "Data volume does not exist, creating..."
        docker volume create "$DATA_VOLUME"
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
                    # Run rsync (in dry-run, warn on exit 3 for missing dest dirs)
                    if [ "${DRY_RUN:-}" = "1" ]; then
                        if ! rsync "$@" "$src/" "$dst/" 2>&1; then
                            echo "[DRY-RUN] Note: $dst does not exist yet (will be created on actual sync)"
                        fi
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
                    # Run rsync (in dry-run, warn on exit 3 for missing dest dirs)
                    if [ "${DRY_RUN:-}" = "1" ]; then
                        if ! rsync "$@" "$src" "$dst" 2>&1; then
                            echo "[DRY-RUN] Note: ${dst%/*} does not exist yet (will be created on actual sync)"
                        fi
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
    # Handle --help before platform check so users can see help on any platform
    local arg
    for arg in "$@"; do
        if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
            print_help
            exit 0
        fi
    done

    # Platform guard - must run before any operations
    check_platform || exit 1

    # Parse remaining arguments after platform check
    parse_args "$@"

    # Initialize EXPLICIT_CONFIG from CONTAINAI_CONFIG env var if not set via --config
    _init_config_from_env

    # Resolve data volume (must be after parse_args sets CLI_VOLUME and EXPLICIT_CONFIG)
    resolve_data_volume
    _finalize_data_volume

    echo "═══════════════════════════════════════════════════════════════════"
    info "Syncing Claude Code plugins from host to Docker sandbox"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""

    # Print resolved volume for verification (required by acceptance criteria)
    info "Using data volume: $DATA_VOLUME"
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