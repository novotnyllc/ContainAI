#!/usr/bin/env bash
# ==============================================================================
# ContainAI Import - cai import subcommand
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _containai_import  - Import host configs to data volume via rsync container
#
# Usage:
#   source lib/config.sh
#   source lib/import.sh
#   _containai_import "" "volume-name" "false" "false" "$PWD" "" ""
#
# Arguments:
#   $1 = Docker context ("" for default, "containai-secure" for Sysbox)
#   $2 = volume name (required)
#   $3 = dry_run flag ("true" or "false", default: "false")
#   $4 = no_excludes flag ("true" or "false", default: "false")
#   $5 = workspace path (optional, for exclude resolution, default: $PWD)
#   $6 = explicit config path (optional, for exclude resolution)
#   $7 = from_source path (optional, tgz file or directory; default: "" means $HOME)
#        NOTE: Non-empty from_source not yet implemented (ignored with warning)
#
# Dependencies:
#   - docker (for rsync container)
#   - jq (for JSON processing)
#   - base64 (for safe exclude pattern transport)
#   - lib/config.sh (for _containai_resolve_excludes, optional)
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/import.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/import.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/import.sh" >&2
    exit 1
fi

# User-specific paths for path transformation (guarded for re-sourcing)
: "${_IMPORT_HOST_PATH_PREFIX:=$HOME/.claude/plugins/}"
: "${_IMPORT_CONTAINER_PATH_PREFIX:=/home/agent/.claude/plugins/}"

# ==============================================================================
# Volume name validation (local copy for independence from config.sh)
# ==============================================================================

# Validate Docker volume name pattern
# Pattern: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
# Length: 1-255 characters
# Returns: 0=valid, 1=invalid
_import_validate_volume_name() {
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

# ==============================================================================
# Source type detection
# ==============================================================================

# Detect source type for --from argument
# Uses file -b for reliable detection (not extension-based)
# Arguments: $1 = source path (file or directory)
# Returns via stdout: "dir", "tgz", or "unknown"
# Exit code: 0=success, 1=source does not exist
_import_detect_source_type() {
    local source="$1"

    # Check source exists
    if [[ ! -e "$source" ]]; then
        return 1
    fi

    # Check for directory (handles symlinks via -d resolving them)
    if [[ -d "$source" ]]; then
        printf '%s\n' "dir"
        return 0
    fi

    # For files, use file -b for reliable detection
    if [[ -f "$source" ]]; then
        local file_type
        if ! file_type=$(file -b -- "$source" 2>/dev/null); then
            printf '%s\n' "unknown"
            return 0
        fi

        # Check for gzip compressed data
        case "$file_type" in
            *gzip\ compressed*)
                printf '%s\n' "tgz"
                return 0
                ;;
        esac
    fi

    # Not a recognized type
    printf '%s\n' "unknown"
    return 0
}

# ==============================================================================
# tgz restore function
# ==============================================================================

# Restore volume from tgz archive (idempotent)
# This is a "pure restore" that bypasses SYNC_MAP and all transforms.
# Arguments (3-arg form for internal use):
#   $1 = Docker context ("" for default)
#   $2 = volume name (required)
#   $3 = archive path (required, must be gzip-compressed tar)
# Arguments (2-arg form for standalone use):
#   $1 = volume name (required)
#   $2 = archive path (required)
# Returns: 0 on success, 1 on failure
_import_restore_from_tgz() {
    local ctx=""
    local volume=""
    local archive=""

    # Validate argument count
    if [[ $# -lt 2 || $# -gt 3 ]]; then
        _import_error "Usage: _import_restore_from_tgz [ctx] volume archive"
        _import_error "Got $# arguments, expected 2 or 3"
        return 1
    fi

    # Support both 2-arg (volume, archive) and 3-arg (ctx, volume, archive) forms
    if [[ $# -eq 3 ]]; then
        # 3-arg form: ctx, volume, archive
        ctx="${1:-}"
        volume="${2:-}"
        archive="${3:-}"
    else
        # 2-arg form: volume, archive (ctx defaults to "")
        volume="${1:-}"
        archive="${2:-}"
    fi

    # Build docker command prefix based on context
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd=(docker --context "$ctx")
    fi

    # Validate required arguments
    if [[ -z "$volume" ]]; then
        _import_error "Volume name is required"
        return 1
    fi

    if [[ -z "$archive" ]]; then
        _import_error "Archive path is required"
        return 1
    fi

    # Validate docker is available (for standalone use)
    if ! command -v docker >/dev/null 2>&1; then
        _import_error "Docker is not installed or not in PATH"
        return 1
    fi

    # Validate volume name to prevent bind mount injection
    # This is critical - without validation, a path like "/" could be passed
    # and the subsequent find -delete would wipe host files
    if ! _import_validate_volume_name "$volume"; then
        _import_error "Invalid volume name: $volume"
        _import_error "Volume names must start with alphanumeric and contain only [a-zA-Z0-9_.-]"
        return 1
    fi

    # Validate archive exists and is readable
    if [[ ! -f "$archive" ]]; then
        _import_error "Archive not found: $archive"
        return 1
    fi

    if [[ ! -r "$archive" ]]; then
        _import_error "Archive not readable: $archive"
        return 1
    fi

    _import_step "Validating archive integrity..."

    # Archive validation uses alpine container for consistency with extraction
    # This ensures validation and extraction use the same tar implementation
    # Validate archive can be read and check for path traversal + entry types in one pass
    # Note: We capture only stdout (not stderr) to avoid Docker pull progress polluting the result
    # Docker stderr (pull progress, warnings) goes to our stderr for user visibility
    local validation_result
    if ! validation_result=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm --network=none -i alpine:3.20 sh -c '
        # Read archive from stdin, validate, and report issues
        # Store stdin to temp file since we need multiple passes
        if ! cat > /tmp/archive.tgz; then
            echo "WRITE_FAILED"
            exit 0
        fi

        # Step 1: Check archive is readable
        if ! tar -tzf /tmp/archive.tgz >/dev/null 2>&1; then
            echo "CORRUPT"
            exit 0
        fi

        # Step 2: Check for path traversal (absolute paths or ..)
        if tar -tzf /tmp/archive.tgz 2>/dev/null | grep -qE "^/|(^|/)\.\.(/|$)"; then
            echo "UNSAFE_PATH"
            exit 0
        fi

        # Step 3: Check entry types using allowlist (only - and d allowed)
        # BusyBox tar -tv format: permissions owner/group size date time name
        # Note: Symlinks/hardlinks are intentionally rejected per spec (security)
        # Capture listing first to ensure tar succeeds before processing
        if ! listing=$(tar -tvzf /tmp/archive.tgz 2>&1); then
            echo "LIST_FAILED"
            exit 0
        fi
        disallowed=$(printf "%s\n" "$listing" | cut -c1 | grep -vE "^[-d]$" | sort -u | tr "\n" " ")
        if [ -n "$disallowed" ]; then
            echo "DISALLOWED_TYPES:$disallowed"
            exit 0
        fi

        echo "OK"
    ' < "$archive"); then
        _import_error "Failed to validate archive (container failed)"
        return 1
    fi

    # Extract just the last line in case Docker output leaked (shouldn't with stdout-only capture)
    validation_result=$(printf '%s\n' "$validation_result" | tail -n1)

    case "$validation_result" in
        WRITE_FAILED)
            _import_error "Failed to write archive to container (disk full or I/O error)"
            return 1
            ;;
        CORRUPT)
            _import_error "Failed to read archive (corrupt or not gzip-compressed tar): $archive"
            return 1
            ;;
        LIST_FAILED)
            _import_error "Failed to list archive contents for validation: $archive"
            return 1
            ;;
        UNSAFE_PATH)
            _import_error "Archive contains unsafe paths (absolute or parent traversal)"
            return 1
            ;;
        DISALLOWED_TYPES:*)
            local types="${validation_result#DISALLOWED_TYPES:}"
            _import_error "Archive contains disallowed entry types (only regular files and directories permitted)"
            _import_info "Symlinks, hardlinks, devices, FIFOs, and sockets are not allowed"
            _import_info "This is a known limitation for security - see epic spec fn-9-mqv"
            _import_info "Found disallowed types: $types"
            return 1
            ;;
        OK)
            : # Validation passed
            ;;
        *)
            _import_error "Unexpected validation result: $validation_result"
            return 1
            ;;
    esac

    _import_success "Archive validation passed"

    # Ensure volume exists (create if needed)
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" volume inspect "$volume" >/dev/null 2>&1; then
        _import_step "Creating volume: $volume"
        if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" volume create "$volume" >/dev/null; then
            _import_error "Failed to create volume $volume"
            return 1
        fi
    fi

    _import_step "Clearing volume contents for idempotent restore..."

    # Clear volume contents (including dotfiles) for idempotency
    # Use find -mindepth 1 -delete to remove all contents but preserve mount point
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm --network=none \
        -v "$volume":/data \
        alpine:3.20 \
        find /data -mindepth 1 -delete; then
        _import_error "Failed to clear volume contents"
        return 1
    fi

    _import_step "Extracting archive to volume..."

    # Extract archive to volume via alpine container
    # Pattern from export.sh:233-243 - use docker run with tar extraction
    # Read archive via stdin to avoid needing to mount the archive file
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm --network=none \
        -v "$volume":/data \
        -i \
        alpine:3.20 \
        tar -xzf - -C /data < "$archive"; then
        _import_error "Failed to extract archive to volume"
        return 1
    fi

    _import_success "Archive restored to volume: $volume"
    return 0
}

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
#
# Note: Callers can override _IMPORT_SYNC_MAP before calling _containai_import
# to customize which paths are synced.
# ==============================================================================

# Only set default if not already defined (allows caller override)
if [[ -z "${_IMPORT_SYNC_MAP+x}" ]]; then
_IMPORT_SYNC_MAP=(
  # --- Claude Code ---
  # Note: target files are NOT dot-prefixed for visibility in volume
  "/source/.claude.json:/target/claude/claude.json:fjs"
  "/source/.claude/.credentials.json:/target/claude/credentials.json:fs"
  "/source/.claude/settings.json:/target/claude/settings.json:fj"
  "/source/.claude/settings.local.json:/target/claude/settings.local.json:f"
  "/source/.claude/plugins:/target/claude/plugins:d"
  "/source/.claude/skills:/target/claude/skills:d"

  # --- GitHub CLI ---
  "/source/.config/gh:/target/config/gh:ds"

  # --- OpenCode (config) ---
  "/source/.config/opencode:/target/config/opencode:d"

  # --- tmux ---
  "/source/.config/tmux:/target/config/tmux:d"
  "/source/.local/share/tmux:/target/local/share/tmux:d"

  # --- Shell ---
  "/source/.bash_aliases:/target/shell/.bash_aliases:f"
  "/source/.bashrc.d:/target/shell/.bashrc.d:d"

  # --- VS Code Server ---
  # Sync entire data subtrees (no overlapping entries)
  "/source/.vscode-server/extensions:/target/vscode-server/extensions:d"
  "/source/.vscode-server/data/Machine:/target/vscode-server/data/Machine:d"
  "/source/.vscode-server/data/User/mcp:/target/vscode-server/data/User/mcp:d"
  "/source/.vscode-server/data/User/prompts:/target/vscode-server/data/User/prompts:d"

  # --- VS Code Insiders ---
  "/source/.vscode-server-insiders/extensions:/target/vscode-server-insiders/extensions:d"
  "/source/.vscode-server-insiders/data/Machine:/target/vscode-server-insiders/data/Machine:d"
  "/source/.vscode-server-insiders/data/User/mcp:/target/vscode-server-insiders/data/User/mcp:d"
  "/source/.vscode-server-insiders/data/User/prompts:/target/vscode-server-insiders/data/User/prompts:d"

  # --- Copilot ---
  # Selective sync: config, mcp-config, skills (exclude logs/, command-history-state.json)
  "/source/.copilot/config.json:/target/copilot/config.json:f"
  "/source/.copilot/mcp-config.json:/target/copilot/mcp-config.json:f"
  "/source/.copilot/skills:/target/copilot/skills:d"

  # --- Gemini ---
  # Selective sync: credentials + user instructions (exclude tmp/, antigravity/)
  "/source/.gemini/google_accounts.json:/target/gemini/google_accounts.json:fs"
  "/source/.gemini/oauth_creds.json:/target/gemini/oauth_creds.json:fs"
  "/source/.gemini/GEMINI.md:/target/gemini/GEMINI.md:f"

  # --- Codex ---
  # Selective sync: config, auth, skills (exclude history.jsonl, log/, sessions/, shell_snapshots/, tmp/)
  "/source/.codex/config.toml:/target/codex/config.toml:f"
  "/source/.codex/auth.json:/target/codex/auth.json:fs"
  "/source/.codex/skills:/target/codex/skills:dx"

  # --- OpenCode (data) ---
  # Only need auth from data dir
  "/source/.local/share/opencode/auth.json:/target/local/share/opencode/auth.json:fs"
)
fi

# ==============================================================================
# Logging helpers - use core.sh functions if available, fallback to ASCII markers
# ==============================================================================
_import_info() {
    if declare -f _cai_info >/dev/null 2>&1; then
        _cai_info "$@"
    else
        echo "[INFO] $*"
    fi
}
_import_success() {
    if declare -f _cai_ok >/dev/null 2>&1; then
        _cai_ok "$@"
    else
        echo "[OK] $*"
    fi
}
_import_error() {
    if declare -f _cai_error >/dev/null 2>&1; then
        _cai_error "$@"
    else
        echo "[ERROR] $*" >&2
    fi
}
_import_warn() {
    if declare -f _cai_warn >/dev/null 2>&1; then
        _cai_warn "$@"
    else
        echo "[WARN] $*" >&2
    fi
}
_import_step() {
    if declare -f _cai_step >/dev/null 2>&1; then
        _cai_step "$@"
    else
        echo "-> $*"
    fi
}

# ==============================================================================
# Main import function
# ==============================================================================

# Import host configs to data volume via rsync container
# Arguments:
#   $1 = Docker context ("" for default, "containai-secure" for Sysbox)
#   $2 = volume name (required)
#   $3 = dry_run flag ("true" or "false", default: "false")
#   $4 = no_excludes flag ("true" or "false", default: "false")
#        When true, disables both config excludes AND .system/ exclusion
#   $5 = workspace path (optional, for exclude resolution, default: $PWD)
#   $6 = explicit config path (optional, for exclude resolution)
#   $7 = from_source path (optional, tgz file or directory; default: "" means $HOME)
# Returns: 0 on success, 1 on failure
_containai_import() {
    local ctx="${1:-}"
    local volume="${2:-}"
    local dry_run="${3:-false}"
    local no_excludes="${4:-false}"
    local workspace="${5:-$PWD}"
    local explicit_config="${6:-}"
    local from_source="${7:-}"

    # Warn if --from is specified (not yet implemented, ignored for now)
    # TODO: Implement in fn-9-mqv.2-5 (tgz restore, directory sync)
    if [[ -n "$from_source" ]]; then
        _import_warn "--from is not yet implemented; ignoring '$from_source'"
        _import_info "Import will use default \$HOME source"
    fi

    # Build docker command prefix based on context
    # All docker calls in this function MUST use docker_cmd and neutralize DOCKER_CONTEXT/DOCKER_HOST
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd=(docker --context "$ctx")
    fi

    # Validate required arguments
    if [[ -z "$volume" ]]; then
        _import_error "Volume name is required"
        return 1
    fi

    # Validate volume name
    if ! _import_validate_volume_name "$volume"; then
        _import_error "Invalid volume name: $volume"
        _import_error "Volume names must start with alphanumeric and contain only [a-zA-Z0-9_.-]"
        return 1
    fi

    # Validate prerequisites
    if ! command -v docker >/dev/null 2>&1; then
        _import_error "Docker is not installed or not in PATH"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        _import_error "jq is not installed (required for JSON processing)"
        return 1
    fi

    if ! command -v base64 >/dev/null 2>&1; then
        _import_error "base64 is not installed (required for exclude pattern transport)"
        return 1
    fi

    # Print resolved volume for verification (required by acceptance criteria)
    _import_info "Using data volume: $volume"

    # Ensure volume exists
    # Note: dry-run requires volume to exist because rsync container mounts it
    # This is intentional - dry-run previews changes to an existing volume
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if [[ "$dry_run" != "true" ]]; then
        if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" volume inspect "$volume" >/dev/null 2>&1; then
            _import_warn "Data volume does not exist, creating..."
            if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" volume create "$volume" >/dev/null; then
                _import_error "Failed to create volume $volume"
                return 1
            fi
        fi
    else
        if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" volume inspect "$volume" >/dev/null 2>&1; then
            _import_error "Data volume does not exist: $volume"
            _import_error "Create it first with: docker volume create $volume"
            return 1
        fi
    fi

    # Resolve excludes from config (unless --no-excludes)
    local -a excludes=()
    if [[ "$no_excludes" != "true" ]]; then
        # Check if _containai_resolve_excludes is available (from config.sh)
        if declare -f _containai_resolve_excludes >/dev/null 2>&1; then
            local exclude_output exclude_line
            # Propagate errors if explicit config was provided
            if [[ -n "$explicit_config" ]]; then
                if ! exclude_output=$(_containai_resolve_excludes "$workspace" "$explicit_config"); then
                    _import_error "Failed to resolve excludes from config: $explicit_config"
                    return 1
                fi
            else
                # For discovered config, silently ignore errors
                exclude_output=$(_containai_resolve_excludes "$workspace" "$explicit_config" 2>/dev/null) || exclude_output=""
            fi
            while IFS= read -r exclude_line; do
                if [[ -n "$exclude_line" ]]; then
                    excludes+=("$exclude_line")
                fi
            done <<< "$exclude_output"
        fi
    fi

    # Build excludes as base64-encoded newline-delimited data for safe passing to container
    # Base64 encoding avoids issues with special characters in env vars and shell escaping
    local exclude_data_b64=""
    if [[ ${#excludes[@]} -gt 0 ]]; then
        local pattern exclude_data_raw=""
        for pattern in "${excludes[@]}"; do
            exclude_data_raw+="$pattern"$'\n'
        done
        # Base64 encode to safely pass through docker --env
        # Use portable encoding: pipe through tr to remove newlines (works on BSD/macOS/Linux)
        if ! exclude_data_b64=$(printf '%s' "$exclude_data_raw" | base64 | tr -d '\n'); then
            _import_error "Failed to encode exclude patterns"
            return 1
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        _import_warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    _import_step "Syncing configs via rsync..."

    # Build environment args for dry-run mode and no-excludes flag
    local -a env_args=()
    if [[ "$dry_run" == "true" ]]; then
        env_args+=(--env "DRY_RUN=1")
    fi
    if [[ "$no_excludes" == "true" ]]; then
        env_args+=(--env "NO_EXCLUDES=1")
    fi

    # Build map data and pass via heredoc inside the script
    # Note: This script runs inside eeacms/rsync with POSIX sh (not bash)
    # All code must be strictly POSIX-compliant (no arrays, no local in functions)
    local script_with_data
    # shellcheck disable=SC2016
    script_with_data='
# ==============================================================================
# Functions for rsync-based sync (runs inside eeacms/rsync container)
# ==============================================================================
# IMPORTANT: This runs under POSIX sh, not bash. No arrays or bash-isms allowed.

# ensure: Create target path and optionally init JSON if flagged
ensure() {
    _path="$1"
    _flags="$2"

    if [ "${DRY_RUN:-}" = "1" ]; then
        return 0
    fi

    case "$_flags" in
        *d*)
            mkdir -p "$_path"
            chown 1000:1000 "$_path"
            ;;
        *f*)
            mkdir -p "${_path%/*}"
            chown 1000:1000 "${_path%/*}"
            touch "$_path"
            chown 1000:1000 "$_path"
            ;;
    esac

    case "$_flags" in
        *j*)
            if [ ! -s "$_path" ]; then
                echo "{}" > "$_path"
                chown 1000:1000 "$_path"
            fi
            ;;
    esac

    case "$_flags" in
        *s*)
            case "$_flags" in
                *d*) chmod 700 "$_path" ;;
                *f*) chmod 600 "$_path" ;;
            esac
            ;;
    esac
}

# copy: Rsync source to target with appropriate flags
copy() {
    _src="$1"
    _dst="$2"
    _flags="$3"

    set -- -a --chown=1000:1000

    case "$_flags" in
        *m*) set -- "$@" --delete ;;
    esac

    # Add .system/ exclusion for x flag (unless NO_EXCLUDES is set)
    if [ "${NO_EXCLUDES:-}" != "1" ]; then
        case "$_flags" in
            *x*) set -- "$@" "--exclude=.system/" ;;
        esac
    fi

    # Add workspace excludes from EXCLUDE_DATA_B64 (unless NO_EXCLUDES is set)
    # EXCLUDE_DATA_B64 is base64-encoded to avoid shell escaping issues
    if [ "${NO_EXCLUDES:-}" != "1" ] && [ -n "${EXCLUDE_DATA_B64:-}" ]; then
        # Decode base64 to get newline-delimited excludes
        _exclude_decoded=$(printf "%s" "$EXCLUDE_DATA_B64" | base64 -d)
        # Disable globbing to prevent pattern expansion (e.g., *.log becoming actual files)
        set -f
        _old_ifs="$IFS"
        IFS="
"
        for _exc in $_exclude_decoded; do
            [ -n "$_exc" ] && set -- "$@" "--exclude=$_exc"
        done
        IFS="$_old_ifs"
        set +f
    fi

    if [ "${DRY_RUN:-}" = "1" ]; then
        set -- "$@" --dry-run --itemize-changes
    else
        set -- "$@" --mkpath
    fi

    if [ -e "$_src" ]; then
        case "$_flags" in
            *d*)
                if [ -d "$_src" ]; then
                    if [ "${DRY_RUN:-}" != "1" ]; then
                        ensure "$_dst" "$_flags"
                    fi
                    if [ "${DRY_RUN:-}" = "1" ]; then
                        if ! rsync "$@" "$_src/" "$_dst/" 2>&1; then
                            echo "[DRY-RUN] Note: $_dst does not exist yet (will be created on actual sync)"
                        fi
                    else
                        rsync "$@" "$_src/" "$_dst/"
                    fi
                    if [ "${DRY_RUN:-}" != "1" ]; then
                        case "$_flags" in
                            *s*)
                                find "$_dst" -type d -exec chmod 700 {} +
                                find "$_dst" -type f -exec chmod 600 {} +
                                ;;
                        esac
                    fi
                else
                    echo "[WARN] Expected directory but found file: $_src" >&2
                fi
                ;;
            *f*)
                if [ -f "$_src" ]; then
                    if [ "${DRY_RUN:-}" != "1" ]; then
                        ensure "$_dst" "$_flags"
                    fi
                    if [ "${DRY_RUN:-}" = "1" ]; then
                        if ! rsync "$@" "$_src" "$_dst" 2>&1; then
                            echo "[DRY-RUN] Note: ${_dst%/*} does not exist yet (will be created on actual sync)"
                        fi
                    else
                        rsync "$@" "$_src" "$_dst"
                    fi
                    if [ "${DRY_RUN:-}" != "1" ]; then
                        case "$_flags" in
                            *j*)
                                if [ ! -s "$_dst" ]; then
                                    echo "{}" > "$_dst"
                                    chown 1000:1000 "$_dst"
                                fi
                                ;;
                        esac
                        case "$_flags" in
                            *s*)
                                if [ -e "$_dst" ]; then
                                    chmod 600 "$_dst"
                                else
                                    echo "[WARN] Secret target missing: $_dst" >&2
                                fi
                                ;;
                        esac
                    fi
                else
                    echo "[WARN] Expected file but found directory: $_src" >&2
                fi
                ;;
        esac
    else
        if [ "${DRY_RUN:-}" = "1" ]; then
            case "$_flags" in
                *j*|*s*)
                    echo "[DRY-RUN] Source missing, would ensure target: $_dst"
                    case "$_flags" in *j*) echo "[DRY-RUN]   with JSON init" ;; esac
                    case "$_flags" in *s*) echo "[DRY-RUN]   with secret permissions" ;; esac
                    ;;
                *)
                    echo "[DRY-RUN] Source not found, would skip: $_src"
                    ;;
            esac
        else
            case "$_flags" in
                *j*|*s*)
                    echo "[INFO] Source missing, ensuring target: $_dst"
                    ensure "$_dst" "$_flags"
                    ;;
                *)
                    echo "[WARN] Source not found, skipping: $_src" >&2
                    ;;
            esac
        fi
    fi
}

# Process map entries from heredoc
while IFS=: read -r _map_src _map_dst _map_flags; do
    [ -z "$_map_src" ] && continue
    copy "$_map_src" "$_map_dst" "$_map_flags"
done <<'"'"'MAP_DATA'"'"'
'

    # Append SYNC_MAP entries as heredoc data
    local entry
    for entry in "${_IMPORT_SYNC_MAP[@]}"; do
        script_with_data+="$entry"$'\n'
    done
    script_with_data+=$'MAP_DATA\n'

    # Pass excludes via environment variable (base64-encoded for safe transport)
    if [[ -n "$exclude_data_b64" ]]; then
        env_args+=(--env "EXCLUDE_DATA_B64=$exclude_data_b64")
    fi

    # Run container with map data embedded in script via heredoc
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm --network=none --user 0:0 \
        --mount type=bind,src="$HOME",dst=/source,readonly \
        --mount type=volume,src="$volume",dst=/target \
        "${env_args[@]}" \
        eeacms/rsync sh -e -c "$script_with_data"; then
        _import_error "Rsync sync failed"
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        _import_success "[dry-run] Rsync sync simulation complete"
    else
        _import_success "Configs synced via rsync"
    fi

    # Post-sync transformations (only in non-dry-run mode)
    # Pass context to all transformation functions for context-aware docker calls
    if [[ "$dry_run" != "true" ]]; then
        if ! _import_transform_installed_plugins "$ctx" "$volume"; then
            _import_warn "Failed to transform installed_plugins.json"
        fi
        if ! _import_transform_marketplaces "$ctx" "$volume"; then
            _import_warn "Failed to transform known_marketplaces.json"
        fi
        if ! _import_merge_enabled_plugins "$ctx" "$volume"; then
            _import_warn "Failed to merge enabledPlugins"
        fi
        _import_remove_orphan_markers "$ctx" "$volume"
    else
        _import_step "[dry-run] Would transform installed_plugins.json"
        _import_step "[dry-run] Would transform known_marketplaces.json"
        _import_step "[dry-run] Would merge enabledPlugins into sandbox settings"
        _import_step "[dry-run] Would remove orphan markers"
    fi

    return 0
}

# ==============================================================================
# Post-sync transformations
# ==============================================================================

# Transform installed_plugins.json (fix paths + scope)
# Arguments: $1 = context, $2 = volume
_import_transform_installed_plugins() {
    local ctx="$1"
    local volume="$2"
    local src_file="$HOME/.claude/plugins/installed_plugins.json"

    # Build docker command with context
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd=(docker --context "$ctx")
    fi

    _import_step "Transforming installed_plugins.json (fixing paths and scope)..."

    if [[ ! -f "$src_file" ]]; then
        _import_warn "installed_plugins.json not found, skipping transform"
        return 0
    fi

    if ! jq -e '.' "$src_file" >/dev/null 2>&1; then
        _import_warn "installed_plugins.json is invalid JSON, skipping transform"
        return 0
    fi

    # Transform and capture result, checking for errors
    local transformed
    if ! transformed=$(jq "
        .plugins = (.plugins | to_entries | map({
            key: .key,
            value: (.value | map(
                . + {
                    scope: \"user\",
                    installPath: (.installPath | gsub(\"$_IMPORT_HOST_PATH_PREFIX\"; \"$_IMPORT_CONTAINER_PATH_PREFIX\"))
                } | del(.projectPath)
            ))
        }) | from_entries)
    " "$src_file"); then
        _import_error "jq transformation failed for installed_plugins.json"
        return 1
    fi

    # Validate transformed JSON before writing
    if ! echo "$transformed" | jq -e '.' >/dev/null 2>&1; then
        _import_error "Transformed installed_plugins.json is invalid JSON"
        return 1
    fi

    # Write to volume with network isolation
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if ! echo "$transformed" | DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm -i --network=none --user 1000:1000 -v "$volume":/target alpine sh -c "cat > /target/claude/plugins/installed_plugins.json"; then
        _import_error "Failed to write transformed installed_plugins.json to volume"
        return 1
    fi

    _import_success "installed_plugins.json transformed"
    return 0
}

# Transform known_marketplaces.json
# Arguments: $1 = context, $2 = volume
_import_transform_marketplaces() {
    local ctx="$1"
    local volume="$2"
    local src_file="$HOME/.claude/plugins/known_marketplaces.json"

    # Build docker command with context
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd=(docker --context "$ctx")
    fi

    _import_step "Transforming known_marketplaces.json..."

    if [[ ! -f "$src_file" ]]; then
        _import_warn "known_marketplaces.json not found, skipping transform"
        return 0
    fi

    if ! jq -e '.' "$src_file" >/dev/null 2>&1; then
        _import_warn "known_marketplaces.json is invalid JSON, skipping transform"
        return 0
    fi

    # Transform and capture result, checking for errors
    local transformed
    if ! transformed=$(jq "
        with_entries(
            .value.installLocation = (.value.installLocation | gsub(\"$_IMPORT_HOST_PATH_PREFIX\"; \"$_IMPORT_CONTAINER_PATH_PREFIX\"))
        )
    " "$src_file"); then
        _import_error "jq transformation failed for known_marketplaces.json"
        return 1
    fi

    # Validate transformed JSON before writing
    if ! echo "$transformed" | jq -e '.' >/dev/null 2>&1; then
        _import_error "Transformed known_marketplaces.json is invalid JSON"
        return 1
    fi

    # Write to volume with network isolation
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if ! echo "$transformed" | DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm -i --network=none --user 1000:1000 -v "$volume":/target alpine sh -c "cat > /target/claude/plugins/known_marketplaces.json"; then
        _import_error "Failed to write transformed known_marketplaces.json to volume"
        return 1
    fi

    _import_success "known_marketplaces.json transformed"
    return 0
}

# Merge enabledPlugins into sandbox settings
# Arguments: $1 = context, $2 = volume
_import_merge_enabled_plugins() {
    local ctx="$1"
    local volume="$2"
    local host_settings="$HOME/.claude/settings.json"

    # Build docker command with context
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd=(docker --context "$ctx")
    fi

    _import_step "Merging enabledPlugins into sandbox settings..."

    if [[ ! -f "$host_settings" ]]; then
        _import_warn "Host settings.json not found, skipping merge"
        return 0
    fi

    # Validate host settings JSON first
    if ! jq -e '.' "$host_settings" >/dev/null 2>&1; then
        _import_warn "Host settings.json is invalid JSON, skipping merge"
        return 0
    fi

    local host_plugins
    if ! host_plugins=$(jq '.enabledPlugins // {}' "$host_settings"); then
        _import_error "Failed to extract enabledPlugins from host settings"
        return 1
    fi

    local existing_settings
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    existing_settings=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm --network=none -v "$volume":/target alpine cat /target/claude/settings.json 2>/dev/null || echo '{}')

    if [[ -z "$existing_settings" ]] || ! echo "$existing_settings" | jq -e '.' >/dev/null 2>&1; then
        existing_settings='{"permissions":{"allow":[],"defaultMode":"dontAsk"},"enabledPlugins":{},"autoUpdatesChannel":"latest"}'
    fi

    local merged
    if ! merged=$(echo "$existing_settings" | jq --argjson hp "$host_plugins" '.enabledPlugins = ((.enabledPlugins // {}) + $hp)'); then
        _import_error "Failed to merge enabledPlugins"
        return 1
    fi

    # Validate merged JSON before writing
    if ! echo "$merged" | jq -e '.' >/dev/null 2>&1; then
        _import_error "Merged settings.json is invalid JSON"
        return 1
    fi

    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if ! echo "$merged" | DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm -i --network=none -v "$volume":/target alpine sh -c "cat > /target/claude/settings.json && chown 1000:1000 /target/claude/settings.json"; then
        _import_error "Failed to write merged settings.json to volume"
        return 1
    fi

    _import_success "enabledPlugins merged"
    return 0
}

# Remove .orphaned_at markers
# Arguments: $1 = context, $2 = volume
_import_remove_orphan_markers() {
    local ctx="$1"
    local volume="$2"

    # Build docker command with context
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd=(docker --context "$ctx")
    fi

    _import_step "Removing .orphaned_at markers..."

    local removed
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    removed=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm --network=none -v "$volume":/plugins alpine sh -c '
        find /plugins/claude/plugins/cache -name ".orphaned_at" -delete -print 2>/dev/null | wc -l || echo 0
    ')

    _import_success "Removed $removed orphan markers"
}

return 0
