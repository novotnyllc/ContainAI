#!/usr/bin/env bash
# shellcheck disable=SC1078,SC1079,SC2026,SC2288,SC2289
# SC1078,SC1079,SC2026: False positives for quotes in comments and heredocs
# SC2288,SC2289: False positives for embedded sh scripts in heredocs (find -exec sh -c)
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
#   $1 = Docker context ("" for default, "containai-docker" for Sysbox)
#   $2 = volume name (required)
#   $3 = dry_run flag ("true" or "false", default: "false")
#   $4 = no_excludes flag ("true" or "false", default: "false")
#   $5 = workspace path (optional, for exclude resolution, default: $PWD)
#   $6 = explicit config path (optional, for exclude resolution)
#   $7 = from_source path (optional, tgz file or directory; default: "" means $HOME)
#        - If tgz archive: restores directly to volume (bypasses sync/transforms)
#        - If directory: syncs from that directory instead of $HOME
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
# Uses tar -tzf for reliable gzip archive detection (not extension-based)
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

    # For files, probe with tar to detect gzip-compressed tar archives
    # This is more reliable than file -b and doesn't require the file command
    if [[ -f "$source" ]]; then
        # Require tar for archive detection
        if ! command -v tar >/dev/null 2>&1; then
            # Can't detect archive type without tar - return unknown
            # Caller will get "unsupported source type" error with clear message
            printf '%s\n' "unknown"
            return 0
        fi
        # Use -- to prevent argument injection from filenames starting with -
        if tar -tzf -- "$source" >/dev/null 2>&1; then
            printf '%s\n' "tgz"
            return 0
        fi
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
        # Capture only stdout to avoid tar warnings polluting type check
        # Non-zero exit is handled as LIST_FAILED, stderr untouched for diagnostics
        if ! listing=$(tar -tvzf /tmp/archive.tgz); then
            echo "LIST_FAILED"
            exit 0
        fi
        disallowed=$(printf "%s\n" "$listing" | cut -c1 | grep -vE "^[-d]$" | sort -u | tr "\n" " ")
        if [ -n "$disallowed" ]; then
            echo "DISALLOWED_TYPES:$disallowed"
            exit 0
        fi

        echo "OK"
    ' <"$archive"); then
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
        tar -xzf - -C /data <"$archive"; then
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

        # --- Fonts ---
        "/source/.local/share/fonts:/target/local/share/fonts:d"

        # -- Common Agents Directory ---
        "/source/.agents:/target/agents:d"

        # --- Shell ---
        "/source/.bash_aliases:/target/shell/bash_aliases:f"
        "/source/.bashrc.d:/target/shell/bashrc.d:d"

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
        # Selective sync: credentials + settings + user instructions (exclude tmp/, antigravity/)
        "/source/.gemini/google_accounts.json:/target/gemini/google_accounts.json:fs"
        "/source/.gemini/oauth_creds.json:/target/gemini/oauth_creds.json:fs"
        "/source/.gemini/settings.json:/target/gemini/settings.json:fj"
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
#   $1 = Docker context ("" for default, "containai-docker" for Sysbox)
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

    # Build docker command prefix based on context (needed early for source validation)
    # All docker calls in this function MUST use docker_cmd and neutralize DOCKER_CONTEXT/DOCKER_HOST
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd=(docker --context "$ctx")
    fi

    # Handle --from source: detect type and route accordingly
    local source_type=""
    local source_root="$HOME"         # Default to $HOME for backward compatibility
    local from_directory_mode="false" # Track if --from <directory> was used (for symlink relinking)

    if [[ -n "$from_source" ]]; then
        # Validate path doesn't contain dangerous characters that could cause Docker mount injection
        # Comma breaks --mount option parsing, newline/carriage-return break command parsing
        # Glob metacharacters (*?[) break shell pattern matching used for symlink relinking
        if [[ "$from_source" == *,* ]] || [[ "$from_source" == *$'\n'* ]] || [[ "$from_source" == *$'\r'* ]]; then
            _import_error "Source path contains invalid characters (comma or control characters): $from_source"
            return 1
        fi
        if [[ "$from_source" == *'*'* ]] || [[ "$from_source" == *'?'* ]] || [[ "$from_source" == *'['* ]]; then
            _import_error "Source path contains glob metacharacters (*?[) which are not supported: $from_source"
            return 1
        fi

        # Normalize path: resolve to absolute path
        local normalized_source
        if [[ -d "$from_source" ]]; then
            # Directory: resolve via cd
            if ! normalized_source=$(cd -- "$from_source" 2>/dev/null && pwd); then
                _import_error "Cannot access source directory: $from_source"
                return 1
            fi
            from_source="$normalized_source"
        elif [[ -f "$from_source" ]]; then
            # File: resolve parent directory, then reconstruct full path
            local parent_dir
            parent_dir=$(dirname -- "$from_source")
            local base_name
            base_name=$(basename -- "$from_source")
            if ! normalized_source=$(cd -- "$parent_dir" 2>/dev/null && pwd); then
                _import_error "Cannot access source file parent directory: $parent_dir"
                return 1
            fi
            from_source="$normalized_source/$base_name"
        else
            _import_error "Source not found: $from_source"
            return 1
        fi

        # Re-validate after normalization (symlinks could resolve to paths with dangerous chars)
        if [[ "$from_source" == *,* ]] || [[ "$from_source" == *$'\n'* ]] || [[ "$from_source" == *$'\r'* ]]; then
            _import_error "Resolved source path contains invalid characters: $from_source"
            return 1
        fi
        if [[ "$from_source" == *'*'* ]] || [[ "$from_source" == *'?'* ]] || [[ "$from_source" == *'['* ]]; then
            _import_error "Resolved source path contains glob metacharacters (*?[) which are not supported: $from_source"
            return 1
        fi

        # Detect source type
        if ! source_type=$(_import_detect_source_type "$from_source"); then
            _import_error "Source not found: $from_source"
            return 1
        fi

        case "$source_type" in
            tgz)
                # tgz archive: delegate to restore function (bypasses sync/transforms)
                _import_info "Detected tgz archive: $from_source"

                # For dry-run, just list archive contents
                if [[ "$dry_run" == "true" ]]; then
                    _import_warn "DRY RUN MODE - Archive contents preview:"
                    echo ""
                    # List archive contents (use -- to prevent argument injection from filenames starting with -)
                    local tar_output
                    if ! tar_output=$(tar -tvzf -- "$from_source" 2>&1); then
                        _import_error "Failed to list archive contents: $from_source"
                        _import_error "$tar_output"
                        return 1
                    fi
                    printf '%s\n' "$tar_output"
                    echo ""
                    _import_success "[dry-run] Archive listing complete (no changes made)"
                    # Set restore mode flag for caller (containai.sh) to skip env import
                    export _CAI_RESTORE_MODE=1
                    return 0
                fi

                # Restore from archive
                if ! _import_restore_from_tgz "$ctx" "$volume" "$from_source"; then
                    return 1
                fi

                # Set restore mode flag for caller (containai.sh) to skip env import
                export _CAI_RESTORE_MODE=1

                # Return immediately - tgz restore bypasses sync pipeline and transforms
                return 0
                ;;
            dir)
                # Directory source: validate and use for sync
                _import_info "Using directory source: $from_source"

                # Validate readable and traversable
                if [[ ! -r "$from_source" ]] || [[ ! -x "$from_source" ]]; then
                    _import_error "Source directory not accessible (need read and execute permissions): $from_source"
                    return 1
                fi

                # Check Docker is available before mount preflight
                if ! command -v docker >/dev/null 2>&1; then
                    _import_error "Docker is not installed or not in PATH"
                    return 1
                fi

                # Check Docker can mount the directory (Docker Desktop file-sharing check)
                # Use docker_cmd to respect the selected context
                # Use --mount instead of -v to avoid colon parsing issues
                # Use --network=none for consistency with rest of import pipeline
                # Note: DOCKER_CONTEXT/DOCKER_HOST neutralization still needed since docker_cmd may use --context
                # Use eeacms/rsync (same image as actual sync) to avoid introducing new image dependency
                local mount_error
                if ! mount_error=$(DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm --network=none \
                    --mount "type=bind,src=$from_source,dst=/test,readonly" \
                    eeacms/rsync true 2>&1); then
                    # Distinguish image pull failure from mount failure
                    if [[ "$mount_error" == *"Unable to find image"* ]] || [[ "$mount_error" == *"pull access denied"* ]] || [[ "$mount_error" == *"manifest unknown"* ]]; then
                        _import_error "Failed to pull eeacms/rsync image (required for import)"
                        _import_info "Check network connectivity or pre-pull the image: docker pull eeacms/rsync"
                    else
                        _import_error "Cannot mount '$from_source' - ensure it's within Docker's file-sharing paths"
                        _import_info "On macOS/Windows, add the path in Docker Desktop Settings > Resources > File Sharing"
                    fi
                    if [[ -n "$mount_error" ]]; then
                        _import_info "Docker error: $mount_error"
                    fi
                    return 1
                fi

                # Set source_root for directory sync and enable symlink relinking mode
                source_root="$from_source"
                from_directory_mode="true"
                ;;
            unknown)
                _import_error "Unsupported source type: must be directory or gzip-compressed tar archive"
                _import_error "Source: $from_source"
                return 1
                ;;
            *)
                _import_error "Unexpected source type: $source_type"
                return 1
                ;;
        esac
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
            done <<<"$exclude_output"
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

    # Pass HOST_SOURCE_ROOT for symlink relinking (only if --from <directory> was used)
    if [[ "$from_directory_mode" == "true" ]]; then
        env_args+=(--env "HOST_SOURCE_ROOT=$source_root")
    fi

    # Build map data and pass via heredoc inside the script
    # Note: This script runs inside eeacms/rsync with POSIX sh (not bash)
    # All code must be strictly POSIX-compliant (no arrays, no local in functions)
    local script_with_data
    # shellcheck disable=SC2016,SC1012,SC2289
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
                        # Preview symlink relinks (scan source since dry-run does not create files)
                        if [ -n "${HOST_SOURCE_ROOT:-}" ]; then
                            _rel_path="${_src#/source}"
                            case "$HOST_SOURCE_ROOT" in
                                /) _host_src_dir="/${_rel_path#/}" ;;
                                */) _host_src_dir="${HOST_SOURCE_ROOT%/}${_rel_path}" ;;
                                *) _host_src_dir="${HOST_SOURCE_ROOT}${_rel_path}" ;;
                            esac
                            _runtime_dst_dir="/mnt/agent-data${_dst#/target}"
                            preview_symlink_relinks "$_host_src_dir" "$_runtime_dst_dir" "$_src" "$_flags"
                        fi
                    else
                        rsync "$@" "$_src/" "$_dst/"

                        # Relink internal absolute symlinks after rsync (only if HOST_SOURCE_ROOT is set)
                        if [ -n "${HOST_SOURCE_ROOT:-}" ]; then
                            # Derive per-entry paths for symlink relinking
                            # _src is /source/relative_path, strip /source to get relative
                            _rel_path="${_src#/source}"
                            # Normalize HOST_SOURCE_ROOT: strip trailing slash, except for root /
                            case "$HOST_SOURCE_ROOT" in
                                /) _host_src_dir="/${_rel_path#/}" ;;
                                */) _host_src_dir="${HOST_SOURCE_ROOT%/}${_rel_path}" ;;
                                *) _host_src_dir="${HOST_SOURCE_ROOT}${_rel_path}" ;;
                            esac
                            _runtime_dst_dir="/mnt/agent-data${_dst#/target}"
                            relink_internal_symlinks "$_host_src_dir" "$_runtime_dst_dir" "$_src" "$_dst"
                        fi
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

# ==============================================================================
# Symlink helper functions for relinking absolute symlinks after rsync
# ==============================================================================

# is_internal_absolute_symlink: Check if absolute symlink target is within host_src_dir
# Takes: host_src_dir, link_path
# Returns: 0 (true) if symlink is absolute AND target is within host_src_dir
#          1 (false) if symlink is relative OR target is outside host_src_dir
is_internal_absolute_symlink() {
    _host_src_dir="$1"
    _link_path="$2"

    # Normalize host_src_dir: strip trailing slash, except for root
    case "$_host_src_dir" in
        /) : ;;  # Keep root as-is
        */) _host_src_dir="${_host_src_dir%/}" ;;
    esac

    # Get symlink target (immediate, not resolved)
    _target=$(readlink "$_link_path") || return 1

    # Check if absolute (starts with /)
    case "$_target" in
        /*)
            # Absolute symlink - check if within host_src_dir
            case "$_target" in
                "${_host_src_dir}"/*|"${_host_src_dir}")
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        *)
            # Relative symlink - we do not relink these
            return 1
            ;;
    esac
}

# remap_absolute_symlink: Calculate new container-absolute target path
# Takes: host_src_dir, runtime_dst_dir, link_path
# Outputs: new target path to stdout
# Returns: 0 on success, 1 on failure (e.g., path escape attempt or external symlink)
# PRECONDITION: Caller should verify symlink is internal via is_internal_absolute_symlink first
remap_absolute_symlink() {
    _host_src_dir="$1"
    _runtime_dst_dir="$2"
    _link_path="$3"

    # Normalize host_src_dir: strip trailing slash, except for root
    case "$_host_src_dir" in
        /) : ;;  # Keep root as-is
        */) _host_src_dir="${_host_src_dir%/}" ;;
    esac

    # Normalize runtime_dst_dir: strip trailing slash, except for root
    case "$_runtime_dst_dir" in
        /) : ;;  # Keep root as-is
        */) _runtime_dst_dir="${_runtime_dst_dir%/}" ;;
    esac

    # Get symlink target
    _target=$(readlink "$_link_path") || return 1

    # Verify target is absolute and starts with host_src_dir (defense-in-depth)
    case "$_target" in
        "${_host_src_dir}"/*|"${_host_src_dir}")
            : # Valid internal absolute symlink
            ;;
        *)
            # External or relative symlink - refuse to remap
            return 1
            ;;
    esac

    # Strip host_src_dir prefix to get relative portion
    _rel_target="${_target#"$_host_src_dir"}"

    # Security: reject if rel_target contains path traversal
    case "$_rel_target" in
        */../*|*/..|/../*|/..)
            return 1
            ;;
    esac

    # Build new target path
    _new_target="${_runtime_dst_dir}${_rel_target}"

    # Belt-and-suspenders: validate result starts with runtime_dst_dir
    case "$_new_target" in
        "${_runtime_dst_dir}"/*|"${_runtime_dst_dir}")
            printf '%s\n' "$_new_target"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# symlink_target_exists_in_source: Check if symlink target exists in mounted source
# Takes: host_src_dir, source_mount, link_path
# Returns: 0 if target exists (regular file, dir, or even symlink), 1 if broken
# PRECONDITION: Caller should verify symlink is internal via is_internal_absolute_symlink first
symlink_target_exists_in_source() {
    _host_src_dir="$1"
    _source_mount="$2"
    _link_path="$3"

    # Normalize host_src_dir: strip trailing slash, except for root
    case "$_host_src_dir" in
        /) : ;;  # Keep root as-is
        */) _host_src_dir="${_host_src_dir%/}" ;;
    esac

    # Normalize source_mount: strip trailing slash, except for root
    case "$_source_mount" in
        /) : ;;  # Keep root as-is
        */) _source_mount="${_source_mount%/}" ;;
    esac

    # Get symlink target
    _target=$(readlink "$_link_path") || return 1

    # Verify target is absolute and starts with host_src_dir (defense-in-depth)
    case "$_target" in
        "${_host_src_dir}"/*|"${_host_src_dir}")
            : # Valid internal absolute symlink
            ;;
        *)
            # External or relative symlink - cannot check existence
            return 1
            ;;
    esac

    # Map host path to source mount path
    # e.g., /host/dotfiles/.config/foo -> /source/foo (if host_src_dir=/host/dotfiles/.config)
    _rel_target="${_target#"$_host_src_dir"}"

    # Security: reject if rel_target contains path traversal
    case "$_rel_target" in
        */../*|*/..|/../*|/..)
            return 1
            ;;
    esac

    _src_target="${_source_mount}${_rel_target}"

    # Test if target exists (file, dir, or symlink itself)
    if [ -e "$_src_target" ] || [ -L "$_src_target" ]; then
        return 0
    fi
    return 1
}

# preview_symlink_relinks: Preview symlinks that would be relinked (dry-run mode)
# Takes: host_src_dir, runtime_dst_dir, source_dir, flags
# Note: Scans SOURCE directory (not target, since rsync dry-run does not create files)
# Note: Respects .system/ exclusion when flags contain x and NO_EXCLUDES != 1
# Output: [RELINK], [WARN] messages to stderr
preview_symlink_relinks() {
    _host_src_dir="$1"
    _runtime_dst_dir="$2"
    _source_dir="$3"
    _flags="${4:-}"

    # Build find command with optional .system/ exclusion (mirrors rsync behavior)
    # When NO_EXCLUDES != 1 and flags contain x, prune .system/ directory
    _prune_system=""
    if [ "${NO_EXCLUDES:-}" != "1" ]; then
        case "$_flags" in
            *x*) _prune_system="1" ;;
        esac
    fi

    # Find all symlinks in source and preview what would be relinked
    # Use -path prune pattern when .system/ exclusion is active
    if [ "$_prune_system" = "1" ]; then
        find "$_source_dir" -path "$_source_dir/.system" -prune -o -type l -exec sh -c '"'"'
    host_src="$1"
    runtime_dst="$2"
    src_dir="$3"
    shift 3
    for link; do
        target=$(readlink "$link" 2>/dev/null) || continue

        # Skip relative symlinks (they remain unchanged, no output)
        case "$target" in
            /*) ;; # absolute, continue processing
            *) continue ;;
        esac

        # Normalize host_src: strip trailing slash, except for root
        case "$host_src" in
            /) : ;;
            */) host_src="${host_src%/}" ;;
        esac

        # Check if internal (target starts with host_src_dir)
        case "$target" in
            "$host_src"/* | "$host_src")
                # Extract relative portion
                rel_target="${target#"$host_src"}"

                # SECURITY: Reject paths with .. segments to prevent escape
                case "$rel_target" in
                    */..)
                        printf "[WARN] %s -> %s (path escape attempt, skipped)\n" "$link" "$target" >&2
                        continue
                        ;;
                    */../*)
                        printf "[WARN] %s -> %s (path escape attempt, skipped)\n" "$link" "$target" >&2
                        continue
                        ;;
                esac

                # Check if target exists in source (map host path to source mount)
                src_target="${src_dir}${rel_target}"
                if ! test -e "$src_target" && ! test -L "$src_target"; then
                    printf "[WARN] %s -> %s (broken, would be preserved)\n" "$link" "$target" >&2
                    continue
                fi

                # Normalize runtime_dst: strip trailing slash, except for root
                case "$runtime_dst" in
                    /) : ;;
                    */) runtime_dst="${runtime_dst%/}" ;;
                esac

                # Would be relinked
                new_target="${runtime_dst}${rel_target}"

                # Security: validate stays under runtime_dst (belt-and-suspenders)
                case "$new_target" in
                    "$runtime_dst"/* | "$runtime_dst") ;;
                    *)
                        printf "[WARN] %s -> %s (escape attempt, skipped)\n" "$link" "$new_target" >&2
                        continue
                        ;;
                esac

                printf "[RELINK] %s -> %s\n" "$link" "$new_target" >&2
                ;;
            *)
                # External absolute symlink (outside entry subtree)
                printf "[WARN] %s -> %s (outside entry subtree, would be preserved)\n" "$link" "$target" >&2
                ;;
        esac
    done
    '"'"' sh "$_host_src_dir" "$_runtime_dst_dir" "$_source_dir" {} +
    else
        find "$_source_dir" -type l -exec sh -c '"'"'
    host_src="$1"
    runtime_dst="$2"
    src_dir="$3"
    shift 3
    for link; do
        target=$(readlink "$link" 2>/dev/null) || continue

        # Skip relative symlinks (they remain unchanged, no output)
        case "$target" in
            /*) ;; # absolute, continue processing
            *) continue ;;
        esac

        # Normalize host_src: strip trailing slash, except for root
        case "$host_src" in
            /) : ;;
            */) host_src="${host_src%/}" ;;
        esac

        # Check if internal (target starts with host_src_dir)
        case "$target" in
            "$host_src"/* | "$host_src")
                # Extract relative portion
                rel_target="${target#"$host_src"}"

                # SECURITY: Reject paths with .. segments to prevent escape
                case "$rel_target" in
                    */..)
                        printf "[WARN] %s -> %s (path escape attempt, skipped)\n" "$link" "$target" >&2
                        continue
                        ;;
                    */../*)
                        printf "[WARN] %s -> %s (path escape attempt, skipped)\n" "$link" "$target" >&2
                        continue
                        ;;
                esac

                # Check if target exists in source (map host path to source mount)
                src_target="${src_dir}${rel_target}"
                if ! test -e "$src_target" && ! test -L "$src_target"; then
                    printf "[WARN] %s -> %s (broken, would be preserved)\n" "$link" "$target" >&2
                    continue
                fi

                # Normalize runtime_dst: strip trailing slash, except for root
                case "$runtime_dst" in
                    /) : ;;
                    */) runtime_dst="${runtime_dst%/}" ;;
                esac

                # Would be relinked
                new_target="${runtime_dst}${rel_target}"

                # Security: validate stays under runtime_dst (belt-and-suspenders)
                case "$new_target" in
                    "$runtime_dst"/* | "$runtime_dst") ;;
                    *)
                        printf "[WARN] %s -> %s (escape attempt, skipped)\n" "$link" "$new_target" >&2
                        continue
                        ;;
                esac

                printf "[RELINK] %s -> %s\n" "$link" "$new_target" >&2
                ;;
            *)
                # External absolute symlink (outside entry subtree)
                printf "[WARN] %s -> %s (outside entry subtree, would be preserved)\n" "$link" "$target" >&2
                ;;
        esac
    done
    '"'"' sh "$_host_src_dir" "$_runtime_dst_dir" "$_source_dir" {} +
    fi
}

# relink_internal_symlinks: Find and relink absolute symlinks within a target directory
# Takes: host_src_dir, runtime_dst_dir, source_mount, target_dir
# Note: Uses find -exec to handle paths with spaces safely (POSIX-compliant)
relink_internal_symlinks() {
    _host_src_dir="$1"
    _runtime_dst_dir="$2"
    _source_mount="$3"
    _target_dir="$4"

    # Skip if dry-run mode
    if [ "${DRY_RUN:-}" = "1" ]; then
        return 0
    fi

    # Find all symlinks and process them
    # Using find -exec sh -c with batch processing (+ terminator)
    find "$_target_dir" -type l -exec sh -c '"'"'
    host_src="$1"
    runtime_dst="$2"
    src_mount="$3"
    shift 3
    for link; do
        target=$(readlink "$link" 2>/dev/null) || continue

        # Skip relative symlinks (they remain unchanged)
        case "$target" in
            /*) ;; # absolute, continue processing
            *) continue ;;
        esac

        # Normalize host_src: strip trailing slash, except for root
        case "$host_src" in
            /) : ;;
            */) host_src="${host_src%/}" ;;
        esac

        # Check if internal (target starts with host_src_dir)
        case "$target" in
            "$host_src"/* | "$host_src")
                # Extract relative portion
                rel_target="${target#"$host_src"}"

                # SECURITY: Reject paths with .. segments to prevent escape
                # Check for /.. anywhere in path (covers /../, /.. at end, etc.)
                case "$rel_target" in
                    */..)
                        printf "[WARN] %s -> %s (path escape)\n" "$link" "$target" >&2
                        continue
                        ;;
                    */../*)
                        printf "[WARN] %s -> %s (path escape)\n" "$link" "$target" >&2
                        continue
                        ;;
                esac

                # Map host path to source mount for existence check
                src_target="${src_mount}${rel_target}"

                # Skip if broken (target does not exist in source)
                if ! test -e "$src_target" && ! test -L "$src_target"; then
                    printf "[WARN] %s -> %s (broken, preserved)\n" "$link" "$target" >&2
                    continue
                fi

                # Normalize runtime_dst: strip trailing slash, except for root
                case "$runtime_dst" in
                    /) : ;;
                    */) runtime_dst="${runtime_dst%/}" ;;
                esac

                # Remap to runtime path
                new_target="${runtime_dst}${rel_target}"

                # Security: validate stays under runtime_dst (belt-and-suspenders)
                case "$new_target" in
                    "$runtime_dst"/* | "$runtime_dst") ;;
                    *)
                        printf "[WARN] %s -> %s (escape attempt, skipped)\n" "$link" "$new_target" >&2
                        continue
                        ;;
                esac

                # Relink (rm first for directory symlink pitfall - ln -sfn creates inside existing dir)
                rm -rf "$link"
                ln -s "$new_target" "$link"
                chown -h 1000:1000 "$link"
                printf "[RELINK] %s -> %s\n" "$link" "$new_target" >&2
                ;;
            *)
                # External absolute symlink (outside entry subtree)
                printf "[WARN] %s -> %s (outside entry subtree, preserved)\n" "$link" "$target" >&2
                ;;
        esac
    done
    '"'"' sh "$_host_src_dir" "$_runtime_dst_dir" "$_source_mount" {} +
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
    # Use source_root (defaults to $HOME, or custom directory from --from)
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm --network=none --user 0:0 \
        --entrypoint sh \
        --mount type=bind,src="$source_root",dst=/source,readonly \
        --mount type=volume,src="$volume",dst=/target \
        "${env_args[@]}" \
        eeacms/rsync -e -c "$script_with_data"; then
        _import_error "Rsync sync failed"
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        _import_success "[dry-run] Rsync sync simulation complete"
    else
        _import_success "Configs synced via rsync"
    fi

    # Post-sync transformations (only in non-dry-run mode)
    # Pass context, volume, and source_root to transformation functions
    if [[ "$dry_run" != "true" ]]; then
        if ! _import_transform_installed_plugins "$ctx" "$volume" "$source_root"; then
            _import_warn "Failed to transform installed_plugins.json"
        fi
        if ! _import_transform_marketplaces "$ctx" "$volume" "$source_root"; then
            _import_warn "Failed to transform known_marketplaces.json"
        fi
        if ! _import_merge_enabled_plugins "$ctx" "$volume" "$source_root"; then
            _import_warn "Failed to merge enabledPlugins"
        fi
        _import_remove_orphan_markers "$ctx" "$volume"
        # Import git config (user identity + safe.directory)
        if ! _cai_import_git_config "$ctx" "$volume"; then
            _import_warn "Failed to import git config"
        fi
    else
        _import_step "[dry-run] Would transform installed_plugins.json"
        _import_step "[dry-run] Would transform known_marketplaces.json"
        _import_step "[dry-run] Would merge enabledPlugins into sandbox settings"
        _import_step "[dry-run] Would remove orphan markers"
        _import_step "[dry-run] Would import git config (user identity + safe.directory)"
    fi

    return 0
}

# ==============================================================================
# Post-sync transformations
# ==============================================================================

# Transform installed_plugins.json (fix paths + scope)
# Arguments: $1 = context, $2 = volume, $3 = source_root (defaults to $HOME)
_import_transform_installed_plugins() {
    local ctx="$1"
    local volume="$2"
    local source_root="${3:-$HOME}"
    local src_file="$source_root/.claude/plugins/installed_plugins.json"

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

    # Build path prefixes for rewriting
    # Always try to rewrite both $HOME/.claude/plugins/ and $source_root/.claude/plugins/
    # This handles configs that may reference either location
    local home_prefix="$HOME/.claude/plugins/"
    local source_prefix="$source_root/.claude/plugins/"

    # Transform and capture result, checking for errors
    # Do best-effort rewriting: try both home and source prefixes
    # Use startswith + slicing instead of gsub to avoid regex interpretation of metacharacters
    local transformed
    if ! transformed=$(jq --arg home_prefix "$home_prefix" \
        --arg source_prefix "$source_prefix" \
        --arg container_prefix "$_IMPORT_CONTAINER_PATH_PREFIX" '
        # Helper function: replace prefix if string starts with it (non-regex)
        def replace_prefix(old; new):
            if startswith(old) then new + .[old | length:] else . end;
        .plugins = (.plugins | to_entries | map({
            key: .key,
            value: (.value | map(
                . + {
                    scope: "user",
                    installPath: (.installPath | replace_prefix($home_prefix; $container_prefix) | replace_prefix($source_prefix; $container_prefix))
                } | del(.projectPath)
            ))
        }) | from_entries)
    ' "$src_file"); then
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
# Arguments: $1 = context, $2 = volume, $3 = source_root (defaults to $HOME)
_import_transform_marketplaces() {
    local ctx="$1"
    local volume="$2"
    local source_root="${3:-$HOME}"
    local src_file="$source_root/.claude/plugins/known_marketplaces.json"

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

    # Build path prefixes for rewriting
    # Always try to rewrite both $HOME/.claude/plugins/ and $source_root/.claude/plugins/
    # This handles configs that may reference either location
    local home_prefix="$HOME/.claude/plugins/"
    local source_prefix="$source_root/.claude/plugins/"

    # Transform and capture result, checking for errors
    # Do best-effort rewriting: try both home and source prefixes
    # Use startswith + slicing instead of gsub to avoid regex interpretation of metacharacters
    local transformed
    if ! transformed=$(jq --arg home_prefix "$home_prefix" \
        --arg source_prefix "$source_prefix" \
        --arg container_prefix "$_IMPORT_CONTAINER_PATH_PREFIX" '
        # Helper function: replace prefix if string starts with it (non-regex)
        def replace_prefix(old; new):
            if startswith(old) then new + .[old | length:] else . end;
        with_entries(
            .value.installLocation = (.value.installLocation | replace_prefix($home_prefix; $container_prefix) | replace_prefix($source_prefix; $container_prefix))
        )
    ' "$src_file"); then
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
# Arguments: $1 = context, $2 = volume, $3 = source_root (defaults to $HOME)
_import_merge_enabled_plugins() {
    local ctx="$1"
    local volume="$2"
    local source_root="${3:-$HOME}"
    local host_settings="$source_root/.claude/settings.json"

    # Build docker command with context
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd=(docker --context "$ctx")
    fi

    _import_step "Merging enabledPlugins into sandbox settings..."

    if [[ ! -f "$host_settings" ]]; then
        _import_warn "Source settings.json not found, skipping merge"
        return 0
    fi

    # Validate source settings JSON first
    if ! jq -e '.' "$host_settings" >/dev/null 2>&1; then
        _import_warn "Source settings.json is invalid JSON, skipping merge"
        return 0
    fi

    local host_plugins
    if ! host_plugins=$(jq '.enabledPlugins // {}' "$host_settings"); then
        _import_error "Failed to extract enabledPlugins from source settings"
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

# ==============================================================================
# Git config import
# ==============================================================================

# Import git user config from host to data volume
# Writes a .gitconfig file with user identity and safe.directory settings
# Arguments: $1 = context, $2 = volume
# Returns: 0 on success (including graceful skip), 1 on failure
_cai_import_git_config() {
    local ctx="$1"
    local volume="$2"

    # Build docker command with context
    local -a docker_cmd=(docker)
    if [[ -n "$ctx" ]]; then
        docker_cmd=(docker --context "$ctx")
    fi

    _import_step "Importing git config..."

    # Check if git is installed on host
    if ! command -v git >/dev/null 2>&1; then
        _import_warn "Git not installed on host, skipping git config import"
        return 0
    fi

    # Extract git user.name and user.email from host
    # Use git config --global to get user-level settings
    # Note: These commands return non-zero if config is not set, which is fine
    local git_name git_email
    git_name=$(git config --global user.name 2>/dev/null || printf '%s\n' "")
    git_email=$(git config --global user.email 2>/dev/null || printf '%s\n' "")

    # Check if we have at least name or email
    if [[ -z "$git_name" && -z "$git_email" ]]; then
        _import_warn "No git user.name or user.email configured on host, skipping git config import"
        return 0
    fi

    # Use git config -f to safely write values (avoids injection via newlines/control chars)
    # Run as root (volume root may be root-owned), then chown to 1000:1000
    # Use alpine image with git installed for git config command
    # Pass values via environment variables to avoid shell escaping issues
    # Use DOCKER_CONTEXT= DOCKER_HOST= prefix to neutralize env (per pitfall memory)
    if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" run --rm --network=none --user 0:0 \
        -v "$volume":/target \
        -e "GIT_NAME=${git_name}" \
        -e "GIT_EMAIL=${git_email}" \
        alpine/git:latest sh -c '
            # Refuse if target exists and is symlink or non-regular file
            if [ -L /target/.gitconfig ]; then
                echo "ERROR: /target/.gitconfig is a symlink - refusing to write" >&2
                exit 1
            fi
            if [ -e /target/.gitconfig ] && [ ! -f /target/.gitconfig ]; then
                echo "ERROR: /target/.gitconfig exists but is not a regular file" >&2
                exit 1
            fi

            # Remove existing file to start fresh (git config -f appends)
            rm -f /target/.gitconfig

            # Use git config -f for safe value escaping (prevents injection)
            if [ -n "$GIT_NAME" ]; then
                git config -f /target/.gitconfig user.name "$GIT_NAME"
            fi
            if [ -n "$GIT_EMAIL" ]; then
                git config -f /target/.gitconfig user.email "$GIT_EMAIL"
            fi

            # Add safe.directory entries (critical for mounted workspaces)
            git config -f /target/.gitconfig --add safe.directory /workspace
            git config -f /target/.gitconfig --add safe.directory /home/agent/workspace

            # Fix ownership for agent user
            chown 1000:1000 /target/.gitconfig
        '; then
        _import_error "Failed to write .gitconfig to volume"
        return 1
    fi

    # Build success message (avoid logging PII - just indicate what was set)
    local success_msg="Git config imported"
    if [[ -n "$git_name" && -n "$git_email" ]]; then
        success_msg="Git config imported (user.name + user.email)"
    elif [[ -n "$git_name" ]]; then
        success_msg="Git config imported (user.name)"
    elif [[ -n "$git_email" ]]; then
        success_msg="Git config imported (user.email)"
    fi
    _import_success "$success_msg"
    return 0
}

# ==============================================================================
# Hot-reload: reload configs into running container via SSH
# ==============================================================================

# Reload configs into a running container via SSH
# This activates environment variables and git config from the data volume
# without restarting the container.
#
# Arguments:
#   $1 = container name
#   $2 = docker context (optional)
#
# Returns: 0 on success, 1 on failure
#
# What gets activated:
# - Git config is copied from /mnt/agent-data/.gitconfig to $HOME/.gitconfig
# - Env vars: creates bashrc.d sourcing script so future shells load them
# - Credentials remain on the volume (accessed on demand by tools)
_cai_hot_reload_container() {
    local container_name="$1"
    local context="${2:-}"

    _import_step "Reloading configs into running container: $container_name"

    # Reload script to run inside container
    # This mirrors the logic from containai-init.sh but for hot-reload
    # Key difference: env vars are made persistent via bashrc.d hook
    local reload_script
    reload_script=$(
        cat <<'RELOAD_EOF'
set -e

DATA_DIR="/mnt/agent-data"
ENV_COUNT=0
GIT_UPDATED=0
ENV_HOOK_CREATED=0

# Helper for output
log() { printf '%s\n' "$*"; }

# ============================================================
# Setup persistent env loading via bashrc.d
# ============================================================
setup_env_hook() {
    local env_file="${DATA_DIR}/.env"
    local hook_dir="${DATA_DIR}/shell/bashrc.d"
    local hook_file="${hook_dir}/00-containai-env.sh"

    if [[ -L "$env_file" ]]; then
        log "[WARN] .env is symlink - skipping"
        return 0
    fi
    if [[ ! -f "$env_file" ]]; then
        log "[INFO] No .env file found in data volume"
        # Remove stale hook if env file was deleted
        if [[ -f "$hook_file" ]]; then
            rm -f "$hook_file" 2>/dev/null || true
            log "[INFO] Removed stale env hook (no .env file)"
        fi
        return 0
    fi
    if [[ ! -r "$env_file" ]]; then
        log "[WARN] .env unreadable - skipping"
        return 0
    fi

    # Count env vars for reporting
    local line key
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Strip optional 'export ' prefix
        if [[ "$line" =~ ^export[[:space:]]+ ]]; then
            line="${line#export}"
            line="${line#"${line%%[![:space:]]*}"}"
        fi
        # Require = in line
        [[ "$line" != *=* ]] && continue
        key="${line%%=*}"
        # Validate key
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        ENV_COUNT=$((ENV_COUNT + 1))
    done < "$env_file"

    # Create/update bashrc.d hook that safely loads .env
    # This ensures all new shells automatically load env vars
    # SECURITY: Uses safe line-by-line parsing, NOT source/eval
    mkdir -p "$hook_dir" 2>/dev/null || true

    cat > "$hook_file" << 'HOOK_EOF'
# ContainAI environment loader - auto-generated by cai import
# Safely loads .env file from data volume (no source/eval - prevents injection)
_cai_load_env() {
    local env_file="/mnt/agent-data/.env"
    [[ -f "$env_file" && -r "$env_file" && ! -L "$env_file" ]] || return 0

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip carriage return
        line="${line%$'\r'}"
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Strip optional 'export ' prefix
        if [[ "$line" =~ ^export[[:space:]]+ ]]; then
            line="${line#export}"
            line="${line#"${line%%[![:space:]]*}"}"
        fi
        # Require = in line
        [[ "$line" != *=* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        # Validate key (alphanumeric + underscore, starts with letter/underscore)
        [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
        # Export safely (no eval)
        export "$key=$value" 2>/dev/null || continue
    done < "$env_file"
}
_cai_load_env
unset -f _cai_load_env
HOOK_EOF

    chmod 644 "$hook_file" 2>/dev/null || true
    ENV_HOOK_CREATED=1

    if [[ $ENV_COUNT -gt 0 ]]; then
        log "[OK] Env hook created: $ENV_COUNT vars available for new shells"
    else
        log "[INFO] Env hook created (empty .env file)"
    fi
}

# ============================================================
# Reload git config from .gitconfig
# ============================================================
reload_git() {
    local src="${DATA_DIR}/.gitconfig"
    local dst="${HOME}/.gitconfig"

    if [[ -L "$src" ]]; then
        log "[WARN] Source .gitconfig is symlink - skipping"
        return 0
    fi
    if [[ ! -f "$src" ]]; then
        log "[INFO] No .gitconfig file found in data volume"
        return 0
    fi
    if [[ ! -r "$src" ]]; then
        log "[WARN] Source .gitconfig unreadable - skipping"
        return 0
    fi

    # Skip if destination is symlink (security)
    if [[ -L "$dst" ]]; then
        log "[WARN] Destination .gitconfig is symlink - refusing to overwrite"
        return 0
    fi

    # Skip if destination exists but is not a regular file (e.g., directory)
    if [[ -e "$dst" && ! -f "$dst" ]]; then
        log "[WARN] Destination .gitconfig exists but is not a regular file - skipping"
        return 0
    fi

    # Atomic copy via temp file
    local tmp_dst="${dst}.tmp.$$"
    if cp "$src" "$tmp_dst" 2>/dev/null && mv "$tmp_dst" "$dst" 2>/dev/null; then
        GIT_UPDATED=1
        log "[OK] Git config reloaded from data volume"
    else
        rm -f "$tmp_dst" 2>/dev/null || true
        log "[WARN] Failed to copy .gitconfig to \$HOME"
    fi
}

# ============================================================
# Main reload sequence
# ============================================================
log "[INFO] Hot-reload starting..."

setup_env_hook
reload_git

# Summary
if [[ $ENV_HOOK_CREATED -eq 1 || $GIT_UPDATED -eq 1 ]]; then
    log "[OK] Hot-reload complete"
    if [[ $ENV_HOOK_CREATED -eq 1 ]]; then
        log "[INFO] Env vars will be available in new shell sessions"
    fi
else
    log "[INFO] Hot-reload complete (no changes)"
fi
RELOAD_EOF
    )

    # Use _cai_ssh_run for retry logic and host-key auto-recovery
    # This ensures consistent behavior with cai shell
    local ssh_output
    local ssh_exit_code

    # Check if _cai_ssh_run is available (it should be, from ssh.sh)
    if declare -f _cai_ssh_run >/dev/null 2>&1; then
        # Use the existing SSH infrastructure with retry/recovery
        if ssh_output=$(_cai_ssh_run "$container_name" "$context" "false" "true" "false" "false" bash -c "$reload_script" 2>&1); then
            ssh_exit_code=0
        else
            ssh_exit_code=$?
        fi
    else
        # Fallback: direct SSH (shouldn't happen if ssh.sh is sourced)
        _import_warn "SSH helper not available, using direct connection"

        # Get SSH port from container label
        local ssh_port
        if ! ssh_port=$(_cai_get_container_ssh_port "$container_name" "$context"); then
            _import_error "Container has no SSH port configured"
            _import_error "This container may have been created before SSH support was added."
            _import_error "Recreate the container with: cai run --fresh /path/to/workspace"
            return 1
        fi

        # Determine StrictHostKeyChecking value based on OpenSSH version
        local strict_host_key_checking
        if _cai_check_ssh_accept_new_support 2>/dev/null; then
            strict_host_key_checking="accept-new"
        else
            strict_host_key_checking="yes"
        fi

        # Build SSH command options
        local -a ssh_opts=(
            -o "HostName=localhost"
            -o "Port=$ssh_port"
            -o "User=agent"
            -o "IdentityFile=$_CAI_SSH_KEY_PATH"
            -o "IdentitiesOnly=yes"
            -o "UserKnownHostsFile=$_CAI_KNOWN_HOSTS_FILE"
            -o "StrictHostKeyChecking=$strict_host_key_checking"
            -o "PreferredAuthentications=publickey"
            -o "GSSAPIAuthentication=no"
            -o "PasswordAuthentication=no"
            -o "ConnectTimeout=10"
            -o "BatchMode=yes"
        )

        if ssh_output=$(ssh "${ssh_opts[@]}" localhost "$reload_script" 2>&1); then
            ssh_exit_code=0
        else
            ssh_exit_code=$?
        fi
    fi

    # Parse and display output with proper logging
    while IFS= read -r line; do
        case "$line" in
            "[OK] "*)
                _import_success "${line#\[OK\] }"
                ;;
            "[WARN] "*)
                _import_warn "${line#\[WARN\] }"
                ;;
            "[ERROR] "*)
                _import_error "${line#\[ERROR\] }"
                ;;
            "[INFO] "*)
                _import_info "${line#\[INFO\] }"
                ;;
            "-> "*)
                _import_step "${line#-> }"
                ;;
            *)
                [[ -n "$line" ]] && printf '%s\n' "$line"
                ;;
        esac
    done <<<"$ssh_output"

    if [[ $ssh_exit_code -ne 0 ]]; then
        _import_error "SSH command failed (exit code: $ssh_exit_code)"
        return 1
    fi

    return 0
}

return 0
