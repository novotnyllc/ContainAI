#!/usr/bin/env bash
# ==============================================================================
# ContainAI ECI (Enhanced Container Isolation) Detection
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_eci_available()     - Check if ECI might be available (Docker Desktop 4.29+)
#   _cai_eci_enabled()       - Check if ECI is actually enabled (uid_map + runtime check)
#   _cai_eci_status()        - Get ECI status: "enabled", "available_not_enabled", "not_available"
#
# Detection methods per Docker documentation:
#   1. uid_map check: docker run --rm --pull=never alpine:3.20 cat /proc/self/uid_map
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
    # ECI requires Docker Desktop - capture version and rc in single call
    local dd_version dd_rc
    dd_version=$(_cai_docker_desktop_version 2>/dev/null) && dd_rc=0 || dd_rc=$?
    if [[ $dd_rc -ne 0 ]]; then
        # Not Docker Desktop - ECI not available
        return 1
    fi

    # Parse major.minor for comparison
    local major minor rest
    major="${dd_version%%.*}"
    rest="${dd_version#*.}"
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
#          Sets _CAI_ECI_UID_MAP_DETAIL with stderr snippet for diagnostics
_cai_eci_check_uid_map() {
    _CAI_ECI_UID_MAP_ERROR=""
    _CAI_ECI_UID_MAP_DETAIL=""

    if ! _cai_docker_daemon_available; then
        _CAI_ECI_UID_MAP_ERROR="daemon_unavailable"
        return 1
    fi

    # Run ephemeral container to check uid_map
    # ECI maps root (uid 0) to unprivileged user (typically 100000+)
    # Without ECI: "0 0 4294967295" (root is root)
    # With ECI: "0 100000 65536" (root mapped to 100000)
    # Use --pull=never to avoid network dependency in airgapped environments
    # Note: Capture stdout only to avoid mixing with pull progress/warnings
    local uid_map_output rc tmpfile stderr_snippet
    tmpfile=$(mktemp)
    # Clear the flag before calling _cai_timeout so we can detect if it was set
    _CAI_TIMEOUT_UNAVAILABLE=0
    uid_map_output=$(_cai_timeout 30 docker run --rm --pull=never "$_CAI_ECI_ALPINE_IMAGE" cat /proc/self/uid_map 2>"$tmpfile") && rc=0 || rc=$?
    stderr_snippet=$(head -c 200 "$tmpfile" 2>/dev/null || true)
    rm -f "$tmpfile"

    # No timeout mechanism available - check flag set by _cai_timeout
    if [[ "${_CAI_TIMEOUT_UNAVAILABLE:-0}" == "1" ]]; then
        _CAI_ECI_UID_MAP_ERROR="no_timeout"
        _CAI_ECI_UID_MAP_DETAIL="Install coreutils (timeout/gtimeout) or perl"
        return 1
    fi

    # Timeout
    if [[ $rc -eq 124 ]]; then
        _CAI_ECI_UID_MAP_ERROR="timeout"
        return 1
    fi

    # Command failed - check for image not found
    if [[ $rc -ne 0 ]]; then
        if printf '%s' "$stderr_snippet" | grep -qiE "no such image|image.*not found|pull access denied|manifest unknown"; then
            _CAI_ECI_UID_MAP_ERROR="image_not_found"
            _CAI_ECI_UID_MAP_DETAIL="Pull $_CAI_ECI_ALPINE_IMAGE: docker pull $_CAI_ECI_ALPINE_IMAGE"
        else
            _CAI_ECI_UID_MAP_ERROR="container_failed"
            _CAI_ECI_UID_MAP_DETAIL="$stderr_snippet"
        fi
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
#          Sets _CAI_ECI_RUNTIME_DETAIL with stderr snippet for diagnostics
_cai_eci_check_runtime() {
    _CAI_ECI_RUNTIME_ERROR=""
    _CAI_ECI_RUNTIME_DETAIL=""

    if ! _cai_docker_daemon_available; then
        _CAI_ECI_RUNTIME_ERROR="daemon_unavailable"
        return 1
    fi

    # Use high-entropy container name to avoid collisions
    # Include PID, timestamp with nanoseconds, and RANDOM for uniqueness
    local container_name cid_for_cleanup
    container_name="cai-eci-check-$$-$(date +%s%N 2>/dev/null || date +%s)-${RANDOM:-0}"
    cid_for_cleanup=""

    # Start ephemeral container (detached, short-lived) with known name
    # Use --pull=never to avoid network dependency in airgapped environments
    # Capture stdout only for CID, stderr to temp file
    local cid rc tmpfile stderr_snippet
    tmpfile=$(mktemp)
    # Clear the flag before calling _cai_timeout so we can detect if it was set
    _CAI_TIMEOUT_UNAVAILABLE=0
    cid=$(_cai_timeout 30 docker run -d --name "$container_name" --rm --pull=never "$_CAI_ECI_ALPINE_IMAGE" sleep 10 2>"$tmpfile") && rc=0 || rc=$?
    stderr_snippet=$(head -c 200 "$tmpfile" 2>/dev/null || true)
    rm -f "$tmpfile"

    # Helper to cleanup by CID (more reliable than name)
    _eci_cleanup() {
        if [[ -n "$cid_for_cleanup" ]]; then
            _cai_timeout 10 docker rm -f "$cid_for_cleanup" >/dev/null 2>&1 || true
        elif [[ -n "$container_name" ]]; then
            _cai_timeout 10 docker rm -f "$container_name" >/dev/null 2>&1 || true
        fi
    }

    # No timeout mechanism available - check flag set by _cai_timeout
    if [[ "${_CAI_TIMEOUT_UNAVAILABLE:-0}" == "1" ]]; then
        _eci_cleanup
        _CAI_ECI_RUNTIME_ERROR="no_timeout"
        _CAI_ECI_RUNTIME_DETAIL="Install coreutils (timeout/gtimeout) or perl"
        return 1
    fi

    # Timeout starting container
    if [[ $rc -eq 124 ]]; then
        _eci_cleanup
        _CAI_ECI_RUNTIME_ERROR="timeout_start"
        return 1
    fi

    # Failed to start container - check for image not found
    if [[ $rc -ne 0 ]]; then
        _eci_cleanup
        if printf '%s' "$stderr_snippet" | grep -qiE "no such image|image.*not found|pull access denied|manifest unknown"; then
            _CAI_ECI_RUNTIME_ERROR="image_not_found"
            _CAI_ECI_RUNTIME_DETAIL="Pull $_CAI_ECI_ALPINE_IMAGE: docker pull $_CAI_ECI_ALPINE_IMAGE"
        else
            _CAI_ECI_RUNTIME_ERROR="container_failed"
            _CAI_ECI_RUNTIME_DETAIL="$stderr_snippet"
        fi
        return 1
    fi

    # Extract CID from output (take last line matching hex pattern in case of extra output)
    cid=$(printf '%s' "$cid" | grep -E '^[a-f0-9]{12,64}$' | tail -1)

    # Validate we got a container ID and save it for cleanup
    if [[ -z "$cid" ]] || [[ ! "$cid" =~ ^[a-f0-9]+$ ]]; then
        _eci_cleanup
        _CAI_ECI_RUNTIME_ERROR="invalid_cid"
        return 1
    fi
    cid_for_cleanup="$cid"

    # Inspect runtime (capture stdout only)
    local runtime
    tmpfile=$(mktemp)
    _CAI_TIMEOUT_UNAVAILABLE=0
    runtime=$(_cai_timeout 10 docker inspect --format '{{.HostConfig.Runtime}}' "$cid" 2>"$tmpfile") && rc=0 || rc=$?
    stderr_snippet=$(head -c 200 "$tmpfile" 2>/dev/null || true)
    rm -f "$tmpfile"

    # Always cleanup container
    _eci_cleanup

    # Timeout inspecting
    if [[ $rc -eq 124 ]]; then
        _CAI_ECI_RUNTIME_ERROR="timeout_inspect"
        return 1
    fi

    # Inspect failed
    if [[ $rc -ne 0 ]]; then
        _CAI_ECI_RUNTIME_ERROR="inspect_failed"
        _CAI_ECI_RUNTIME_DETAIL="$stderr_snippet"
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
#          Sets _CAI_ECI_DETECTION_UNCERTAIN=1 if failure was operational (not definitive)
_cai_eci_enabled() {
    _CAI_ECI_ENABLED_ERROR=""
    _CAI_ECI_DETECTION_UNCERTAIN=0

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

    # Mark detection as uncertain if failure was operational (not definitive "not enabled")
    # These errors mean we couldn't determine status, not that ECI is definitely off
    case "${_CAI_ECI_UID_MAP_ERROR:-}" in
        timeout|no_timeout|daemon_unavailable|container_failed|image_not_found|inspect_failed)
            _CAI_ECI_DETECTION_UNCERTAIN=1
            ;;
    esac
    case "${_CAI_ECI_RUNTIME_ERROR:-}" in
        timeout_start|timeout_inspect|no_timeout|daemon_unavailable|container_failed|image_not_found|inspect_failed|invalid_cid)
            _CAI_ECI_DETECTION_UNCERTAIN=1
            ;;
    esac

    return 1
}

# ==============================================================================
# ECI status summary
# ==============================================================================

# Get comprehensive ECI status
# Outputs: One of: "enabled", "available_not_enabled", "detection_failed", "not_available"
# Returns: Always 0 (status is in output)
# Note: "available_not_enabled" means Docker Desktop 4.29+ and ECI definitively not enabled
#       "detection_failed" means Docker Desktop 4.29+ but detection had operational failure
_cai_eci_status() {
    # Check if ECI is actually enabled
    if _cai_eci_enabled; then
        printf '%s' "enabled"
        return 0
    fi

    # Check if ECI could be available (Docker Desktop 4.29+)
    # This only checks version - subscription tier and admin settings cannot be detected
    if _cai_eci_available; then
        # If detection was uncertain, report that instead of claiming "not enabled"
        if [[ "${_CAI_ECI_DETECTION_UNCERTAIN:-0}" == "1" ]]; then
            printf '%s' "detection_failed"
        else
            printf '%s' "available_not_enabled"
        fi
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
        available_not_enabled)
            printf '%s\n' "ECI available but not enabled"
            printf '%s\n' "  Docker Desktop version supports ECI, but:"
            printf '%s\n' "  - ECI requires Docker Business subscription"
            printf '%s\n' "  - ECI must be enabled by admin in Docker Desktop Settings"
            printf '%s\n' "  Enable: Settings > Security > Enhanced Container Isolation"
            ;;
        detection_failed)
            printf '%s\n' "ECI detection failed"
            printf '%s\n' "  Docker Desktop version supports ECI, but detection could not complete"
            case "${_CAI_ECI_ENABLED_ERROR:-}" in
                image_not_found|uid_map_image_not_found|runtime_image_not_found)
                    printf '%s\n' "  Missing image: $_CAI_ECI_ALPINE_IMAGE"
                    printf '%s\n' "  Run: docker pull $_CAI_ECI_ALPINE_IMAGE"
                    ;;
                no_timeout|uid_map_no_timeout|runtime_no_timeout)
                    printf '%s\n' "  No timeout command available"
                    printf '%s\n' "  Install coreutils: brew install coreutils (macOS) or apt install coreutils (Linux)"
                    ;;
                timeout*|uid_map_timeout*|runtime_timeout*)
                    printf '%s\n' "  Docker command timed out"
                    printf '%s\n' "  Check Docker Desktop is responsive"
                    ;;
                daemon_unavailable|uid_map_daemon_unavailable|runtime_daemon_unavailable)
                    printf '%s\n' "  Docker daemon not accessible"
                    printf '%s\n' "  Ensure Docker Desktop is running"
                    ;;
                *)
                    printf '%s\n' "  Error: ${_CAI_ECI_ENABLED_ERROR:-unknown}"
                    if [[ -n "${_CAI_ECI_UID_MAP_DETAIL:-}" ]]; then
                        printf '%s\n' "  Detail: ${_CAI_ECI_UID_MAP_DETAIL}"
                    fi
                    ;;
            esac
            ;;
        not_available)
            printf '%s\n' "ECI not available"
            # Branch on specific error conditions for accurate messaging
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
                    # Check for no_timeout error
                    if [[ "${_CAI_ECI_UID_MAP_ERROR:-}" == "no_timeout" || "${_CAI_ECI_RUNTIME_ERROR:-}" == "no_timeout" ]]; then
                        printf '%s\n' "  No timeout command available (timeout, gtimeout, or perl required)"
                        printf '%s\n' "  Install coreutils: brew install coreutils (macOS) or apt install coreutils (Linux)"
                    # Check if we can get version info
                    elif _cai_docker_desktop_version >/dev/null 2>&1; then
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
                            no_timeout)
                                printf '%s\n' "  No timeout command available"
                                printf '%s\n' "  Install coreutils: brew install coreutils (macOS)"
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
