#!/usr/bin/env bash
# ==============================================================================
# ContainAI Docker Interaction Helpers
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_docker_available()   - Check if Docker is available and running
#   _cai_docker_version()     - Get Docker Desktop version (or daemon version)
#   _cai_sandbox_available()  - Check if 'docker sandbox' is available
#   _cai_sandbox_version()    - Get docker sandbox version if available
#
# Dependencies:
#   - Requires lib/core.sh to be sourced first for logging functions
#
# Usage: source lib/docker.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/docker.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/docker.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/docker.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_DOCKER_LOADED:-}" ]]; then
    return 0
fi
_CAI_DOCKER_LOADED=1

# ==============================================================================
# Docker availability checks
# ==============================================================================

# Check if Docker CLI is available
# Returns: 0=available, 1=not available
_cai_docker_cli_available() {
    command -v docker >/dev/null 2>&1
}

# Check if Docker daemon is accessible
# Returns: 0=accessible, 1=not accessible
_cai_docker_daemon_available() {
    docker info >/dev/null 2>&1
}

# Check if Docker is available (CLI + daemon)
# Returns: 0=available, 1=not available (with error message if verbose)
# Arguments: $1 = verbose flag ("verbose" to print errors)
_cai_docker_available() {
    local verbose="${1:-}"

    if ! _cai_docker_cli_available; then
        if [[ "$verbose" == "verbose" ]] && declare -f _cai_error >/dev/null 2>&1; then
            _cai_error "Docker is not installed or not in PATH"
        fi
        return 1
    fi

    if ! _cai_docker_daemon_available; then
        if [[ "$verbose" == "verbose" ]] && declare -f _cai_error >/dev/null 2>&1; then
            _cai_error "Docker daemon is not accessible"
        fi
        return 1
    fi

    return 0
}

# ==============================================================================
# Docker version detection
# ==============================================================================

# Get Docker version
# Outputs: Version string (e.g., "27.5.1" or "Docker Desktop 4.50.0")
# Returns: 0=success, 1=docker unavailable
_cai_docker_version() {
    if ! _cai_docker_cli_available; then
        return 1
    fi

    local version_output
    if ! version_output=$(docker version --format '{{.Server.Version}}' 2>/dev/null); then
        # Fallback: try simpler format
        if ! version_output=$(docker --version 2>/dev/null); then
            return 1
        fi
        # Parse "Docker version X.Y.Z, ..." format
        version_output="${version_output#Docker version }"
        version_output="${version_output%%,*}"
    fi

    printf '%s' "$version_output"
    return 0
}

# ==============================================================================
# Docker Sandbox detection
# ==============================================================================

# Check if docker sandbox command is available
# Returns: 0=available, 1=not available, 2=unknown (fail-open with warning)
# Note: This checks if the 'docker sandbox' subcommand exists and responds
_cai_sandbox_available() {
    if ! _cai_docker_cli_available; then
        return 1
    fi

    # Check if sandbox command is available by trying to run 'docker sandbox ls'
    local ls_output
    if ls_output=$(docker sandbox ls 2>&1); then
        return 0
    fi

    # Sandbox ls failed - analyze the error
    # Pattern: command not found/unknown command = not available
    if printf '%s' "$ls_output" | grep -qiE "not recognized|unknown command|not a docker command|command not found"; then
        return 1
    fi

    # Pattern: feature disabled/not enabled = not available
    if printf '%s' "$ls_output" | grep -qiE "feature.*disabled|not enabled|requirements.*not met|sandbox.*unavailable" && \
       ! printf '%s' "$ls_output" | grep -qiE "no sandboxes"; then
        return 1
    fi

    # Pattern: empty list = available (just no sandboxes yet)
    if printf '%s' "$ls_output" | grep -qiE "no sandboxes found|0 sandboxes|sandbox list is empty"; then
        return 0
    fi

    # Pattern: daemon not running = not accessible
    if printf '%s' "$ls_output" | grep -qiE "daemon.*not running|connection refused|Is the docker daemon running"; then
        return 1
    fi

    # Pattern: permission denied = not accessible
    if printf '%s' "$ls_output" | grep -qiE "permission denied"; then
        return 1
    fi

    # Unknown error - warn and return 2 (fail-open, let caller decide)
    if declare -f _cai_warn >/dev/null 2>&1; then
        _cai_warn "Could not determine docker sandbox availability (unknown response)"
    fi
    return 2
}

# Get docker sandbox version if available
# Outputs: Version string (e.g., "0.1.0")
# Returns: 0=success, 1=sandbox unavailable
_cai_sandbox_version() {
    if ! _cai_sandbox_available; then
        return 1
    fi

    local version_output
    if ! version_output=$(docker sandbox version 2>/dev/null); then
        return 1
    fi

    # Parse version output - typically "docker sandbox version X.Y.Z"
    # Extract just the version number
    local version
    version="${version_output##*version }"
    version="${version%% *}"

    if [[ -z "$version" ]]; then
        # Fallback: output raw
        printf '%s' "$version_output"
    else
        printf '%s' "$version"
    fi

    return 0
}

return 0
