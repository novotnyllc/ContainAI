#!/usr/bin/env bash
# ==============================================================================
# ContainAI Doctor Command - System Health Check and Diagnostics
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_doctor()              - Run all checks and output formatted report
#   _cai_doctor_json()         - Run all checks and output JSON report
#   _cai_check_wsl_seccomp()   - Check WSL2 seccomp compatibility status
#   _cai_select_context()      - Auto-select Docker context based on isolation availability
#
# Requirements Hierarchy:
#   Docker Sandbox: Hard requirement - blocks usage if not available
#   Sysbox:         Strong suggestion - warns but allows usage if not available
#
# Dependencies:
#   - Requires lib/core.sh to be sourced first for logging functions
#   - Requires lib/platform.sh to be sourced first for platform detection
#   - Requires lib/docker.sh to be sourced first for Docker availability checks
#   - Requires lib/eci.sh to be sourced first for ECI detection
#
# Usage: source lib/doctor.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/doctor.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/doctor.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/doctor.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_DOCTOR_LOADED:-}" ]]; then
    return 0
fi
_CAI_DOCTOR_LOADED=1

# ==============================================================================
# WSL2 Seccomp Compatibility Check
# ==============================================================================

# Check WSL2 seccomp compatibility status for Sysbox
# Outputs: "ok", "filter_warning", "unavailable", or "unknown"
# Sets: _CAI_SECCOMP_MODE with numeric mode (0=disabled, 1=strict, 2=filter)
# Note: WSL2's filter mode (Seccomp: 2) can conflict with Sysbox's seccomp policies
_cai_check_wsl_seccomp() {
    _CAI_SECCOMP_MODE=""

    # Check /proc/self/status for Seccomp field (current process's seccomp mode)
    if [[ -f /proc/self/status ]]; then
        local seccomp_line
        # Guard grep with || true per pitfall memory
        seccomp_line=$(grep "^Seccomp:" /proc/self/status 2>/dev/null || true)
        if [[ -n "$seccomp_line" ]]; then
            # Extract mode number
            _CAI_SECCOMP_MODE="${seccomp_line##*:}"
            _CAI_SECCOMP_MODE="${_CAI_SECCOMP_MODE// /}"

            case "$_CAI_SECCOMP_MODE" in
                0)
                    # Mode 0 means seccomp is not active for this process
                    # but the kernel may still support it - report as ok
                    printf '%s' "ok"
                    return 0
                    ;;
                1)
                    # Strict mode - Sysbox works
                    printf '%s' "ok"
                    return 0
                    ;;
                2)
                    # Filter mode - may conflict with Sysbox
                    printf '%s' "filter_warning"
                    return 0
                    ;;
            esac
        fi
    fi

    # No seccomp status found - cannot determine
    printf '%s' "unknown"
    return 0
}

# ==============================================================================
# Context Auto-Selection
# ==============================================================================

# Auto-select Docker context based on isolation availability
# Returns context name via stdout:
#   - "" (empty) for default context (Docker Desktop with ECI)
#   - "containai-secure" for Sysbox context (or config override)
#   - Nothing (return 1) if no isolation available
# Arguments: $1 = config override for context name (optional)
#            $2 = debug flag ("debug" to enable debug output)
# Returns: 0=context selected, 1=no isolation available
# Outputs: Debug messages to stderr if debug flag is set
_cai_select_context() {
    local config_context_name="${1:-}"
    local debug_flag="${2:-}"
    local eci_status

    # Check ECI status first (ensure we use default context for this check)
    # Unset DOCKER_CONTEXT to ensure we check Docker Desktop, not a custom context
    eci_status=$(DOCKER_CONTEXT= DOCKER_HOST= _cai_eci_status)

    # ECI path requires BOTH ECI enabled AND sandbox feature available
    if [[ "$eci_status" == "enabled" ]]; then
        # Also verify sandbox feature is enabled (docker sandbox command works)
        if _cai_sandbox_feature_enabled 2>/dev/null; then
            # ECI enabled with sandboxes - use default context (Docker Desktop)
            if [[ "$debug_flag" == "debug" ]]; then
                printf '%s\n' "[DEBUG] Context selection: ECI enabled + sandboxes available, using default context" >&2
            fi
            printf '%s' ""
            return 0
        else
            if [[ "$debug_flag" == "debug" ]]; then
                printf '%s\n' "[DEBUG] Context selection: ECI enabled but sandboxes not available, checking Sysbox" >&2
            fi
        fi
    fi

    # ECI path not usable - check for Secure Engine context
    # Use config override if provided, otherwise default to containai-secure
    local context_name="${config_context_name:-containai-secure}"
    local default_context="containai-secure"

    # Verify context exists AND has sysbox-runc runtime (not just context inspect)
    # This catches cases where context exists but daemon is down or sysbox not installed
    if _cai_sysbox_available_for_context "$context_name"; then
        if [[ "$debug_flag" == "debug" ]]; then
            printf '%s\n' "[DEBUG] Context selection: Using context '$context_name' with Sysbox" >&2
        fi
        printf '%s' "$context_name"
        return 0
    fi

    # Config-specified context failed - try default containai-secure as fallback
    # (unless config already specified containai-secure, which we just tried)
    if [[ -n "$config_context_name" ]] && [[ "$config_context_name" != "$default_context" ]]; then
        if [[ "$debug_flag" == "debug" ]]; then
            printf '%s\n' "[DEBUG] Context selection: Config context '$config_context_name' not available, trying default '$default_context'" >&2
        fi
        if _cai_sysbox_available_for_context "$default_context"; then
            if [[ "$debug_flag" == "debug" ]]; then
                printf '%s\n' "[DEBUG] Context selection: Using fallback context '$default_context' with Sysbox" >&2
            fi
            echo "[WARN] Config context '$config_context_name' not available, using default '$default_context'" >&2
            printf '%s' "$default_context"
            return 0
        fi
    fi

    # No isolation available
    if [[ "$debug_flag" == "debug" ]]; then
        printf '%s\n' "[DEBUG] Context selection: No isolation available (ECI status=$eci_status, context '$context_name' not ready)" >&2
    fi
    return 1
}

# Check if Sysbox is available for a specific context
# Arguments: $1 = context name
# Returns: 0=available, 1=not available
# Outputs: Sets _CAI_SYSBOX_CONTEXT_ERROR with reason on failure
_cai_sysbox_available_for_context() {
    local context_name="${1:-containai-secure}"
    _CAI_SYSBOX_CONTEXT_ERROR=""

    # Check if context exists
    if ! docker context inspect "$context_name" >/dev/null 2>&1; then
        _CAI_SYSBOX_CONTEXT_ERROR="context_not_found"
        return 1
    fi

    # Check if we can connect to the daemon on this context
    local info_output rc
    info_output=$(_cai_timeout 10 docker --context "$context_name" info 2>&1) && rc=0 || rc=$?

    if [[ $rc -eq 124 ]]; then
        _CAI_SYSBOX_CONTEXT_ERROR="timeout"
        return 1
    fi

    if [[ $rc -ne 0 ]]; then
        _CAI_SYSBOX_CONTEXT_ERROR="daemon_unavailable"
        return 1
    fi

    # Check for sysbox-runc runtime
    if ! printf '%s' "$info_output" | grep -q "sysbox-runc"; then
        _CAI_SYSBOX_CONTEXT_ERROR="runtime_not_found"
        return 1
    fi

    return 0
}

# ==============================================================================
# Sysbox Detection
# ==============================================================================

# Check if Sysbox is available on the containai-secure context
# Returns: 0=available, 1=not available
# Outputs: Sets _CAI_SYSBOX_ERROR with reason on failure
#          Sets _CAI_SYSBOX_CONTEXT_EXISTS with true/false
_cai_sysbox_available() {
    _CAI_SYSBOX_ERROR=""
    _CAI_SYSBOX_CONTEXT_EXISTS="false"

    local socket="/var/run/containai-docker.sock"

    # Check if socket exists
    if [[ ! -S "$socket" ]]; then
        _CAI_SYSBOX_ERROR="socket_not_found"
        return 1
    fi

    # Check if context exists
    if docker context inspect containai-secure >/dev/null 2>&1; then
        _CAI_SYSBOX_CONTEXT_EXISTS="true"
    else
        _CAI_SYSBOX_ERROR="context_not_found"
        return 1
    fi

    # Check if we can connect to the daemon
    local info_output rc
    info_output=$(_cai_timeout 10 docker --context containai-secure info 2>&1) && rc=0 || rc=$?

    if [[ $rc -eq 124 ]]; then
        _CAI_SYSBOX_ERROR="timeout"
        return 1
    fi

    if [[ $rc -ne 0 ]]; then
        _CAI_SYSBOX_ERROR="daemon_unavailable"
        return 1
    fi

    # Check for sysbox-runc runtime
    if ! printf '%s' "$info_output" | grep -q "sysbox-runc"; then
        _CAI_SYSBOX_ERROR="runtime_not_found"
        return 1
    fi

    return 0
}

# ==============================================================================
# Doctor Text Output
# ==============================================================================

# Print right-aligned status marker at column 60
# Arguments: $1 = status text (e.g., "[OK]", "[WARN]", "[ERROR]")
#            $2 = optional note (e.g., "REQUIRED", "STRONGLY RECOMMENDED")
_cai_doctor_status() {
    local status="$1"
    local note="${2:-}"

    if [[ -n "$note" ]]; then
        printf '%s    <- %s\n' "$status" "$note"
    else
        printf '%s\n' "$status"
    fi
}

# Run doctor command with text output
# Returns: 0 if any isolation available (Sandbox OR Sysbox)
#          1 if no isolation available (cannot proceed)
_cai_doctor() {
    local sandbox_ok="false"
    local eci_enabled="false"
    local sysbox_ok="false"
    local dd_version=""
    local dd_available="false"
    local docker_cli_ok="false"
    local docker_daemon_ok="false"
    local platform
    local seccomp_status=""

    platform=$(_cai_detect_platform)

    printf '%s\n' "ContainAI Doctor"
    printf '%s\n' "================"
    printf '\n'

    # === Docker CLI/Daemon Section ===
    printf '%s\n' "Docker"

    # Check Docker CLI
    if _cai_docker_cli_available; then
        docker_cli_ok="true"
        printf '  %-44s %s\n' "Docker CLI:" "[OK]"
    else
        printf '  %-44s %s\n' "Docker CLI:" "[ERROR] Not installed"
    fi

    # Check Docker daemon (only if CLI available)
    if [[ "$docker_cli_ok" == "true" ]]; then
        if _cai_docker_daemon_available; then
            docker_daemon_ok="true"
            printf '  %-44s %s\n' "Docker daemon:" "[OK]"
        else
            printf '  %-44s %s\n' "Docker daemon:" "[ERROR] Not accessible"
            case "${_CAI_DAEMON_ERROR:-unknown}" in
                not_running)
                    printf '  %-44s %s\n' "" "(Start Docker Desktop or dockerd)"
                    ;;
                permission)
                    printf '  %-44s %s\n' "" "(Check permissions or Docker service)"
                    ;;
                timeout)
                    printf '  %-44s %s\n' "" "(Docker command timed out)"
                    ;;
            esac
        fi
    fi

    printf '\n'

    # === Docker Desktop / ECI Section ===
    printf '%s\n' "Docker Desktop (ECI Path)"

    if [[ "$docker_daemon_ok" != "true" ]]; then
        printf '  %-44s %s\n' "Status:" "[SKIP] Docker daemon not available"
    elif _cai_docker_desktop_version >/dev/null 2>&1; then
        dd_version=$(_cai_docker_desktop_version)
        dd_available="true"
        printf '  %-44s %s\n' "Version: $dd_version" "[OK]"

        # Check if Docker Desktop version is sufficient (4.50+)
        local dd_major dd_minor dd_rest
        dd_major="${dd_version%%.*}"
        dd_rest="${dd_version#*.}"
        dd_minor="${dd_rest%%.*}"

        if [[ "$dd_major" -lt 4 ]] || { [[ "$dd_major" -eq 4 ]] && [[ "$dd_minor" -lt 50 ]]; }; then
            printf '  %-44s %s\n' "Sandboxes feature:" "[ERROR] Version $dd_version < 4.50"
            printf '  %-44s %s\n' "" "(Upgrade Docker Desktop to 4.50+)"
        elif _cai_sandbox_feature_enabled 2>/dev/null; then
            sandbox_ok="true"
            printf '  %-44s %s\n' "Sandboxes feature:" "[OK] Enabled"

            # Check if ECI is actually enabled (required for cai run to use this path)
            local eci_status
            eci_status=$(_cai_eci_status)
            if [[ "$eci_status" == "enabled" ]]; then
                eci_enabled="true"
                printf '  %-44s %s\n' "ECI (Enhanced Container Isolation):" "[OK] Enabled"
            elif [[ "$eci_status" == "available_not_enabled" ]]; then
                printf '  %-44s %s\n' "ECI (Enhanced Container Isolation):" "[WARN] Available but not enabled"
                printf '  %-44s %s\n' "" "(Enable in Settings > Security for this path to work)"
            else
                printf '  %-44s %s\n' "ECI (Enhanced Container Isolation):" "[WARN] Status unknown"
            fi
        else
            printf '  %-44s %s\n' "Sandboxes feature:" "[ERROR] Not enabled"
            printf '  %-44s %s\n' "" "(Enable in Docker Desktop Settings > Features in development)"
        fi
    else
        # Not Docker Desktop
        case "${_CAI_DD_VERSION_ERROR:-}" in
            not_docker_desktop)
                printf '  %-44s %s\n' "Status:" "[INFO] Not Docker Desktop (using Docker Engine)"
                printf '  %-44s %s\n' "" "(ECI path requires Docker Desktop 4.50+)"
                ;;
            *)
                printf '  %-44s %s\n' "Status:" "[WARN] Could not detect Docker Desktop"
                ;;
        esac
    fi

    printf '\n'

    # === Sysbox / Secure Engine Section ===
    printf '%s\n' "Secure Engine (Sysbox Path)"

    # Resolve configured context name (env/config), default to containai-secure
    local sysbox_context_name="containai-secure"
    local config_context
    config_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || config_context=""
    if [[ -n "$config_context" ]]; then
        sysbox_context_name="$config_context"
    fi

    # Check Sysbox availability with resolved context name
    if _cai_sysbox_available_for_context "$sysbox_context_name"; then
        sysbox_ok="true"
        printf '  %-44s %s\n' "Sysbox available:" "[OK]"
        printf '  %-44s %s\n' "Runtime: sysbox-runc" "[OK]"
        printf '  %-44s %s\n' "Context '$sysbox_context_name':" "[OK] Configured"
    else
        printf '  %-44s %s\n' "Sysbox available:" "[INFO] Not configured"
        case "${_CAI_SYSBOX_CONTEXT_ERROR:-${_CAI_SYSBOX_ERROR:-}}" in
            socket_not_found)
                printf '  %-44s %s\n' "" "(Run 'cai setup' to install Sysbox)"
                ;;
            context_not_found)
                printf '  %-44s %s\n' "" "(Run 'cai setup' to configure '$sysbox_context_name' context)"
                ;;
            daemon_unavailable)
                printf '  %-44s %s\n' "" "(Docker daemon for '$sysbox_context_name' not running)"
                ;;
            runtime_not_found)
                printf '  %-44s %s\n' "" "(Sysbox runtime not found - run 'cai setup')"
                ;;
            timeout)
                printf '  %-44s %s\n' "" "(Docker daemon for '$sysbox_context_name' timed out)"
                ;;
            *)
                printf '  %-44s %s\n' "" "(Run 'cai setup' for Sysbox isolation)"
                ;;
        esac
    fi

    printf '\n'

    # === Platform-specific Section ===
    if [[ "$platform" == "wsl" ]]; then
        printf '%s\n' "Platform: WSL2"

        seccomp_status=$(_cai_check_wsl_seccomp)
        case "$seccomp_status" in
            ok)
                printf '  %-44s %s\n' "Seccomp compatibility: ok" "[OK]"
                ;;
            filter_warning)
                printf '  %-44s %s\n' "Seccomp compatibility: warning" "[WARN]"
                printf '  %-44s %s\n' "" "(WSL 1.1.0+ may have seccomp conflicts with Sysbox)"
                printf '  %-44s %s\n' "" "(use --force with cai setup if needed)"
                ;;
            unavailable)
                printf '  %-44s %s\n' "Seccomp compatibility: not available" "[WARN]"
                printf '  %-44s %s\n' "" "(Sysbox requires seccomp support)"
                ;;
            unknown)
                printf '  %-44s %s\n' "Seccomp compatibility: unknown" "[WARN]"
                ;;
        esac

        printf '\n'
    elif [[ "$platform" == "macos" ]]; then
        printf '%s\n' "Platform: macOS"

        # Check ECI status on macOS
        local eci_status
        eci_status=$(_cai_eci_status)
        case "$eci_status" in
            enabled)
                printf '  %-44s %s\n' "ECI (Enhanced Container Isolation): enabled" "[OK]"
                ;;
            available_not_enabled)
                printf '  %-44s %s\n' "ECI (Enhanced Container Isolation): available" "[WARN]"
                printf '  %-44s %s\n' "" "(Enable in Settings > Security for additional isolation)"
                ;;
            *)
                printf '  %-44s %s\n' "ECI (Enhanced Container Isolation): not available" "[WARN]"
                ;;
        esac

        printf '\n'
    elif [[ "$platform" == "linux" ]]; then
        printf '%s\n' "Platform: Linux"
        printf '\n'
    fi

    # === Summary Section ===
    printf '%s\n' "Summary"

    # Isolation is available if ECI is enabled (for sandbox path) OR Sysbox is available
    # Note: sandbox_ok means sandboxes feature is enabled, but cai run requires ECI enabled
    local isolation_available="false"
    if [[ "$eci_enabled" == "true" ]] || [[ "$sysbox_ok" == "true" ]]; then
        isolation_available="true"
    fi

    # ECI path status (requires both sandboxes AND ECI enabled)
    if [[ "$eci_enabled" == "true" ]]; then
        printf '  %-44s %s\n' "ECI Path:" "[OK] Ready (Docker Desktop + ECI)"
    elif [[ "$sandbox_ok" == "true" ]]; then
        printf '  %-44s %s\n' "ECI Path:" "[WARN] Sandboxes enabled but ECI not enabled"
        printf '  %-44s %s\n' "" "(Enable ECI in Docker Desktop Settings > Security)"
    else
        if [[ "$sysbox_ok" == "true" ]]; then
            printf '  %-44s %s\n' "ECI Path:" "[INFO] Not available (using Sysbox instead)"
        else
            printf '  %-44s %s\n' "ECI Path:" "[ERROR] Not available"
        fi
    fi

    # Sysbox path status
    if [[ "$sysbox_ok" == "true" ]]; then
        printf '  %-44s %s\n' "Sysbox Path:" "[OK] Ready"
    else
        if [[ "$eci_enabled" == "true" ]]; then
            printf '  %-44s %s\n' "Sysbox Path:" "[INFO] Not configured (using ECI instead)"
        else
            printf '  %-44s %s\n' "Sysbox Path:" "[WARN] Not available"
            printf '  %-44s %s\n' "" "(Run 'cai setup' to configure)"
        fi
    fi

    # Overall status
    if [[ "$isolation_available" == "true" ]]; then
        printf '  %-44s %s\n' "Status:" "[OK] Ready to use 'cai run'"
    else
        printf '  %-44s %s\n' "Status:" "[ERROR] No isolation available"
        if [[ "$sandbox_ok" == "true" ]]; then
            printf '  %-44s %s\n' "Recommended:" "Enable ECI in Docker Desktop Settings > Security"
        else
            printf '  %-44s %s\n' "Recommended:" "Install Docker Desktop 4.50+ with ECI, or run 'cai setup'"
        fi
    fi

    # Exit code: 0 if any isolation available, 1 if not
    if [[ "$isolation_available" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# Doctor JSON Output
# ==============================================================================

# Escape string for JSON output
# Arguments: $1 = string to escape
# Outputs: JSON-safe escaped string
_cai_json_escape() {
    local str="$1"
    # Escape backslashes first, then quotes, then control chars
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

# Run doctor command with JSON output
# Returns: 0 if any isolation available (ECI enabled OR Sysbox)
#          1 if no isolation available (cannot proceed)
_cai_doctor_json() {
    local sandboxes_available="false"
    local sandbox_enabled="false"
    local eci_enabled="false"
    local sysbox_ok="false"
    local dd_version=""
    local platform
    local platform_json
    local seccomp_status=""
    local seccomp_compatible="true"
    local seccomp_warning=""
    local eci_status="not_available"
    local sysbox_runtime=""
    local sysbox_context_exists="false"
    local sysbox_context_name="containai-secure"
    local recommended_action="setup_required"

    platform=$(_cai_detect_platform)
    # Normalize platform type for JSON (wsl -> wsl2 per spec)
    if [[ "$platform" == "wsl" ]]; then
        platform_json="wsl2"
    else
        platform_json="$platform"
    fi

    # Try to get configured context name (if available)
    local config_context
    config_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || config_context=""
    if [[ -n "$config_context" ]]; then
        sysbox_context_name="$config_context"
    fi

    # Check Docker availability
    if _cai_docker_cli_available && _cai_docker_daemon_available; then
        if _cai_docker_desktop_version >/dev/null 2>&1; then
            dd_version=$(_cai_docker_desktop_version)

            # Check version requirement
            local dd_major dd_minor dd_rest
            dd_major="${dd_version%%.*}"
            dd_rest="${dd_version#*.}"
            dd_minor="${dd_rest%%.*}"

            if [[ "$dd_major" -gt 4 ]] || { [[ "$dd_major" -eq 4 ]] && [[ "$dd_minor" -ge 50 ]]; }; then
                # Version sufficient - check if sandbox plugin is available
                if _cai_sandbox_available; then
                    sandboxes_available="true"
                fi
                # Check if sandbox feature is actually enabled
                if _cai_sandbox_feature_enabled 2>/dev/null; then
                    sandbox_enabled="true"
                    # Check if ECI is actually enabled (required for cai run)
                    eci_status=$(_cai_eci_status)
                    if [[ "$eci_status" == "enabled" ]]; then
                        eci_enabled="true"
                    fi
                fi
            fi
        fi
    fi

    # Check Sysbox with configured context name
    if _cai_sysbox_available_for_context "$sysbox_context_name"; then
        sysbox_ok="true"
        sysbox_runtime="sysbox-runc"
        sysbox_context_exists="true"
    else
        # Check if context exists even if not usable
        if docker context inspect "$sysbox_context_name" >/dev/null 2>&1; then
            sysbox_context_exists="true"
        fi
    fi

    # Platform-specific checks
    if [[ "$platform" == "wsl" ]]; then
        seccomp_status=$(_cai_check_wsl_seccomp)
        case "$seccomp_status" in
            ok)
                seccomp_compatible="true"
                ;;
            filter_warning)
                seccomp_compatible="false"
                seccomp_warning="WSL 1.1.0+ may have seccomp conflicts"
                ;;
            unavailable|unknown)
                seccomp_compatible="false"
                ;;
        esac
    elif [[ "$platform" == "macos" ]]; then
        # eci_status already set above if Docker Desktop available
        if [[ "$eci_status" == "not_available" ]]; then
            eci_status=$(_cai_eci_status)
        fi
    fi

    # Isolation requires ECI enabled (for sandbox path) OR Sysbox available
    local isolation_available="false"
    if [[ "$eci_enabled" == "true" ]] || [[ "$sysbox_ok" == "true" ]]; then
        isolation_available="true"
    fi

    # Determine recommended action
    if [[ "$eci_enabled" == "true" ]] && [[ "$sysbox_ok" == "true" ]]; then
        recommended_action="ready"
    elif [[ "$eci_enabled" == "true" ]] || [[ "$sysbox_ok" == "true" ]]; then
        recommended_action="ready"  # Either one is sufficient
    elif [[ "$sandbox_enabled" == "true" ]]; then
        recommended_action="enable_eci"  # Sandboxes work but ECI not enabled
    else
        recommended_action="setup_required"
    fi

    # Output JSON
    printf '{\n'
    printf '  "docker_desktop": {\n'
    printf '    "version": "%s",\n' "$(_cai_json_escape "$dd_version")"
    printf '    "sandboxes_available": %s,\n' "$sandboxes_available"
    printf '    "sandboxes_enabled": %s,\n' "$sandbox_enabled"
    printf '    "eci_enabled": %s\n' "$eci_enabled"
    printf '  },\n'
    printf '  "sysbox": {\n'
    printf '    "available": %s,\n' "$sysbox_ok"
    if [[ -n "$sysbox_runtime" ]]; then
        printf '    "runtime": "%s",\n' "$sysbox_runtime"
    else
        printf '    "runtime": null,\n'
    fi
    printf '    "context_exists": %s,\n' "$sysbox_context_exists"
    printf '    "context_name": "%s"\n' "$(_cai_json_escape "$sysbox_context_name")"
    printf '  },\n'
    printf '  "platform": {\n'
    printf '    "type": "%s",\n' "$platform_json"
    if [[ "$platform" == "wsl" ]]; then
        printf '    "seccomp_compatible": %s,\n' "$seccomp_compatible"
        if [[ -n "$seccomp_warning" ]]; then
            printf '    "warning": "%s"\n' "$(_cai_json_escape "$seccomp_warning")"
        else
            printf '    "warning": null\n'
        fi
    elif [[ "$platform" == "macos" ]]; then
        printf '    "eci_status": "%s"\n' "$eci_status"
    else
        printf '    "warning": null\n'
    fi
    printf '  },\n'
    printf '  "summary": {\n'
    printf '    "eci_enabled": %s,\n' "$eci_enabled"
    printf '    "sysbox_ok": %s,\n' "$sysbox_ok"
    printf '    "isolation_available": %s,\n' "$isolation_available"
    printf '    "recommended_action": "%s"\n' "$recommended_action"
    printf '  }\n'
    printf '}\n'

    # Exit code: 0 if any isolation available, 1 if not
    if [[ "$isolation_available" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

return 0
