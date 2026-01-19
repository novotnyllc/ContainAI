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
#   _cai_sandbox_available()         - Check if 'docker sandbox' is available (0/1)
#   _cai_sandbox_feature_enabled()   - Check if sandbox feature is enabled (admin policy check)
#   _cai_sandbox_version()           - Get docker sandbox version if available
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

    # No timeout mechanism available - run without timeout and warn
    if declare -f _cai_warn >/dev/null 2>&1; then
        _cai_warn "No timeout command available; command may hang if daemon is unresponsive"
    fi
    "$@"
    return $?
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
# Outputs: On verbose mode, sets _CAI_DAEMON_ERROR with error details
_cai_docker_daemon_available() {
    local output rc
    output=$(_cai_timeout 5 docker info 2>&1) && rc=0 || rc=$?

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
                timeout)
                    _cai_error "Docker command timed out"
                    _cai_error "  Check DOCKER_CONTEXT / daemon reachability"
                    ;;
                permission)
                    _cai_error "Permission denied accessing Docker"
                    _cai_error "  Ensure Docker Desktop is running, or add user to docker group"
                    ;;
                not_running)
                    _cai_error "Docker daemon is not running"
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
_cai_docker_desktop_version() {
    if ! _cai_docker_cli_available; then
        return 1
    fi

    # Get Platform.Name which contains "Docker Desktop X.Y.Z" on Docker Desktop
    # On non-Docker Desktop (colima, docker-ce, etc) this returns different values
    local platform_name rc
    platform_name=$(_cai_timeout 5 docker version --format '{{.Server.Platform.Name}}' 2>/dev/null) && rc=0 || rc=$?

    # Timeout or error
    if [[ $rc -ne 0 ]]; then
        return 1
    fi

    # Check if this is Docker Desktop - the string should contain "Docker Desktop"
    # Examples: "Docker Desktop 4.50.0", "Docker Desktop 4.50.1 (abcdef)"
    if [[ "$platform_name" != *"Docker Desktop"* ]]; then
        # Not Docker Desktop (could be: "Docker Engine - Community", "colima", etc.)
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

    # Validate semver format (at least major.minor)
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+ ]]; then
        return 1
    fi

    printf '%s' "$version"
    return 0
}

# ==============================================================================
# Docker Sandbox detection
# ==============================================================================

# Check if docker sandbox plugin/command is available
# Returns: 0=available, 1=not available
# Note: This checks if the 'docker sandbox' subcommand exists
# Use _cai_sandbox_feature_enabled() to check if the feature is actually usable
_cai_sandbox_available() {
    if ! _cai_docker_cli_available; then
        return 1
    fi

    # Try 'docker sandbox version' - fastest way to check if plugin exists
    local version_output rc
    version_output=$(_cai_timeout 5 docker sandbox version 2>&1) && rc=0 || rc=$?

    # Success
    if [[ $rc -eq 0 ]]; then
        return 0
    fi

    # Timeout - can't determine availability
    if [[ $rc -eq 124 ]]; then
        return 1
    fi

    # Analyze error to distinguish "not installed" from "installed but error"
    # Pattern: command not found/unknown command = plugin not installed
    if printf '%s' "$version_output" | grep -qiE "not recognized|unknown command|not a docker command|command not found|is not a"; then
        return 1
    fi

    # If we got an error but the command was recognized, plugin exists
    # (could be version mismatch, daemon issue, etc.)
    # Check if error mentions sandbox at all (suggests plugin exists)
    if printf '%s' "$version_output" | grep -qiE "sandbox"; then
        return 0
    fi

    # Daemon not running - can't determine availability
    if printf '%s' "$version_output" | grep -qiE "daemon.*not running|connection refused|Is the docker daemon running|Cannot connect"; then
        return 1
    fi

    # Default: command not recognized = not available
    return 1
}

# Check if sandbox feature is enabled and usable (not blocked by admin policy)
# Returns: 0=enabled and usable, 1=not enabled/blocked
# Outputs: On failure, prints actionable error message to stderr
_cai_sandbox_feature_enabled() {
    # First check if Docker daemon is accessible (with detailed error)
    if ! _cai_docker_daemon_available; then
        case "${_CAI_DAEMON_ERROR:-unknown}" in
            timeout)
                _cai_error "Docker command timed out"
                _cai_error "  Check DOCKER_CONTEXT / daemon reachability"
                ;;
            permission)
                _cai_error "Permission denied accessing Docker"
                _cai_error "  Docker Desktop: Ensure Docker Desktop is running and restart it"
                _cai_error "  Linux: Add user to docker group: sudo usermod -aG docker \$USER"
                ;;
            not_running)
                _cai_error "Docker daemon is not running"
                _cai_error "  Start Docker Desktop and try again"
                ;;
            context)
                _cai_error "Docker context or connection issue"
                _cai_error "  Check DOCKER_CONTEXT / DOCKER_HOST settings"
                ;;
            *)
                _cai_error "Docker daemon is not accessible"
                _cai_error "  Start Docker Desktop and try again"
                ;;
        esac
        return 1
    fi

    # Check Docker Desktop version requirement (4.50+)
    # Sandboxes are a Docker Desktop feature - require Docker Desktop
    local dd_version
    if ! dd_version=$(_cai_docker_desktop_version); then
        _cai_error "Docker Sandboxes require Docker Desktop 4.50+"
        _cai_error "  Current Docker is not Docker Desktop (colima, docker-ce, etc.)"
        _cai_error "  Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
        return 1
    fi

    # Parse major.minor for comparison
    local major minor
    major="${dd_version%%.*}"
    local rest="${dd_version#*.}"
    minor="${rest%%.*}"

    # Version 4.50+ required
    if [[ "$major" -lt 4 ]] || { [[ "$major" -eq 4 ]] && [[ "$minor" -lt 50 ]]; }; then
        _cai_error "Docker Desktop 4.50+ required (found: $dd_version)"
        _cai_error "  Update Docker Desktop: https://www.docker.com/products/docker-desktop/"
        return 1
    fi

    # Check if sandbox plugin is installed
    if ! _cai_sandbox_available; then
        _cai_error "docker sandbox command not found - enable experimental features"
        _cai_error "  Enable beta features in Docker Desktop Settings"
        _cai_error "  See: https://docs.docker.com/ai/sandboxes/troubleshooting/"
        return 1
    fi

    # Try 'docker sandbox ls' to check if feature is actually enabled
    # This catches admin policy blocks and other restrictions
    local ls_output ls_rc
    ls_output=$(_cai_timeout 10 docker sandbox ls 2>&1) && ls_rc=0 || ls_rc=$?

    # Success = feature enabled
    if [[ $ls_rc -eq 0 ]]; then
        return 0
    fi

    # Timeout
    if [[ $ls_rc -eq 124 ]]; then
        _cai_error "Docker sandbox command timed out"
        _cai_error "  Check Docker Desktop is responsive"
        return 1
    fi

    # Analyze error message for specific failure modes

    # Admin policy blocks beta features
    if printf '%s' "$ls_output" | grep -qiE "beta.*disabled|disabled.*admin|administrator.*policy|settings.*management|locked.*admin|admin.*locked"; then
        _cai_error "Sandboxes disabled by administrator policy"
        _cai_error "  Ask your administrator to allow beta features"
        _cai_error "  See: https://docs.docker.com/desktop/settings-and-maintenance/settings/"
        return 1
    fi

    # Feature not enabled in settings
    if printf '%s' "$ls_output" | grep -qiE "feature.*disabled|not enabled|enable.*beta|beta.*feature|experimental.*disabled"; then
        _cai_error "Docker Sandboxes feature is not enabled"
        _cai_error "  Enable beta features in Docker Desktop Settings"
        _cai_error "  See: https://docs.docker.com/ai/sandboxes/troubleshooting/"
        return 1
    fi

    # Requirements not met (general)
    if printf '%s' "$ls_output" | grep -qiE "requirements.*not met|sandbox.*unavailable"; then
        _cai_error "Docker Sandboxes requirements not met"
        _cai_error "  Check Docker Desktop Settings for requirements"
        _cai_error "  See: https://docs.docker.com/ai/sandboxes/troubleshooting/"
        return 1
    fi

    # Empty list messages still indicate success
    if printf '%s' "$ls_output" | grep -qiE "no sandboxes|0 sandboxes|empty"; then
        return 0
    fi

    # Unknown error - report it with proper formatting
    _cai_error "Docker Sandboxes check failed"
    _cai_error "  docker sandbox ls output:"
    printf '%s\n' "$ls_output" | while IFS= read -r line; do
        _cai_error "    $line"
    done
    _cai_error "  See: https://docs.docker.com/ai/sandboxes/troubleshooting/"
    return 1
}

# Get docker sandbox version if available
# Outputs: Version string (e.g., "0.1.0")
# Returns: 0=success, 1=sandbox unavailable
_cai_sandbox_version() {
    if ! _cai_sandbox_available; then
        return 1
    fi

    local version_output rc
    version_output=$(_cai_timeout 5 docker sandbox version 2>/dev/null) && rc=0 || rc=$?

    if [[ $rc -ne 0 ]]; then
        return 1
    fi

    # Parse version output - typically "docker sandbox version X.Y.Z"
    # or just "X.Y.Z" depending on plugin version
    local version
    # Try to extract version after "version " if present
    if [[ "$version_output" == *"version "* ]]; then
        version="${version_output##*version }"
        version="${version%% *}"
    else
        # Maybe just the version number directly
        version="${version_output%% *}"
    fi

    # Clean up any trailing newlines/spaces
    version="${version%%[[:space:]]}"

    if [[ -z "$version" ]]; then
        # Fallback: output raw (trimmed)
        printf '%s' "${version_output%%[[:space:]]}"
    else
        printf '%s' "$version"
    fi

    return 0
}

return 0
