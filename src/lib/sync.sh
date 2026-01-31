#!/usr/bin/env bash
# ==============================================================================
# ContainAI Sync Library - In-container config sync to data volume
# ==============================================================================
# Provides `cai sync` functionality for moving user configs to the data volume
# and replacing them with symlinks. This allows container customizations to
# persist across container recreations.
#
# Security:
# - Only runs inside containers (multiple signal detection)
# - Validates paths with realpath before operations
# - Rejects paths containing symlinks
# - Verifies resolved paths are under /mnt/agent-data
#
# Usage: cai sync [--dry-run]
# ==============================================================================

# Data directory constant
readonly _CAI_SYNC_DATA_DIR="/mnt/agent-data"

# Manifest location (built into container image)
readonly _CAI_SYNC_MANIFEST="/opt/containai/sync-manifest.toml"

# Parse manifest script location (container vs development)
_cai_sync_get_parse_script() {
    # In container, use installed location first
    if [[ -f "/opt/containai/scripts/parse-manifest.sh" ]]; then
        printf '%s' "/opt/containai/scripts/parse-manifest.sh"
    # In development, use repo location
    elif [[ -f "${_CAI_SCRIPT_DIR}/scripts/parse-manifest.sh" ]]; then
        printf '%s' "${_CAI_SCRIPT_DIR}/scripts/parse-manifest.sh"
    # Fallback - look for manifest parser in parent directory
    elif [[ -f "${_CAI_SCRIPT_DIR}/../scripts/parse-manifest.sh" ]]; then
        printf '%s' "${_CAI_SCRIPT_DIR}/../scripts/parse-manifest.sh"
    else
        return 1
    fi
}

# Get manifest path (container vs development)
_cai_sync_get_manifest() {
    # In container, use installed location first
    if [[ -f "$_CAI_SYNC_MANIFEST" ]]; then
        printf '%s' "$_CAI_SYNC_MANIFEST"
    # In development, use repo location
    elif [[ -f "${_CAI_SCRIPT_DIR}/sync-manifest.toml" ]]; then
        printf '%s' "${_CAI_SCRIPT_DIR}/sync-manifest.toml"
    # Fallback - try parent directory
    elif [[ -f "${_CAI_SCRIPT_DIR}/../sync-manifest.toml" ]]; then
        printf '%s' "${_CAI_SCRIPT_DIR}/../sync-manifest.toml"
    else
        return 1
    fi
}

# Detect if we're running inside a container
# Requires BOTH conditions:
# 1. /mnt/agent-data must be a mountpoint (strict - no directory fallback)
# 2. At least one of: /.dockerenv OR container cgroup marker
_cai_sync_detect_container() {
    # Condition 1: /mnt/agent-data must be a mountpoint (REQUIRED)
    # Use mountpoint command if available, otherwise parse /proc/self/mountinfo
    if command -v mountpoint >/dev/null 2>&1; then
        if ! mountpoint -q "$_CAI_SYNC_DATA_DIR" 2>/dev/null; then
            return 1
        fi
    elif [[ -f /proc/self/mountinfo ]]; then
        # Parse mountinfo to check if path is a mountpoint
        if ! grep -q " ${_CAI_SYNC_DATA_DIR} " /proc/self/mountinfo 2>/dev/null; then
            return 1
        fi
    else
        # Cannot verify mountpoint - fail closed
        return 1
    fi

    # Condition 2: At least one container indicator must be present
    # Check for /.dockerenv (Docker creates this file)
    if [[ -f "/.dockerenv" ]]; then
        return 0
    fi

    # Check cgroup for container markers (works for Docker, Podman, Sysbox)
    if [[ -f "/proc/1/cgroup" ]]; then
        # Look for docker, lxc, or kubepods in cgroup paths
        # Note: Using ERE (-E) is intentional here - this code only runs in containers
        # where GNU grep is available (Linux containers with /proc filesystem)
        if grep -qE '(docker|lxc|kubepods|containerd)' /proc/1/cgroup 2>/dev/null; then
            return 0
        fi
    fi

    # No container indicators found (env vars alone are not sufficient)
    return 1
}

# Verify path resolves under data directory (prevents symlink traversal)
_cai_sync_verify_path_under_data() {
    local path="$1"
    local resolved

    resolved="$(realpath -m "$path" 2>/dev/null)" || {
        return 1
    }

    # Check path is under data directory (with trailing slash to prevent prefix attacks)
    if [[ "$resolved" == "${_CAI_SYNC_DATA_DIR}" || "$resolved" == "${_CAI_SYNC_DATA_DIR}/"* ]]; then
        return 0
    fi

    return 1
}

# Verify path resolves under HOME directory (prevents .. traversal escapes)
_cai_sync_verify_path_under_home() {
    local path="$1"
    local resolved

    resolved="$(realpath -m "$path" 2>/dev/null)" || {
        return 1
    }

    # Check path is under HOME (with trailing slash to prevent prefix attacks)
    if [[ "$resolved" == "${HOME}" || "$resolved" == "${HOME}/"* ]]; then
        return 0
    fi

    return 1
}

# Check for required external commands
_cai_sync_check_dependencies() {
    local missing=()

    if ! command -v realpath >/dev/null 2>&1; then
        missing+=("realpath")
    fi
    if ! command -v rsync >/dev/null 2>&1; then
        missing+=("rsync")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf '[ERROR] Missing required commands: %s\n' "${missing[*]}" >&2
        return 1
    fi
    return 0
}

# Reject paths containing symlinks (for security-sensitive operations)
_cai_sync_reject_symlinks_in_path() {
    local path="$1"
    local current=""
    local segment

    # Walk each path component and check for symlinks
    # Use IFS to split on /
    while IFS= read -r -d '/' segment || [[ -n "$segment" ]]; do
        [[ -z "$segment" ]] && continue
        current="${current}/${segment}"
        if [[ -L "$current" ]]; then
            return 1
        fi
    done <<< "$path"

    return 0
}

# Helper to print dry-run messages (always visible, bypasses verbose gating)
_cai_sync_dryrun() {
    printf '[DRY-RUN] %s\n' "$*" >&2
}

# Sync a single entry from home to data volume
# Arguments: source target container_link dry_run
# Returns: 0=synced, 1=error, 2=skipped
_cai_sync_entry() {
    local source="$1"
    local target="$2"
    local container_link="$3"
    local dry_run="$4"

    local home_source="${HOME}/${source}"
    local volume_target="${_CAI_SYNC_DATA_DIR}/${target}"
    local home_link="${HOME}/${container_link}"

    # Skip if source doesn't exist
    if [[ ! -e "$home_source" ]]; then
        return 2
    fi

    # Handle if source is already a symlink
    if [[ -L "$home_source" ]]; then
        local link_target
        link_target="$(readlink -f "$home_source" 2>/dev/null)" || true
        if [[ "$link_target" == "${_CAI_SYNC_DATA_DIR}/"* ]]; then
            # Already synced to volume - this is expected, skip silently
            printf '[SKIP] %s (already symlinked to volume)\n' "$home_source"
            return 2
        else
            # User symlink pointing elsewhere - warn and count as failure
            printf '[WARN] %s is a symlink to %s (resolve manually)\n' "$home_source" "$link_target" >&2
            return 1
        fi
    fi

    # Security: verify source path stays under HOME (prevents .. traversal)
    if ! _cai_sync_verify_path_under_home "$home_source"; then
        printf '[ERROR] Source path escapes HOME directory: %s\n' "$home_source" >&2
        return 1
    fi

    # Security: verify link path stays under HOME (prevents .. traversal)
    if ! _cai_sync_verify_path_under_home "$home_link"; then
        printf '[ERROR] Container link path escapes HOME directory: %s\n' "$home_link" >&2
        return 1
    fi

    # Security: verify target path would be under data directory
    if ! _cai_sync_verify_path_under_data "$volume_target"; then
        printf '[ERROR] Target path escapes data directory: %s\n' "$volume_target" >&2
        return 1
    fi

    # Security: reject if source path contains symlinks in its ancestors
    if ! _cai_sync_reject_symlinks_in_path "$(dirname "$home_source")"; then
        printf '[ERROR] Source path contains symlinks: %s\n' "$home_source" >&2
        return 1
    fi

    # Count items for reporting (use tr to reliably strip whitespace from wc output)
    local item_count=1
    if [[ -d "$home_source" ]]; then
        item_count=$(find "$home_source" -type f 2>/dev/null | wc -l | tr -d '[:space:]')
        [[ -z "$item_count" ]] && item_count=0
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_sync_dryrun "Would move: $home_source -> $volume_target"
        _cai_sync_dryrun "Would create symlink: $home_link -> $volume_target"
        return 0
    fi

    # Ensure target parent directory exists
    local target_parent
    target_parent="$(dirname "$volume_target")"
    if ! mkdir -p "$target_parent" 2>/dev/null; then
        printf '[ERROR] Cannot create target directory: %s\n' "$target_parent" >&2
        return 1
    fi

    # If target already exists on volume, we need to merge or handle conflict
    if [[ -e "$volume_target" ]]; then
        # For directories, rsync to merge contents (local source wins on conflicts)
        if [[ -d "$home_source" && -d "$volume_target" ]]; then
            if ! rsync -a "$home_source/" "$volume_target/" 2>/dev/null; then
                printf '[ERROR] Failed to merge directory: %s\n' "$home_source" >&2
                return 1
            fi
            # Remove source after merge - fail closed if removal fails
            if ! rm -rf "$home_source" 2>/dev/null || [[ -e "$home_source" ]]; then
                printf '[ERROR] Failed to remove source after merge: %s\n' "$home_source" >&2
                return 1
            fi
        # For files, prefer local source (user's newer changes) - overwrite volume
        elif [[ -f "$home_source" && -f "$volume_target" ]]; then
            if ! mv -f -- "$home_source" "$volume_target" 2>/dev/null; then
                printf '[ERROR] Failed to overwrite volume file: %s\n' "$volume_target" >&2
                return 1
            fi
        else
            printf '[ERROR] Type conflict: %s exists on volume but differs in type\n' "$volume_target" >&2
            return 1
        fi
    else
        # Move source to volume
        if ! mv -- "$home_source" "$volume_target" 2>/dev/null; then
            printf '[ERROR] Failed to move: %s -> %s\n' "$home_source" "$volume_target" >&2
            return 1
        fi
    fi

    # Handle container_link symlink creation
    # If container_link == source, the symlink replaces the original location
    # If container_link != source, we create symlink at container_link location
    if [[ "$container_link" == "$source" ]]; then
        # Simple case: symlink at original location
        if ! ln -sfn -- "$volume_target" "$home_source" 2>/dev/null; then
            printf '[ERROR] Failed to create symlink: %s -> %s\n' "$home_source" "$volume_target" >&2
            return 1
        fi
    else
        # Different link name: create at container_link location
        local link_parent
        link_parent="$(dirname "$home_link")"

        # Security: reject if container_link parent path contains symlinks
        if ! _cai_sync_reject_symlinks_in_path "$link_parent"; then
            printf '[ERROR] Container link parent path contains symlinks: %s\n' "$link_parent" >&2
            return 1
        fi

        # Security: verify link parent resolves under $HOME
        local resolved_parent
        resolved_parent="$(realpath -m "$link_parent" 2>/dev/null)" || {
            printf '[ERROR] Cannot resolve container link parent: %s\n' "$link_parent" >&2
            return 1
        }
        if [[ "$resolved_parent" != "${HOME}" && "$resolved_parent" != "${HOME}/"* ]]; then
            printf '[ERROR] Container link parent escapes HOME: %s -> %s\n' "$link_parent" "$resolved_parent" >&2
            return 1
        fi

        # Ensure parent directory exists (fail-closed on errors)
        if ! mkdir -p "$link_parent" 2>/dev/null; then
            printf '[ERROR] Cannot create container link parent directory: %s\n' "$link_parent" >&2
            return 1
        fi

        # Refuse to overwrite existing file/dir at link location (safety)
        if [[ -e "$home_link" && ! -L "$home_link" ]]; then
            printf '[ERROR] Container link location exists and is not a symlink: %s\n' "$home_link" >&2
            printf '  Move or remove it manually before running cai sync\n' >&2
            return 1
        fi

        if ! ln -sfn -- "$volume_target" "$home_link" 2>/dev/null; then
            printf '[ERROR] Failed to create symlink: %s -> %s\n' "$home_link" "$volume_target" >&2
            return 1
        fi
    fi

    printf '[OK] ~/%s -> %s (moved %d files)\n' "$source" "$volume_target" "$item_count"
    return 0
}

# Main sync command
_cai_sync_cmd() {
    local dry_run="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --verbose)
                _cai_set_verbose
                shift
                ;;
            --help | -h)
                _cai_sync_help
                return 0
                ;;
            -*)
                printf '[ERROR] Unknown option: %s\n' "$1" >&2
                _cai_sync_help >&2
                return 1
                ;;
            *)
                printf '[ERROR] Unexpected argument: %s\n' "$1" >&2
                _cai_sync_help >&2
                return 1
                ;;
        esac
    done

    # Check we're inside a container (do this first to give clear error on host)
    if ! _cai_sync_detect_container; then
        printf '[ERROR] cai sync must be run inside a ContainAI container\n' >&2
        printf '  /mnt/agent-data must be mounted AND container indicators present\n' >&2
        return 1
    fi

    # Check required commands are available
    if ! _cai_sync_check_dependencies; then
        return 1
    fi

    # Find manifest and parser
    local manifest
    local parser
    if ! manifest="$(_cai_sync_get_manifest)"; then
        printf '[ERROR] Cannot find sync-manifest.toml\n' >&2
        return 1
    fi
    if ! parser="$(_cai_sync_get_parse_script)"; then
        printf '[ERROR] Cannot find parse-manifest.sh\n' >&2
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_sync_dryrun "Syncing local configs to data volume..."
    else
        _cai_info "Syncing local configs to data volume..."
    fi

    local synced=0
    local skipped=0
    local failed=0

    # Parse manifest - capture output and detect parser errors
    # Use a subshell to avoid global trap side effects
    local parser_output parser_error
    parser_error=""
    parser_output=$("$parser" "$manifest" 2>&1) || {
        parser_error="$parser_output"
    }

    if [[ -n "$parser_error" ]]; then
        printf '[ERROR] Failed to parse manifest: %s\n' "$manifest" >&2
        printf '%s\n' "$parser_error" >&2
        return 1
    fi

    # Process manifest entries with non-empty container_link
    local source target container_link flags disabled entry_type optional
    while IFS='|' read -r source target container_link flags disabled entry_type optional; do
        # Skip container_symlinks (type=symlink) - these have no source to sync
        [[ "$entry_type" == "symlink" ]] && continue

        # Skip entries without source (container-only symlinks)
        [[ -z "$source" ]] && continue

        # Skip entries without container_link (copy-only, not symlinked)
        [[ -z "$container_link" ]] && continue

        # Skip disabled entries
        [[ "$disabled" == "true" ]] && continue

        # Skip glob patterns (G flag)
        [[ "$flags" == *G* ]] && continue

        # Process entry and track result
        # Return codes: 0=synced, 1=error, 2=skipped
        local result=0
        _cai_sync_entry "$source" "$target" "$container_link" "$dry_run" || result=$?

        case $result in
            0) synced=$((synced + 1)) ;;
            1) failed=$((failed + 1)) ;;
            2) skipped=$((skipped + 1)) ;;
        esac
    done <<< "$parser_output"

    # Summary
    if [[ "$dry_run" == "true" ]]; then
        _cai_sync_dryrun "Done. $synced paths would be synced."
    else
        _cai_info "Done. $synced paths synced, $skipped skipped."
    fi

    if [[ $failed -gt 0 ]]; then
        printf '[WARN] %d paths failed to sync\n' "$failed" >&2
        return 1
    fi

    return 0
}

# Help text for sync command
_cai_sync_help() {
    cat <<'EOF'
ContainAI Sync - Move local configs to data volume

Usage: cai sync [options]

Moves user configuration from $HOME to /mnt/agent-data and creates symlinks.
This allows container customizations to persist across container recreations.

Only processes manifest entries with non-empty container_link values.
Entries like .gitconfig (copy-only) are not converted to symlinks.

Options:
  --dry-run     Show what would happen without making changes
  --verbose     Show detailed output
  -h, --help    Show this help message

Security:
  - Only runs inside ContainAI containers (detects /.dockerenv, cgroups)
  - Validates all paths with realpath before operations
  - Rejects paths containing symlinks
  - Verifies target paths are under /mnt/agent-data

Examples:
  cai sync                  Sync all eligible configs to volume
  cai sync --dry-run        Preview what would be synced

What gets synced:
  - Agent configs (.claude, .codex, .gemini, etc.)
  - Shell customizations (.bash_aliases, .bashrc.d)
  - Editor configs (.vimrc, .config/nvim)
  - Git settings (.gitignore_global)

What does NOT get synced:
  - .gitconfig (copied at container startup, not symlinked)
  - SSH keys (not in manifest by default)
  - Files without container_link in manifest
EOF
}
