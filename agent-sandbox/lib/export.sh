#!/usr/bin/env bash
# ==============================================================================
# ContainAI Export - cai export subcommand
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _containai_export  - Export data volume to .tgz archive
#
# Usage:
#   source lib/export.sh
#   excludes=("pattern1" "pattern2")
#   _containai_export "volume-name" "/path/to/output.tgz" excludes "false"
#
# Note: config.sh is NOT required for basic export. It's only needed if the
# caller wants to resolve excludes from config (done by containai.sh wrapper).
#
# Arguments (matching spec signature):
#   $1 = volume name (required)
#   $2 = output path (optional, default: ./containai-export-YYYYMMDD-HHMMSS.tgz)
#        If a directory, the default filename is appended.
#   $3 = excludes array name (passed by reference via nameref)
#   $4 = no_excludes flag ("true" or "false", default: "false")
#
# Output: Prints absolute path to archive on stdout (logs go to stderr)
#
# Dependencies:
#   - docker (for tar container)
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/export.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/export.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/export.sh" >&2
    exit 1
fi

# ==============================================================================
# Volume name validation (local copy for independence from config.sh)
# ==============================================================================

# Validate Docker volume name pattern
# Pattern: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
# Length: 1-255 characters
# Returns: 0=valid, 1=invalid
_export_validate_volume_name() {
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
# Output helpers - all logs go to stderr, only archive path to stdout
# ==============================================================================
_export_info() { echo "[INFO] $*" >&2; }
_export_success() { echo "[OK] $*" >&2; }
_export_error() { echo "[ERROR] $*" >&2; }
_export_warn() { echo "[WARN] $*" >&2; }

# ==============================================================================
# Main export function
# ==============================================================================

# Export data volume to .tgz archive
# Arguments:
#   $1 = volume name (required)
#   $2 = output path (optional, default: ./containai-export-YYYYMMDD-HHMMSS.tgz)
#        If a directory or ends with /, the default filename is appended.
#   $3 = excludes array name (passed by reference via nameref, optional)
#   $4 = no_excludes flag ("true" or "false", default: "false")
# Returns: 0 on success, 1 on failure
# Outputs: Absolute archive path to stdout on success
_containai_export() {
    local volume="${1:-}"
    local output_path="${2:-}"
    local excludes_name="${3:-}"
    local no_excludes="${4:-false}"

    # Use nameref to access excludes array by name (bash 4.3+)
    local -a excludes=()
    if [[ -n "$excludes_name" ]]; then
        local -n _excludes_ref="$excludes_name" 2>/dev/null || true
        if [[ -n "${_excludes_ref+x}" ]]; then
            excludes=("${_excludes_ref[@]}")
        fi
    fi

    # Validate required arguments
    if [[ -z "$volume" ]]; then
        _export_error "Volume name is required"
        return 1
    fi

    # Validate volume name
    if ! _export_validate_volume_name "$volume"; then
        _export_error "Invalid volume name: $volume"
        _export_error "Volume names must start with alphanumeric and contain only [a-zA-Z0-9_.-]"
        return 1
    fi

    # Validate prerequisites
    if ! command -v docker >/dev/null 2>&1; then
        _export_error "Docker is not installed or not in PATH"
        return 1
    fi

    # Check Docker daemon is reachable
    if ! docker info >/dev/null 2>&1; then
        _export_error "Cannot connect to Docker daemon"
        return 1
    fi

    # Check that volume exists
    if ! docker volume inspect "$volume" >/dev/null 2>&1; then
        _export_error "Volume does not exist: $volume"
        return 1
    fi

    # Default filename for auto-generated archives
    local default_filename="containai-export-$(date +%Y%m%d-%H%M%S).tgz"

    # Expand leading tilde safely (without eval)
    if [[ "$output_path" == "~/"* ]]; then
        output_path="${HOME}${output_path:1}"
    elif [[ "$output_path" == "~" ]]; then
        output_path="$HOME"
    fi

    # Determine output path - handle directory vs file
    if [[ -z "$output_path" ]]; then
        # No path specified - use default in current directory
        output_path="./$default_filename"
    elif [[ -d "$output_path" ]]; then
        # Path is an existing directory - append default filename
        output_path="${output_path%/}/$default_filename"
    elif [[ "$output_path" == */ ]]; then
        # Path ends with / - treat as directory, append default filename
        output_path="${output_path}$default_filename"
    fi

    # Resolve output path to absolute
    local output_dir output_basename output_abs_path
    output_dir=$(dirname "$output_path")
    output_basename=$(basename "$output_path")

    # Validate output directory exists
    if [[ ! -d "$output_dir" ]]; then
        _export_error "Output directory doesn't exist: $output_dir"
        return 1
    fi

    # Check output directory is writable
    if [[ ! -w "$output_dir" ]]; then
        _export_error "Output directory is not writable: $output_dir"
        return 1
    fi

    # Resolve to absolute path
    if ! output_dir=$(cd "$output_dir" 2>/dev/null && pwd); then
        _export_error "Cannot access output directory: $(dirname "$output_path")"
        return 1
    fi
    output_abs_path="$output_dir/$output_basename"

    _export_info "Exporting volume '$volume' to: $output_abs_path"

    # Build tar exclude flags (unless --no-excludes)
    # Note: Use separate --exclude and pattern args for BusyBox tar compatibility
    # With `tar -C /data .`, archived paths have leading ./ (e.g., ./claude/settings.json)
    # Pass both forms (with and without ./) for maximum compatibility across tar versions
    local -a tar_excludes=()
    if [[ "$no_excludes" != "true" ]] && [[ ${#excludes[@]} -gt 0 ]]; then
        local pattern normalized
        for pattern in "${excludes[@]}"; do
            # Strip leading ./ if present to get normalized form
            normalized="${pattern#./}"
            # Skip empty patterns
            [[ -z "$normalized" ]] && continue
            # Add both forms: ./path and path for tar compatibility
            tar_excludes+=(--exclude "./$normalized" --exclude "$normalized")
        done
    fi

    # Build the tar command as an array for safe quoting
    local -a tar_cmd=(tar -czf "/out/$output_basename")
    if [[ ${#tar_excludes[@]} -gt 0 ]]; then
        tar_cmd+=("${tar_excludes[@]}")
    fi
    tar_cmd+=(-C /data .)

    # Get current user's uid:gid for proper file ownership
    local user_id group_id
    user_id=$(id -u)
    group_id=$(id -g)

    # Run tar via docker container mounting the volume read-only
    # Output directory is mounted for writing the archive
    # Use --user to ensure output file is owned by invoking user
    if ! docker run --rm --network=none \
        --user "${user_id}:${group_id}" \
        -v "${volume}:/data:ro" \
        -v "${output_dir}:/out" \
        alpine \
        "${tar_cmd[@]}"; then
        _export_error "Failed to create archive"
        return 1
    fi

    # Verify archive was created
    if [[ ! -f "$output_abs_path" ]]; then
        _export_error "Archive was not created: $output_abs_path"
        return 1
    fi

    _export_success "Exported to: $output_abs_path"

    # Output archive path (for programmatic use)
    echo "$output_abs_path"

    return 0
}

return 0
