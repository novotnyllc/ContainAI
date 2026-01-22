#!/usr/bin/env bash
# ==============================================================================
# ContainAI Docker Interaction Helpers
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_docker_available()          - Check if Docker is available and running
#   _cai_docker_version()            - Get Docker daemon version
#   _cai_docker_desktop_version()    - Get Docker Desktop version as semver (empty if not DD)
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
# Portable timeout wrapper
# ==============================================================================

# Portable timeout command wrapper
# macOS doesn't have 'timeout' by default; use gtimeout (from coreutils) or perl fallback
# Arguments: $1 = timeout in seconds, $@ = command to run
# Returns: command exit code, or 124 on timeout
_cai_timeout() {
    local secs="$1"
    shift

    # Prefer 'timeout' (Linux, coreutils)
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
        return $?
    fi

    # Try 'gtimeout' (macOS with coreutils installed via brew)
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
        return $?
    fi

    # Perl-based fallback (available on most systems including macOS)
    if command -v perl >/dev/null 2>&1; then
        perl -e '
            use strict;
            use warnings;
            my $timeout = shift @ARGV;
            my $pid = fork();
            if (!defined $pid) { die "fork failed: $!"; }
            if ($pid == 0) {
                exec @ARGV or die "exec failed: $!";
            }
            eval {
                local $SIG{ALRM} = sub { die "timeout\n"; };
                alarm($timeout);
                waitpid($pid, 0);
                alarm(0);
            };
            if ($@ && $@ eq "timeout\n") {
                kill 9, $pid;
                waitpid($pid, 0);
                exit 124;
            }
            exit($? >> 8);
        ' "$secs" "$@"
        return $?
    fi

    # No timeout mechanism available - set flag and return special exit code 125
    # Exit code 125 signals "no timeout available" so callers can provide remediation
    # We don't print here because stderr is often captured/redirected
    _CAI_TIMEOUT_UNAVAILABLE=1
    return 125
}

# ==============================================================================
# Docker availability checks
# ==============================================================================

# Check if Docker CLI is available
# Returns: 0=available, 1=not available
_cai_docker_cli_available() {
    command -v docker >/dev/null 2>&1
}

# Check if Docker daemon is accessible (with timeout to avoid hanging)
# Returns: 0=accessible, 1=not accessible
# Outputs: Sets _CAI_DAEMON_ERROR with error details
_cai_docker_daemon_available() {
    local output rc
    output=$(_cai_timeout 5 docker info 2>&1) && rc=0 || rc=$?

    # No timeout mechanism available (exit code 125)
    if [[ $rc -eq 125 ]]; then
        _CAI_DAEMON_ERROR="no_timeout"
        return 1
    fi

    # Timeout (exit code 124)
    if [[ $rc -eq 124 ]]; then
        _CAI_DAEMON_ERROR="timeout"
        return 1
    fi

    # Success
    if [[ $rc -eq 0 ]]; then
        _CAI_DAEMON_ERROR=""
        return 0
    fi

    # Analyze error for specific failure modes
    if printf '%s' "$output" | grep -qiE "permission denied"; then
        _CAI_DAEMON_ERROR="permission"
    elif printf '%s' "$output" | grep -qiE "daemon.*not running|connection refused|Is the docker daemon running|Cannot connect"; then
        _CAI_DAEMON_ERROR="not_running"
    elif printf '%s' "$output" | grep -qiE "context|DOCKER_HOST|socket"; then
        _CAI_DAEMON_ERROR="context"
    else
        _CAI_DAEMON_ERROR="unknown"
    fi
    return 1
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
            case "${_CAI_DAEMON_ERROR:-unknown}" in
                no_timeout)
                    _cai_error "No timeout command available (timeout, gtimeout, or perl required)"
                    _cai_error "  Install coreutils: brew install coreutils (macOS) or apt install coreutils (Linux)"
                    ;;
                timeout)
                    _cai_error "Docker command timed out"
                    _cai_error "  Check DOCKER_CONTEXT / daemon reachability"
                    ;;
                permission)
                    _cai_error "Permission denied accessing Docker"
                    _cai_error "  Ensure Docker Desktop is running, or add user to docker group"
                    ;;
                not_running)
                    _cai_error "Docker Desktop is not running"
                    _cai_error "  Start Docker Desktop and try again"
                    ;;
                context)
                    _cai_error "Docker context or connection issue"
                    _cai_error "  Check DOCKER_CONTEXT / DOCKER_HOST settings"
                    ;;
                *)
                    _cai_error "Docker daemon is not accessible"
                    ;;
            esac
        fi
        return 1
    fi

    return 0
}

# ==============================================================================
# Docker version detection
# ==============================================================================

# Get Docker daemon version
# Outputs: Version string (e.g., "27.5.1")
# Returns: 0=success, 1=docker unavailable
_cai_docker_version() {
    if ! _cai_docker_cli_available; then
        return 1
    fi

    local version_output
    if ! version_output=$(_cai_timeout 5 docker version --format '{{.Server.Version}}' 2>/dev/null); then
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

# Get Docker Desktop version as semver string
# Outputs: Version string (e.g., "4.50.1") or empty if not Docker Desktop
# Returns: 0=Docker Desktop detected (version output), 1=not Docker Desktop or error
# Note: Uses timeout to avoid hanging when Docker is not running
# Sets _CAI_DD_VERSION_ERROR for callers who need to distinguish failure modes
_cai_docker_desktop_version() {
    _CAI_DD_VERSION_ERROR=""

    if ! _cai_docker_cli_available; then
        _CAI_DD_VERSION_ERROR="no_cli"
        return 1
    fi

    # Get Platform.Name which contains "Docker Desktop X.Y.Z" on Docker Desktop
    # On non-Docker Desktop (colima, docker-ce, etc) this returns different values
    # Use single docker call with temp file to capture both stdout and stderr
    local platform_name rc tmpfile
    tmpfile=$(mktemp)
    # Capture stderr to temp file, stdout to variable
    platform_name=$(_cai_timeout 5 docker version --format '{{.Server.Platform.Name}}' 2>"$tmpfile") && rc=0 || rc=$?
    local stderr_output
    stderr_output=$(cat "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"

    # Timeout
    if [[ $rc -eq 124 ]]; then
        _CAI_DD_VERSION_ERROR="timeout"
        return 1
    fi

    # Other error - check if it's permission/daemon issue vs not Docker Desktop
    if [[ $rc -ne 0 ]]; then
        if printf '%s' "$stderr_output" | grep -qiE "permission denied"; then
            _CAI_DD_VERSION_ERROR="permission"
        elif printf '%s' "$stderr_output" | grep -qiE "daemon.*not running|connection refused|Cannot connect"; then
            _CAI_DD_VERSION_ERROR="not_running"
        else
            _CAI_DD_VERSION_ERROR="error"
        fi
        return 1
    fi

    # Check if this is Docker Desktop - the string should contain "Docker Desktop"
    # Examples: "Docker Desktop 4.50.0", "Docker Desktop 4.50.1 (abcdef)"
    if [[ "$platform_name" != *"Docker Desktop"* ]]; then
        # Not Docker Desktop (could be: "Docker Engine - Community", "colima", etc.)
        _CAI_DD_VERSION_ERROR="not_docker_desktop"
        return 1
    fi

    # Extract version from "Docker Desktop X.Y.Z" or "Docker Desktop X.Y.Z (build)"
    # Remove "Docker Desktop " prefix
    local version="${platform_name#Docker Desktop }"

    # Remove anything after version number (build info, etc)
    # Version is digits and dots at the start: "4.50.1 (abcdef)" -> "4.50.1"
    version="${version%% *}"

    # Strip pre-release suffixes like "-beta" to get clean semver major.minor.patch
    # Note: We intentionally strip pre-release metadata for version comparison
    version="${version%%[^0-9.]*}"

    # Validate we got something that looks like a version
    if [[ -z "$version" ]]; then
        return 1
    fi

    # Validate and normalize semver format (major.minor.patch)
    # Accept X.Y or X.Y.Z, normalize to X.Y.Z
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        return 1
    fi
    # Normalize X.Y to X.Y.0 for consistent semver output
    if [[ ! "$version" =~ \.[0-9]+\.[0-9]+$ ]]; then
        version="${version}.0"
    fi

    printf '%s' "$version"
    return 0
}

return 0
