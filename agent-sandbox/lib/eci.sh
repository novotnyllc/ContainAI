#!/usr/bin/env bash
# ==============================================================================
# ContainAI ECI (Enhanced Container Isolation) Detection
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_eci_available()     - Check if ECI might be available (Docker Desktop 4.29+)
#   _cai_eci_enabled()       - Check if ECI is actually enabled (uid_map + runtime check)
#   _cai_eci_status()        - Get ECI status: "enabled", "maybe_available", "not_available"
#
# Detection methods per Docker documentation:
#   1. uid_map check: docker run --rm alpine:3.20 cat /proc/self/uid_map
#      - ECI active: "0 100000 65536" (root mapped to unprivileged)
#      - ECI inactive: "0 0 4294967295" (root is root)
#   2. runtime check: docker inspect --format '{{.HostConfig.Runtime}}' <cid>
#      - ECI active: "sysbox-runc"
#      - ECI inactive: "runc" or empty
#
# Dependencies:
#   - Requires lib/core.sh to be sourced first for logging functions
#   - Requires lib/docker.sh to be sourced first for Docker availability checks
#
# Usage: source lib/eci.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/eci.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/eci.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/eci.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_ECI_LOADED:-}" ]]; then
    return 0
fi
_CAI_ECI_LOADED=1

# Pin alpine version for reproducible uid_map output parsing
_CAI_ECI_ALPINE_IMAGE="alpine:3.20"

# ==============================================================================
# ECI availability check
# ==============================================================================

# Check if ECI might be available (Docker Desktop 4.29+ with Business subscription)
# This checks prerequisites but cannot definitively detect subscription tier or admin settings.
# Returns: 0=potentially available (Docker Desktop 4.29+), 1=not available
# Note: Even if this returns 0, ECI may not be enabled due to subscription/admin - use _cai_eci_enabled() to verify
_cai_eci_available() {
    # ECI requires Docker Desktop
    local dd_version dd_rc
    _cai_docker_desktop_version >/dev/null 2>&1 && dd_rc=0 || dd_rc=$?
    if [[ $dd_rc -ne 0 ]]; then
        # Not Docker Desktop - ECI not available
        return 1
    fi

    # Capture version
    dd_version=$(_cai_docker_desktop_version)

    # Parse major.minor for comparison
    local major minor
    major="${dd_version%%.*}"
    local rest="${dd_version#*.}"
    minor="${rest%%.*}"

    # ECI requires Docker Desktop 4.29+ (when ECI was introduced)
    # https://docs.docker.com/enterprise/security/hardened-desktop/enhanced-container-isolation/
    if [[ "$major" -lt 4 ]] || { [[ "$major" -eq 4 ]] && [[ "$minor" -lt 29 ]]; }; then
        return 1
    fi

    # Docker Desktop version is sufficient for ECI to potentially be available
    # Actual subscription tier (Business) and admin settings cannot be detected programmatically
    return 0
}

# ==============================================================================
# ECI uid_map check (Method 1)
# ==============================================================================

# Check ECI status via uid_map in ephemeral container
# Returns: 0=ECI active, 1=ECI not active or error
# Outputs: Sets _CAI_ECI_UID_MAP_ERROR on failure with reason
_cai_eci_check_uid_map() {
    _CAI_ECI_UID_MAP_ERROR=""

    if ! _cai_docker_daemon_available; then
        _CAI_ECI_UID_MAP_ERROR="daemon_unavailable"
        return 1
    fi

    # Run ephemeral container to check uid_map
    # ECI maps root (uid 0) to unprivileged user (typically 100000+)
    # Without ECI: "0 0 4294967295" (root is root)
    # With ECI: "0 100000 65536" (root mapped to 100000)
    # Note: Capture stdout only to avoid mixing with pull progress/warnings
    local uid_map_output rc tmpfile
    tmpfile=$(mktemp)
    uid_map_output=$(_cai_timeout 30 docker run --rm "$_CAI_ECI_ALPINE_IMAGE" cat /proc/self/uid_map 2>"$tmpfile") && rc=0 || rc=$?
    rm -f "$tmpfile"

    # Timeout
    if [[ $rc -eq 124 ]]; then
        _CAI_ECI_UID_MAP_ERROR="timeout"
        return 1
    fi

    # Command failed
    if [[ $rc -ne 0 ]]; then
        _CAI_ECI_UID_MAP_ERROR="container_failed"
        return 1
    fi

    # Parse uid_map output
    # Format: "inside_uid outside_uid count"
    # ECI active: first field is 0, second field is high (100000+)
    # ECI inactive: first field is 0, second field is 0
    # Filter for lines matching the expected uid_map format to handle any extra output
    local inside_uid outside_uid _count line
    line=$(printf '%s' "$uid_map_output" | grep -E '^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+' | head -1)
    if [[ -z "$line" ]]; then
        _CAI_ECI_UID_MAP_ERROR="parse_failed"
        return 1
    fi
    # _count captures the third field but is unused (only need inside_uid and outside_uid)
    if ! read -r inside_uid outside_uid _count <<< "$line"; then
        _CAI_ECI_UID_MAP_ERROR="parse_failed"
        return 1
    fi

    # Validate we got numeric values
    if [[ ! "$inside_uid" =~ ^[0-9]+$ ]] || [[ ! "$outside_uid" =~ ^[0-9]+$ ]]; then
        _CAI_ECI_UID_MAP_ERROR="parse_failed"
        return 1
    fi

    # ECI detection: root (0) mapped to high uid (100000+)
    # Docker's ECI uses userns starting at 100000
    if [[ "$inside_uid" == "0" ]] && [[ "$outside_uid" -ge 100000 ]]; then
        return 0
    fi

    # No user namespace remapping active
    _CAI_ECI_UID_MAP_ERROR="not_remapped"
    return 1
}

# ==============================================================================
# ECI runtime check (Method 2)
# ==============================================================================

# Check ECI status via runtime inspection
# Returns: 0=ECI active (sysbox-runc), 1=ECI not active or error
# Outputs: Sets _CAI_ECI_RUNTIME_ERROR on failure with reason
_cai_eci_check_runtime() {
    _CAI_ECI_RUNTIME_ERROR=""

    if ! _cai_docker_daemon_available; then
        _CAI_ECI_RUNTIME_ERROR="daemon_unavailable"
        return 1
    fi

    # Use deterministic container name for cleanup on all exit paths
    local container_name
    container_name="cai-eci-check-$$-$(date +%s)"

    # Cleanup function - always try to remove by name
    _cai_eci_cleanup_runtime_container() {
        _cai_timeout 10 docker rm -f "$container_name" >/dev/null 2>&1 || true
    }

    # Start ephemeral container (detached, short-lived) with known name
    # Capture stdout only for CID, stderr to temp file
    local cid rc tmpfile
    tmpfile=$(mktemp)
    cid=$(_cai_timeout 30 docker run -d --name "$container_name" --rm "$_CAI_ECI_ALPINE_IMAGE" sleep 10 2>"$tmpfile") && rc=0 || rc=$?
    rm -f "$tmpfile"

    # Timeout starting container - cleanup by name
    if [[ $rc -eq 124 ]]; then
        _cai_eci_cleanup_runtime_container
        _CAI_ECI_RUNTIME_ERROR="timeout_start"
        return 1
    fi

    # Failed to start container - cleanup by name in case partial creation
    if [[ $rc -ne 0 ]]; then
        _cai_eci_cleanup_runtime_container
        _CAI_ECI_RUNTIME_ERROR="container_failed"
        return 1
    fi

    # Extract CID from output (take last line matching hex pattern in case of extra output)
    cid=$(printf '%s' "$cid" | grep -E '^[a-f0-9]{12,64}$' | tail -1)

    # Validate we got a container ID
    if [[ -z "$cid" ]] || [[ ! "$cid" =~ ^[a-f0-9]+$ ]]; then
        _cai_eci_cleanup_runtime_container
        _CAI_ECI_RUNTIME_ERROR="invalid_cid"
        return 1
    fi

    # Inspect runtime (capture stdout only)
    local runtime
    tmpfile=$(mktemp)
    runtime=$(_cai_timeout 10 docker inspect --format '{{.HostConfig.Runtime}}' "$cid" 2>"$tmpfile") && rc=0 || rc=$?
    rm -f "$tmpfile"

    # Always cleanup container by name
    _cai_eci_cleanup_runtime_container

    # Timeout inspecting
    if [[ $rc -eq 124 ]]; then
        _CAI_ECI_RUNTIME_ERROR="timeout_inspect"
        return 1
    fi

    # Inspect failed
    if [[ $rc -ne 0 ]]; then
        _CAI_ECI_RUNTIME_ERROR="inspect_failed"
        return 1
    fi

    # Check runtime value
    # ECI uses sysbox-runc
    # Non-ECI uses "runc" or empty string (default runtime)
    if [[ "$runtime" == "sysbox-runc" ]]; then
        return 0
    fi

    _CAI_ECI_RUNTIME_ERROR="not_sysbox"
    return 1
}

# ==============================================================================
# Combined ECI enabled check
# ==============================================================================

# Check if ECI is enabled using both uid_map and runtime checks
# Both methods must agree for "enabled" status (high confidence)
# Returns: 0=ECI enabled, 1=ECI not enabled
# Outputs: Sets _CAI_ECI_ENABLED_ERROR with detailed reason on failure
_cai_eci_enabled() {
    _CAI_ECI_ENABLED_ERROR=""

    local uid_map_rc runtime_rc

    # Run uid_map check
    _cai_eci_check_uid_map && uid_map_rc=0 || uid_map_rc=$?

    # Run runtime check
    _cai_eci_check_runtime && runtime_rc=0 || runtime_rc=$?

    # Both must pass for ECI to be considered enabled
    if [[ $uid_map_rc -eq 0 ]] && [[ $runtime_rc -eq 0 ]]; then
        return 0
    fi

    # Determine most useful error message
    if [[ $uid_map_rc -ne 0 ]] && [[ $runtime_rc -ne 0 ]]; then
        # Both failed - report uid_map error (typically more informative)
        _CAI_ECI_ENABLED_ERROR="${_CAI_ECI_UID_MAP_ERROR:-unknown}"
    elif [[ $uid_map_rc -ne 0 ]]; then
        _CAI_ECI_ENABLED_ERROR="uid_map_${_CAI_ECI_UID_MAP_ERROR:-failed}"
    else
        _CAI_ECI_ENABLED_ERROR="runtime_${_CAI_ECI_RUNTIME_ERROR:-failed}"
    fi

    return 1
}

# ==============================================================================
# ECI status summary
# ==============================================================================

# Get comprehensive ECI status
# Outputs: One of: "enabled", "maybe_available", "not_available"
# Returns: Always 0 (status is in output)
# Note: "maybe_available" means Docker Desktop 4.29+ but subscription/admin status unknown
_cai_eci_status() {
    # Check if ECI is actually enabled
    if _cai_eci_enabled; then
        printf '%s' "enabled"
        return 0
    fi

    # Check if ECI could be available (Docker Desktop 4.29+)
    # This only checks version - subscription tier and admin settings cannot be detected
    if _cai_eci_available; then
        printf '%s' "maybe_available"
        return 0
    fi

    printf '%s' "not_available"
    return 0
}

# ==============================================================================
# ECI status message helpers
# ==============================================================================

# Print human-readable ECI status message
# Arguments: none (uses _cai_eci_status internally)
# Outputs: Status message to stdout
_cai_eci_status_message() {
    local status
    status=$(_cai_eci_status)

    case "$status" in
        enabled)
            printf '%s\n' "ECI enabled"
            ;;
        maybe_available)
            printf '%s\n' "ECI may be available but is not enabled"
            printf '%s\n' "  Docker Desktop version supports ECI, but:"
            printf '%s\n' "  - ECI requires Docker Business subscription"
            printf '%s\n' "  - ECI must be enabled by admin in Docker Desktop Settings"
            printf '%s\n' "  Enable: Settings > Security > Enhanced Container Isolation"
            ;;
        not_available)
            printf '%s\n' "ECI not available"
            # Branch on specific error conditions for accurate messaging
            # First check daemon errors from the last availability check
            case "${_CAI_DD_VERSION_ERROR:-}" in
                timeout)
                    printf '%s\n' "  Docker command timed out"
                    printf '%s\n' "  Check Docker Desktop is responsive"
                    ;;
                permission)
                    printf '%s\n' "  Permission denied accessing Docker"
                    printf '%s\n' "  Ensure Docker Desktop is running and accessible"
                    ;;
                not_running)
                    printf '%s\n' "  Docker Desktop is not running"
                    printf '%s\n' "  Start Docker Desktop and try again"
                    ;;
                not_docker_desktop)
                    printf '%s\n' "  ECI requires Docker Desktop 4.29+"
                    printf '%s\n' "  Current Docker is not Docker Desktop (colima, docker-ce, etc.)"
                    ;;
                *)
                    # Check if we can get version info
                    if _cai_docker_desktop_version >/dev/null 2>&1; then
                        local dd_version
                        dd_version=$(_cai_docker_desktop_version)
                        printf '%s\n' "  ECI requires Docker Desktop 4.29+"
                        printf '%s\n' "  Current version: $dd_version (too old)"
                    elif ! _cai_docker_daemon_available; then
                        # Daemon not available - check daemon error
                        case "${_CAI_DAEMON_ERROR:-}" in
                            timeout)
                                printf '%s\n' "  Docker command timed out"
                                ;;
                            permission)
                                printf '%s\n' "  Permission denied accessing Docker"
                                ;;
                            not_running)
                                printf '%s\n' "  Docker is not running"
                                ;;
                            *)
                                printf '%s\n' "  Docker daemon not accessible"
                                ;;
                        esac
                    else
                        printf '%s\n' "  ECI requires Docker Desktop 4.29+"
                        printf '%s\n' "  Current Docker is not Docker Desktop"
                    fi
                    ;;
            esac
            ;;
    esac
}

return 0
