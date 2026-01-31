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
# 1. /mnt/agent-data mountpoint exists
# 2. At least one of: /.dockerenv OR container cgroup marker
_cai_sync_detect_container() {
    # Condition 1: /mnt/agent-data must be a mountpoint
    if ! mountpoint -q "$_CAI_SYNC_DATA_DIR" 2>/dev/null; then
        # Fallback: check if it's at least a directory (for testing)
        if [[ ! -d "$_CAI_SYNC_DATA_DIR" ]]; then
            return 1
        fi
    fi

    # Condition 2: At least one container indicator must be present
    # Check for /.dockerenv (Docker creates this file)
    if [[ -f "/.dockerenv" ]]; then
        return 0
    fi

    # Check cgroup for container markers (works for Docker, Podman, Sysbox)
    if [[ -f "/proc/1/cgroup" ]]; then
        # Look for docker, lxc, or kubepods in cgroup paths
        if grep -qE '(docker|lxc|kubepods|containerd)' /proc/1/cgroup 2>/dev/null; then
            return 0
        fi
    fi

    # Check for container runtime environment variables
    if [[ -n "${container:-}" ]] || [[ -n "${CONTAINAI_CONTAINER:-}" ]]; then
        return 0
    fi

    # No container indicators found
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

    # Skip if source is already a symlink (already synced or user symlink)
    if [[ -L "$home_source" ]]; then
        local link_target
        link_target="$(readlink -f "$home_source" 2>/dev/null)" || true
        if [[ "$link_target" == "${_CAI_SYNC_DATA_DIR}/"* ]]; then
            printf '[SKIP] %s (already symlinked to volume)\n' "$home_source"
        else
            printf '[SKIP] %s (is a symlink to %s)\n' "$home_source" "$link_target"
        fi
        return 2
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

    # Count items for reporting
    local item_count=1
    if [[ -d "$home_source" ]]; then
        item_count=$(find "$home_source" -type f 2>/dev/null | wc -l)
        item_count="${item_count##*[[:space:]]}"  # Trim whitespace
        item_count="${item_count%%[[:space:]]*}"
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
        # For directories, rsync to merge contents
        if [[ -d "$home_source" && -d "$volume_target" ]]; then
            if ! rsync -a "$home_source/" "$volume_target/" 2>/dev/null; then
                printf '[ERROR] Failed to merge directory: %s\n' "$home_source" >&2
                return 1
            fi
            rm -rf "$home_source"
        # For files, prefer volume version (already synced), just remove source
        elif [[ -f "$home_source" && -f "$volume_target" ]]; then
            rm -f "$home_source"
        else
            printf '[ERROR] Type conflict: %s exists on volume but differs in type\n' "$volume_target" >&2
            return 1
        fi
    else
        # Move source to volume
        if ! mv "$home_source" "$volume_target" 2>/dev/null; then
            printf '[ERROR] Failed to move: %s -> %s\n' "$home_source" "$volume_target" >&2
            return 1
        fi
    fi

    # Handle container_link symlink creation
    # If container_link == source, the symlink replaces the original location
    # If container_link != source, we create symlink at container_link location
    if [[ "$container_link" == "$source" ]]; then
        # Simple case: symlink at original location
        if ! ln -sfn "$volume_target" "$home_source" 2>/dev/null; then
            printf '[ERROR] Failed to create symlink: %s -> %s\n' "$home_source" "$volume_target" >&2
            return 1
        fi
    else
        # Different link name: create at container_link location
        # Ensure parent directory for container_link exists
        local link_parent
        link_parent="$(dirname "$home_link")"
        mkdir -p "$link_parent" 2>/dev/null || true

        # Remove existing file/dir at link location if needed
        if [[ -e "$home_link" && ! -L "$home_link" ]]; then
            rm -rf "$home_link"
        fi

        if ! ln -sfn "$volume_target" "$home_link" 2>/dev/null; then
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

    # Check we're inside a container
    if ! _cai_sync_detect_container; then
        printf '[ERROR] cai sync must be run inside a ContainAI container\n' >&2
        printf '  /mnt/agent-data must be mounted AND container indicators present\n' >&2
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

    # Parse manifest and process entries with non-empty container_link
    local line source target container_link flags disabled entry_type optional
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
    done < <("$parser" "$manifest")

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
