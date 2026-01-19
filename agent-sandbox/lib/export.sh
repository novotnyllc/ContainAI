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
#   _containai_export "volume-name" "" "false" "pattern1" "pattern2"
#
# Note: config.sh is NOT required for basic export. It's only needed if the
# caller wants to resolve excludes from config (done by containai.sh wrapper).
#
# Arguments:
#   $1 = volume name (required)
#   $2 = output path (optional, default: ./containai-export-YYYYMMDD-HHMMSS.tgz)
#   $3 = no_excludes flag ("true" or "false", default: "false")
#   $@ = exclude patterns (remaining arguments, applied unless no_excludes)
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
#   $3 = no_excludes flag ("true" or "false", default: "false")
#   $@ = remaining args are exclude patterns
# Returns: 0 on success, 1 on failure
# Outputs: Archive path on success
_containai_export() {
    local volume="${1:-}"
    local output_path="${2:-}"
    local no_excludes="${3:-false}"
    shift 3 2>/dev/null || shift $#
    local -a excludes=("$@")

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

    # Determine output path
    if [[ -z "$output_path" ]]; then
        output_path="./containai-export-$(date +%Y%m%d-%H%M%S).tgz"
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

    # Resolve to absolute path
    if ! output_dir=$(cd "$output_dir" 2>/dev/null && pwd); then
        _export_error "Cannot access output directory: $(dirname "$output_path")"
        return 1
    fi
    output_abs_path="$output_dir/$output_basename"

    _export_info "Exporting volume '$volume' to: $output_abs_path"

    # Build tar exclude flags (unless --no-excludes)
    # Note: Use separate --exclude and pattern args for BusyBox tar compatibility
    local -a tar_excludes=()
    if [[ "$no_excludes" != "true" ]] && [[ ${#excludes[@]} -gt 0 ]]; then
        local pattern
        for pattern in "${excludes[@]}"; do
            tar_excludes+=(--exclude "$pattern")
        done
    fi

    # Build the tar command as an array for safe quoting
    local -a tar_cmd=(tar -czf "/out/$output_basename")
    if [[ ${#tar_excludes[@]} -gt 0 ]]; then
        tar_cmd+=("${tar_excludes[@]}")
    fi
    tar_cmd+=(-C /data .)

    # Run tar via docker container mounting the volume read-only
    # Output directory is mounted for writing the archive
    if ! docker run --rm --network=none \
        -v "${volume}:/data:ro" \
        -v "${output_dir}:/out" \
        alpine:latest \
        "${tar_cmd[@]}"; then
        _export_error "Failed to create archive"
        return 1
    fi

    _export_success "Exported to: $output_abs_path"

    # Output archive path (for programmatic use)
    echo "$output_abs_path"

    return 0
}

return 0
