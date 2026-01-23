#!/usr/bin/env bash
# ==============================================================================
# ContainAI Doctor Command - System Health Check and Diagnostics
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_doctor()              - Run all checks and output formatted report
#   _cai_doctor_json()         - Run all checks and output JSON report
#   _cai_doctor_fix()          - Auto-remediate fixable issues and output report
#   _cai_check_wsl_seccomp()   - Check WSL2 seccomp compatibility status
#   _cai_check_kernel_for_sysbox() - Check kernel version for Sysbox compatibility
#   _cai_select_context()      - Auto-select Docker context based on Sysbox availability
#
# Requirements:
#   Sysbox: Required for container isolation
#
# Dependencies:
#   - Requires lib/core.sh to be sourced first for logging functions
#   - Requires lib/platform.sh to be sourced first for platform detection
#   - Requires lib/docker.sh to be sourced first for Docker availability checks
#   - Requires lib/ssh.sh to be sourced first for SSH constants and version check
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
# Kernel Version Check for Sysbox
# ==============================================================================

# Check kernel version for Sysbox compatibility
# Sysbox requires kernel 5.5+ for user namespace and syscall interception features
# Returns: 0=compatible, 1=incompatible
# Outputs: Kernel version to stdout (e.g., "6.6")
# Sets: _CAI_KERNEL_MAJOR, _CAI_KERNEL_MINOR with parsed values
# Note: Uses bash arithmetic only (no bc dependency)
_cai_check_kernel_for_sysbox() {
    local kernel_version major minor
    _CAI_KERNEL_MAJOR=""
    _CAI_KERNEL_MINOR=""

    kernel_version=$(uname -r)

    # Parse major.minor from kernel version
    # Handles WSL2 format: 5.15.133.1-microsoft-standard-WSL2
    # cut -d. -f1 gets "5", cut -d. -f2 gets "15"
    major=$(printf '%s' "$kernel_version" | cut -d. -f1)
    minor=$(printf '%s' "$kernel_version" | cut -d. -f2)

    # Validate we got numbers
    if ! [[ "$major" =~ ^[0-9]+$ ]] || ! [[ "$minor" =~ ^[0-9]+$ ]]; then
        _cai_warn "Could not parse kernel version: $kernel_version"
        # Output the raw version anyway
        printf '%s' "$kernel_version"
        return 0  # Don't block, just warn
    fi

    _CAI_KERNEL_MAJOR="$major"
    _CAI_KERNEL_MINOR="$minor"

    # Output parsed version
    printf '%s.%s' "$major" "$minor"

    # Sysbox requires 5.5+
    if [[ "$major" -lt 5 ]] || { [[ "$major" -eq 5 ]] && [[ "$minor" -lt 5 ]]; }; then
        return 1
    fi

    return 0
}

# ==============================================================================
# Context Auto-Selection
# ==============================================================================

# Auto-select Docker context based on Sysbox availability
# Returns context name via stdout:
#   - "containai-secure" for Sysbox context (or config override)
#   - Nothing (return 1) if no isolation available
# Arguments: $1 = config override for context name (optional)
#            $2 = debug flag ("debug" to enable debug output)
# Returns: 0=context selected, 1=no isolation available
# Outputs: Debug messages to stderr if debug flag is set
_cai_select_context() {
    local config_context_name="${1:-}"
    local debug_flag="${2:-}"

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
        printf '%s\n' "[DEBUG] Context selection: No isolation available (context '$context_name' not ready)" >&2
    fi
    return 1
}

# Check if Sysbox is available for a specific context
# Arguments: $1 = context name
# Returns: 0=available, 1=not available
# Outputs: Sets _CAI_SYSBOX_CONTEXT_ERROR with reason on failure
# Error codes:
#   socket_not_found - Socket file does not exist (unix socket contexts)
#   context_not_found - Docker context not configured
#   timeout - Connection timed out
#   permission_denied - User not in docker group (Lima/macOS)
#   connection_refused - Docker daemon not running
#   daemon_unavailable - Generic daemon error
#   runtime_not_found - Sysbox runtime not registered
_cai_sysbox_available_for_context() {
    local context_name="${1:-containai-secure}"
    _CAI_SYSBOX_CONTEXT_ERROR=""

    # Check if context exists
    if ! docker context inspect "$context_name" >/dev/null 2>&1; then
        _CAI_SYSBOX_CONTEXT_ERROR="context_not_found"
        return 1
    fi

    # For unix socket contexts, check if socket file exists before attempting docker info
    local context_host
    context_host=$(docker context inspect "$context_name" --format '{{.Endpoints.docker.Host}}' 2>/dev/null) || context_host=""
    if [[ "$context_host" == unix://* ]]; then
        local socket_path="${context_host#unix://}"
        if [[ ! -S "$socket_path" ]]; then
            _CAI_SYSBOX_CONTEXT_ERROR="socket_not_found"
            return 1
        fi
    fi

    # Check if we can connect to the daemon on this context
    local info_output rc
    info_output=$(_cai_timeout 10 docker --context "$context_name" info 2>&1) && rc=0 || rc=$?

    if [[ $rc -eq 124 ]]; then
        _CAI_SYSBOX_CONTEXT_ERROR="timeout"
        return 1
    fi

    if [[ $rc -ne 0 ]]; then
        # Diagnose specific failure modes
        if printf '%s' "$info_output" | grep -qi "permission denied"; then
            _CAI_SYSBOX_CONTEXT_ERROR="permission_denied"
        elif printf '%s' "$info_output" | grep -qi "connection refused"; then
            _CAI_SYSBOX_CONTEXT_ERROR="connection_refused"
        else
            _CAI_SYSBOX_CONTEXT_ERROR="daemon_unavailable"
        fi
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
# Error codes:
#   socket_not_found - Socket file does not exist
#   context_not_found - Docker context not configured
#   timeout - Connection timed out
#   permission_denied - User not in docker group (Lima/macOS)
#   connection_refused - Docker daemon not running
#   daemon_unavailable - Generic daemon error
#   runtime_not_found - Sysbox runtime not registered
_cai_sysbox_available() {
    _CAI_SYSBOX_ERROR=""
    _CAI_SYSBOX_CONTEXT_EXISTS="false"

    # Determine expected socket based on platform
    # - WSL2: Uses dedicated socket at _CAI_SECURE_SOCKET
    # - macOS: Uses Lima socket at _CAI_LIMA_SOCKET_PATH
    # - Native Linux: Uses default socket at /var/run/docker.sock
    local socket platform
    platform=$(_cai_detect_platform)
    case "$platform" in
        wsl)
            socket="${_CAI_SECURE_SOCKET:-/var/run/docker-containai.sock}"
            ;;
        macos)
            socket="${_CAI_LIMA_SOCKET_PATH:-$HOME/.lima/containai-secure/sock/docker.sock}"
            ;;
        linux)
            socket="/var/run/docker.sock"
            ;;
        *)
            socket="${_CAI_SECURE_SOCKET:-/var/run/docker-containai.sock}"
            ;;
    esac

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
        # Diagnose specific failure modes
        if printf '%s' "$info_output" | grep -qi "permission denied"; then
            _CAI_SYSBOX_ERROR="permission_denied"
        elif printf '%s' "$info_output" | grep -qi "connection refused"; then
            _CAI_SYSBOX_ERROR="connection_refused"
        else
            _CAI_SYSBOX_ERROR="daemon_unavailable"
        fi
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
# Returns: 0 if Sysbox isolation is available
#          1 if no isolation available (cannot proceed)
_cai_doctor() {
    local sysbox_ok="false"
    local docker_cli_ok="false"
    local docker_daemon_ok="false"
    local platform
    local seccomp_status=""
    local kernel_ok="true"  # Default to true (macOS doesn't need kernel check)
    local kernel_version=""

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

    # === Sysbox / Secure Engine Section ===
    printf '%s\n' "Sysbox Isolation"

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
        printf '  %-44s %s\n' "Sysbox available:" "[ERROR] Not configured"
        local sysbox_error="${_CAI_SYSBOX_CONTEXT_ERROR:-${_CAI_SYSBOX_ERROR:-}}"
        case "$sysbox_error" in
            socket_not_found)
                if [[ "$platform" == "macos" ]]; then
                    printf '  %-44s %s\n' "" "(Lima VM not running or not provisioned)"
                    printf '  %-44s %s\n' "" "(Run 'cai setup' or 'limactl start containai-secure')"
                else
                    printf '  %-44s %s\n' "" "(Run 'cai setup' to install Sysbox)"
                fi
                ;;
            context_not_found)
                printf '  %-44s %s\n' "" "(Run 'cai setup' to configure '$sysbox_context_name' context)"
                ;;
            permission_denied)
                if [[ "$platform" == "macos" ]]; then
                    printf '  %-44s %s\n' "" "(User not in docker group inside Lima VM)"
                    printf '  %-44s %s\n' "" "(Run 'cai setup' to repair, or restart Lima VM)"
                else
                    printf '  %-44s %s\n' "" "(Permission denied - check docker group membership)"
                fi
                ;;
            connection_refused)
                if [[ "$platform" == "macos" ]]; then
                    printf '  %-44s %s\n' "" "(Docker daemon not running inside Lima VM)"
                    printf '  %-44s %s\n' "" "(Try: limactl shell containai-secure sudo systemctl start docker)"
                else
                    printf '  %-44s %s\n' "" "(Docker daemon not running)"
                fi
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

        # Kernel version check (WSL2 and Linux need kernel 5.5+ for Sysbox)
        kernel_version=$(_cai_check_kernel_for_sysbox) && kernel_ok="true" || kernel_ok="false"
        if [[ "$kernel_ok" == "true" ]]; then
            printf '  %-44s %s\n' "Kernel version: $kernel_version" "[OK]"
        else
            printf '  %-44s %s\n' "Kernel version: $kernel_version" "[ERROR]"
            printf '  %-44s %s\n' "" "(Sysbox requires kernel 5.5+)"
        fi

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
        # Note: macOS uses Lima VM, kernel is inside the VM (Ubuntu 24.04 has 5.15+)
        printf '  %-44s %s\n' "Sysbox runs inside Lima VM" "[OK]"
        printf '\n'
    elif [[ "$platform" == "linux" ]]; then
        printf '%s\n' "Platform: Linux"

        # Kernel version check (Linux needs kernel 5.5+ for Sysbox)
        kernel_version=$(_cai_check_kernel_for_sysbox) && kernel_ok="true" || kernel_ok="false"
        if [[ "$kernel_ok" == "true" ]]; then
            printf '  %-44s %s\n' "Kernel version: $kernel_version" "[OK]"
        else
            printf '  %-44s %s\n' "Kernel version: $kernel_version" "[ERROR]"
            printf '  %-44s %s\n' "" "(Sysbox requires kernel 5.5+)"
        fi

        printf '\n'
    fi

    # === ContainAI Docker Section ===
    local containai_docker_ok="false"
    local containai_docker_sysbox_default="false"

    printf '%s\n' "ContainAI Docker"

    # Check containai docker availability
    if _cai_containai_docker_available; then
        containai_docker_ok="true"
        printf '  %-44s %s\n' "Context 'docker-containai':" "[OK]"
        printf '  %-44s %s\n' "Socket: $_CAI_CONTAINAI_DOCKER_SOCKET" "[OK]"

        # Check if sysbox-runc is available and default
        if _cai_containai_docker_has_sysbox; then
            printf '  %-44s %s\n' "Runtime: sysbox-runc" "[OK] Available"

            if _cai_containai_docker_sysbox_is_default; then
                containai_docker_sysbox_default="true"
                printf '  %-44s %s\n' "Default runtime: sysbox-runc" "[OK]"
            else
                local actual_default
                actual_default=$(_cai_containai_docker_default_runtime) || actual_default="unknown"
                printf '  %-44s %s\n' "Default runtime: $actual_default" "[WARN]"
                printf '  %-44s %s\n' "" "(Expected sysbox-runc as default)"
            fi
        else
            printf '  %-44s %s\n' "Runtime: sysbox-runc" "[ERROR] Not found"
        fi
    else
        printf '  %-44s %s\n' "ContainAI Docker:" "[NOT INSTALLED]"
        case "${_CAI_CONTAINAI_ERROR:-}" in
            context_not_found)
                printf '  %-44s %s\n' "" "(Context 'docker-containai' not configured)"
                ;;
            wrong_endpoint)
                printf '  %-44s %s\n' "" "(Context 'docker-containai' points to wrong socket)"
                printf '  %-44s %s\n' "" "(Expected: unix://$_CAI_CONTAINAI_DOCKER_SOCKET)"
                ;;
            socket_not_found)
                printf '  %-44s %s\n' "" "(Socket $_CAI_CONTAINAI_DOCKER_SOCKET not found)"
                ;;
            connection_refused|daemon_unavailable)
                printf '  %-44s %s\n' "" "(containai-docker service not running)"
                printf '  %-44s %s\n' "" "(Try: sudo systemctl start containai-docker)"
                ;;
            *)
                printf '  %-44s %s\n' "" "(Run 'sudo scripts/install-containai-docker.sh')"
                ;;
        esac
    fi

    printf '\n'

    # === SSH Section ===
    local ssh_key_ok="false"
    local ssh_config_dir_ok="false"
    local ssh_include_ok="false"
    local ssh_version_ok="false"
    local ssh_version=""
    local ssh_all_ok="false"

    printf '%s\n' "SSH"

    # Check OpenSSH version (7.3+ required for Include directive)
    if ssh_version=$(_cai_check_ssh_version 2>/dev/null); then
        ssh_version_ok="true"
        printf '  %-44s %s\n' "OpenSSH version: $ssh_version" "[OK]"
    else
        if [[ -n "$ssh_version" ]]; then
            printf '  %-44s %s\n' "OpenSSH version: $ssh_version" "[ERROR]"
            printf '  %-44s %s\n' "" "(OpenSSH 7.3+ required for Include directive)"
        else
            printf '  %-44s %s\n' "OpenSSH version:" "[ERROR] Cannot determine"
            printf '  %-44s %s\n' "" "(Verify ssh is installed)"
        fi
    fi

    # Check SSH key exists
    local ssh_key_path="$_CAI_SSH_KEY_PATH"
    if [[ -f "$ssh_key_path" ]]; then
        ssh_key_ok="true"
        printf '  %-44s %s\n' "SSH key: $ssh_key_path" "[OK]"
    else
        printf '  %-44s %s\n' "SSH key: $ssh_key_path" "[ERROR] Not found"
        printf '  %-44s %s\n' "" "(Run 'cai setup' to configure SSH)"
    fi

    # Check SSH config directory exists
    local ssh_config_dir="$_CAI_SSH_CONFIG_DIR"
    if [[ -d "$ssh_config_dir" ]]; then
        ssh_config_dir_ok="true"
        printf '  %-44s %s\n' "SSH config dir: $ssh_config_dir" "[OK]"
    else
        printf '  %-44s %s\n' "SSH config dir: $ssh_config_dir" "[ERROR] Not found"
        printf '  %-44s %s\n' "" "(Run 'cai setup' to configure SSH)"
    fi

    # Check Include directive in ~/.ssh/config
    local ssh_config="$HOME/.ssh/config"
    local include_pattern='^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]+[^#]*containai\.d/\*\.conf'
    if [[ -f "$ssh_config" ]] && grep -qE "$include_pattern" "$ssh_config" 2>/dev/null; then
        ssh_include_ok="true"
        printf '  %-44s %s\n' "Include directive in ~/.ssh/config:" "[OK]"
    else
        if [[ ! -f "$ssh_config" ]]; then
            printf '  %-44s %s\n' "Include directive in ~/.ssh/config:" "[ERROR] File not found"
        else
            printf '  %-44s %s\n' "Include directive in ~/.ssh/config:" "[ERROR] Not present"
        fi
        printf '  %-44s %s\n' "" "(Run 'cai setup' to configure SSH)"
    fi

    # SSH connectivity test for running containers (only if containai-docker is available)
    if [[ "$ssh_key_ok" == "true" ]] && [[ "$ssh_include_ok" == "true" ]] && [[ "$containai_docker_ok" == "true" ]]; then
        # Check if any ContainAI containers are running (with timeout to keep doctor fast)
        local running_containers
        running_containers=$(_cai_timeout 5 docker --context "${_CAI_CONTAINAI_DOCKER_CONTEXT:-docker-containai}" ps --filter "label=containai.workspace" --format '{{.Names}}' 2>/dev/null | head -1) || running_containers=""
        if [[ -n "$running_containers" ]]; then
            local test_container="$running_containers"
            local ssh_port
            ssh_port=$(_cai_timeout 5 docker --context "${_CAI_CONTAINAI_DOCKER_CONTEXT:-docker-containai}" inspect "$test_container" --format '{{index .Config.Labels "containai.ssh-port"}}' 2>/dev/null) || ssh_port=""
            if [[ -n "$ssh_port" ]]; then
                # Try connectivity test with BatchMode and short timeout
                # Use same known_hosts file as cai shell/run for accurate UX reflection
                local known_hosts_file="${_CAI_KNOWN_HOSTS_FILE:-$HOME/.config/containai/known_hosts}"
                local known_hosts_opt="-o UserKnownHostsFile=$known_hosts_file"
                # Use accept-new if supported, otherwise no for strict checking
                local strict_opt="-o StrictHostKeyChecking=accept-new"
                if ! _cai_check_ssh_accept_new_support 2>/dev/null; then
                    strict_opt="-o StrictHostKeyChecking=no"
                fi
                if ssh -o BatchMode=yes -o ConnectTimeout=5 "$strict_opt" \
                       "$known_hosts_opt" -i "$ssh_key_path" \
                       -p "$ssh_port" agent@localhost true 2>/dev/null; then
                    printf '  %-44s %s\n' "SSH connectivity ($test_container):" "[OK]"
                else
                    printf '  %-44s %s\n' "SSH connectivity ($test_container):" "[WARN] Failed"
                    printf '  %-44s %s\n' "" "(Container may need 'cai import' or SSH restart)"
                fi
            else
                printf '  %-44s %s\n' "SSH connectivity ($test_container):" "[SKIP] No SSH port label"
            fi
        fi
    fi

    # Summary for SSH section
    if [[ "$ssh_version_ok" == "true" ]] && [[ "$ssh_key_ok" == "true" ]] && \
       [[ "$ssh_config_dir_ok" == "true" ]] && [[ "$ssh_include_ok" == "true" ]]; then
        ssh_all_ok="true"
    fi

    printf '\n'

    # === Resources Section ===
    printf '%s\n' "Resources"

    # Detect host resources and configured limits
    local resources detected_memory_gb detected_cpus container_memory container_cpus
    resources=$(_cai_detect_resources 50 2 1)
    detected_memory_gb=$(printf '%s' "$resources" | awk '{print $1}')
    detected_cpus=$(printf '%s' "$resources" | awk '{print $2}')
    container_memory=$(printf '%s' "$resources" | awk '{print $3}')
    container_cpus=$(printf '%s' "$resources" | awk '{print $4}')

    printf '  %-44s %s\n' "Host memory: ${detected_memory_gb}GB" "[OK]"
    printf '  %-44s %s\n' "Host CPUs: $detected_cpus" "[OK]"

    # Check if config overrides are set
    local config_memory="${_CAI_CONTAINER_MEMORY:-}"
    local config_cpus="${_CAI_CONTAINER_CPUS:-}"

    if [[ -n "$config_memory" ]]; then
        printf '  %-44s %s\n' "Container memory: $config_memory" "(configured)"
    else
        printf '  %-44s %s\n' "Container memory: $container_memory" "(50% of host, 2GB min)"
    fi

    if [[ -n "$config_cpus" ]]; then
        printf '  %-44s %s\n' "Container CPUs: $config_cpus" "(configured)"
    else
        printf '  %-44s %s\n' "Container CPUs: $container_cpus" "(50% of host, 1 min)"
    fi

    printf '\n'

    # === Summary Section ===
    printf '%s\n' "Summary"

    # Isolation requires both Sysbox available AND compatible kernel
    local isolation_ready="false"
    if [[ "$sysbox_ok" == "true" ]] && [[ "$kernel_ok" == "true" ]]; then
        isolation_ready="true"
    fi

    # Sysbox path status
    if [[ "$isolation_ready" == "true" ]]; then
        printf '  %-44s %s\n' "Sysbox:" "[OK] Ready"
        printf '  %-44s %s\n' "Status:" "[OK] Ready to use 'cai run'"
    elif [[ "$sysbox_ok" == "true" ]] && [[ "$kernel_ok" == "false" ]]; then
        # Sysbox installed but kernel too old
        printf '  %-44s %s\n' "Sysbox:" "[WARN] Installed but kernel incompatible"
        printf '  %-44s %s\n' "Status:" "[ERROR] Kernel 5.5+ required for Sysbox"
        printf '  %-44s %s\n' "Recommended:" "Upgrade kernel to 5.5+"
    else
        printf '  %-44s %s\n' "Sysbox:" "[ERROR] Not available"
        printf '  %-44s %s\n' "Status:" "[ERROR] No isolation available"
        printf '  %-44s %s\n' "Recommended:" "Run 'cai setup' to configure Sysbox"
    fi

    # ContainAI Docker summary
    if [[ "$containai_docker_ok" == "true" ]] && [[ "$containai_docker_sysbox_default" == "true" ]]; then
        printf '  %-44s %s\n' "ContainAI Docker:" "[OK] sysbox-runc default"
    elif [[ "$containai_docker_ok" == "true" ]]; then
        printf '  %-44s %s\n' "ContainAI Docker:" "[WARN] sysbox-runc not default"
    else
        printf '  %-44s %s\n' "ContainAI Docker:" "[NOT INSTALLED]"
    fi

    # SSH summary
    if [[ "$ssh_all_ok" == "true" ]]; then
        printf '  %-44s %s\n' "SSH:" "[OK] Configured"
    else
        printf '  %-44s %s\n' "SSH:" "[ERROR] Not configured"
        printf '  %-44s %s\n' "Recommended:" "Run 'cai setup' to configure SSH"
    fi

    # Exit code: 0 if isolation ready AND SSH configured, 1 if not
    if [[ "$isolation_ready" == "true" ]] && [[ "$ssh_all_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# Doctor Fix Mode
# ==============================================================================

# Run doctor with auto-remediation for fixable issues
# Returns: 0 if all issues fixed, 1 if unfixable issues remain
# Outputs: Formatted report showing what was fixed, skipped, or failed
_cai_doctor_fix() {
    local fixed_count=0
    local skip_count=0
    local fail_count=0
    local platform

    platform=$(_cai_detect_platform)

    printf '%s\n' "ContainAI Doctor (Fix Mode)"
    printf '%s\n' "==========================="
    printf '\n'

    # === SSH Key Fix ===
    local ssh_key_path="$_CAI_SSH_KEY_PATH"
    local ssh_pubkey_path="$_CAI_SSH_PUBKEY_PATH"
    local config_dir="$_CAI_CONFIG_DIR"

    printf '%s\n' "SSH Key"

    # Create config directory if missing
    if [[ ! -d "$config_dir" ]]; then
        printf '  %-50s' "Creating $config_dir"
        if mkdir -p "$config_dir" && chmod 700 "$config_dir"; then
            printf '%s\n' "[FIXED]"
            ((fixed_count++))
        else
            printf '%s\n' "[FAIL]"
            ((fail_count++))
        fi
    else
        # Check/fix config directory permissions
        local dir_perms
        dir_perms=$(stat -c "%a" "$config_dir" 2>/dev/null || stat -f "%OLp" "$config_dir" 2>/dev/null)
        if [[ "$dir_perms" != "700" ]]; then
            printf '  %-50s' "Fixing permissions on $config_dir"
            if chmod 700 "$config_dir"; then
                printf '%s\n' "[FIXED]"
                ((fixed_count++))
            else
                printf '%s\n' "[FAIL]"
                ((fail_count++))
            fi
        else
            printf '  %-50s %s\n' "Config directory permissions" "[OK]"
        fi
    fi

    # Generate SSH key if missing
    if [[ ! -f "$ssh_key_path" ]]; then
        printf '  %-50s' "Generating SSH key"
        if command -v ssh-keygen >/dev/null 2>&1; then
            if ssh-keygen -t ed25519 -f "$ssh_key_path" -N "" -C "containai" >/dev/null 2>&1; then
                chmod 600 "$ssh_key_path"
                chmod 644 "$ssh_pubkey_path"
                printf '%s\n' "[FIXED]"
                ((fixed_count++))
            else
                printf '%s\n' "[FAIL]"
                ((fail_count++))
            fi
        else
            printf '%s\n' "[FAIL] ssh-keygen not found"
            ((fail_count++))
        fi
    else
        # Check/fix private key permissions
        local key_perms
        key_perms=$(stat -c "%a" "$ssh_key_path" 2>/dev/null || stat -f "%OLp" "$ssh_key_path" 2>/dev/null)
        if [[ "$key_perms" != "600" ]]; then
            printf '  %-50s' "Fixing permissions on SSH key"
            if chmod 600 "$ssh_key_path"; then
                printf '%s\n' "[FIXED]"
                ((fixed_count++))
            else
                printf '%s\n' "[FAIL]"
                ((fail_count++))
            fi
        else
            printf '  %-50s %s\n' "SSH key exists" "[OK]"
        fi

        # Regenerate public key if missing
        if [[ ! -f "$ssh_pubkey_path" ]]; then
            printf '  %-50s' "Regenerating public key"
            if ssh-keygen -y -f "$ssh_key_path" > "$ssh_pubkey_path" 2>/dev/null; then
                chmod 644 "$ssh_pubkey_path"
                printf '%s\n' "[FIXED]"
                ((fixed_count++))
            else
                printf '%s\n' "[FAIL]"
                ((fail_count++))
            fi
        fi
    fi

    printf '\n'

    # === SSH Config Fix ===
    local ssh_dir="$HOME/.ssh"
    local ssh_config_dir="$_CAI_SSH_CONFIG_DIR"
    local ssh_config="$ssh_dir/config"
    local include_line="Include ~/.ssh/containai.d/*.conf"
    local include_pattern='^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]+[^#]*containai\.d/\*\.conf'

    printf '%s\n' "SSH Config"

    # Create ~/.ssh/ directory if missing
    if [[ ! -d "$ssh_dir" ]]; then
        printf '  %-50s' "Creating $ssh_dir"
        if mkdir -p "$ssh_dir" && chmod 700 "$ssh_dir"; then
            printf '%s\n' "[FIXED]"
            ((fixed_count++))
        else
            printf '%s\n' "[FAIL]"
            ((fail_count++))
        fi
    else
        # Check/fix .ssh directory permissions
        local ssh_dir_perms
        ssh_dir_perms=$(stat -c "%a" "$ssh_dir" 2>/dev/null || stat -f "%OLp" "$ssh_dir" 2>/dev/null)
        if [[ "$ssh_dir_perms" != "700" ]]; then
            printf '  %-50s' "Fixing permissions on $ssh_dir"
            if chmod 700 "$ssh_dir"; then
                printf '%s\n' "[FIXED]"
                ((fixed_count++))
            else
                printf '%s\n' "[FAIL]"
                ((fail_count++))
            fi
        fi
    fi

    # Create ~/.ssh/containai.d/ directory if missing
    if [[ ! -d "$ssh_config_dir" ]]; then
        printf '  %-50s' "Creating $ssh_config_dir"
        if mkdir -p "$ssh_config_dir" && chmod 700 "$ssh_config_dir"; then
            printf '%s\n' "[FIXED]"
            ((fixed_count++))
        else
            printf '%s\n' "[FAIL]"
            ((fail_count++))
        fi
    else
        # Check/fix containai.d directory permissions
        local config_dir_perms
        config_dir_perms=$(stat -c "%a" "$ssh_config_dir" 2>/dev/null || stat -f "%OLp" "$ssh_config_dir" 2>/dev/null)
        if [[ "$config_dir_perms" != "700" ]]; then
            printf '  %-50s' "Fixing permissions on $ssh_config_dir"
            if chmod 700 "$ssh_config_dir"; then
                printf '%s\n' "[FIXED]"
                ((fixed_count++))
            else
                printf '%s\n' "[FAIL]"
                ((fail_count++))
            fi
        else
            printf '  %-50s %s\n' "SSH config directory" "[OK]"
        fi
    fi

    # Add/fix Include directive in ~/.ssh/config
    if [[ ! -f "$ssh_config" ]]; then
        printf '  %-50s' "Creating $ssh_config with Include"
        if printf '%s\n' "$include_line" > "$ssh_config" && chmod 600 "$ssh_config"; then
            printf '%s\n' "[FIXED]"
            ((fixed_count++))
        else
            printf '%s\n' "[FAIL]"
            ((fail_count++))
        fi
    else
        # Check if Include directive exists and is at top
        local include_present=false
        local include_at_top=false

        if grep -qE "$include_pattern" "$ssh_config" 2>/dev/null; then
            include_present=true
            local first_effective_line
            first_effective_line=$(grep -v '^[[:space:]]*$' "$ssh_config" | grep -v '^[[:space:]]*#' | head -1)
            if printf '%s' "$first_effective_line" | grep -qE "$include_pattern"; then
                include_at_top=true
            fi
        fi

        if [[ "$include_present" == "true" ]] && [[ "$include_at_top" == "true" ]]; then
            printf '  %-50s %s\n' "Include directive" "[OK]"
        else
            printf '  %-50s' "Adding Include directive to top of config"
            local temp_file
            if temp_file=$(mktemp 2>/dev/null); then
                if {
                    printf '%s\n\n' "$include_line"
                    grep -vE "$include_pattern" "$ssh_config" 2>/dev/null || true
                } > "$temp_file" && cp "$temp_file" "$ssh_config" && rm -f "$temp_file"; then
                    printf '%s\n' "[FIXED]"
                    ((fixed_count++))
                else
                    rm -f "$temp_file" 2>/dev/null || true
                    printf '%s\n' "[FAIL]"
                    ((fail_count++))
                fi
            else
                printf '%s\n' "[FAIL]"
                ((fail_count++))
            fi
        fi

        # Check/fix ssh config file permissions
        local ssh_config_perms
        ssh_config_perms=$(stat -c "%a" "$ssh_config" 2>/dev/null || stat -f "%OLp" "$ssh_config" 2>/dev/null)
        if [[ "$ssh_config_perms" != "600" && "$ssh_config_perms" != "644" ]]; then
            printf '  %-50s' "Fixing permissions on $ssh_config"
            if chmod 600 "$ssh_config"; then
                printf '%s\n' "[FIXED]"
                ((fixed_count++))
            else
                printf '%s\n' "[FAIL]"
                ((fail_count++))
            fi
        fi
    fi

    printf '\n'

    # === Stale SSH Config Cleanup ===
    printf '%s\n' "Stale SSH Configs"

    # Only attempt cleanup if Docker is available and at least one daemon is reachable
    if command -v docker >/dev/null 2>&1; then
        # Check if any Docker context is reachable
        local docker_reachable=false
        if _cai_timeout 5 docker info >/dev/null 2>&1; then
            docker_reachable=true
        elif docker context inspect containai-secure >/dev/null 2>&1 && \
             _cai_timeout 5 docker --context containai-secure info >/dev/null 2>&1; then
            docker_reachable=true
        fi

        if [[ "$docker_reachable" == "true" ]]; then
            # Run cleanup silently and capture result
            local cleanup_output
            if cleanup_output=$(_cai_ssh_cleanup "false" 2>&1); then
                # Parse cleanup output for what was cleaned
                local cleaned
                cleaned=$(printf '%s' "$cleanup_output" | grep -c '\[CLEANED\]' || true)
                if [[ "$cleaned" -gt 0 ]]; then
                    printf '  %-50s %s\n' "Cleaned $cleaned stale config(s)" "[FIXED]"
                    ((fixed_count += cleaned))
                else
                    printf '  %-50s %s\n' "No stale configs found" "[OK]"
                fi
            else
                printf '  %-50s %s\n' "Cleanup" "[SKIP] Docker unreachable"
                ((skip_count++))
            fi
        else
            printf '  %-50s %s\n' "Cleanup" "[SKIP] Docker daemon not reachable"
            ((skip_count++))
        fi
    else
        printf '  %-50s %s\n' "Cleanup" "[SKIP] Docker not installed"
        ((skip_count++))
    fi

    printf '\n'

    # === Unfixable Issues (informational) ===
    printf '%s\n' "Cannot Auto-Fix"

    # Sysbox availability
    local sysbox_context_name="containai-secure"
    local config_context
    config_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || config_context=""
    if [[ -n "$config_context" ]]; then
        sysbox_context_name="$config_context"
    fi

    if ! _cai_sysbox_available_for_context "$sysbox_context_name" 2>/dev/null; then
        local sysbox_error="${_CAI_SYSBOX_CONTEXT_ERROR:-unknown}"
        case "$sysbox_error" in
            socket_not_found)
                printf '  %-50s %s\n' "Sysbox socket not found" "[MANUAL] Run 'cai setup'"
                ((skip_count++))
                ;;
            context_not_found)
                printf '  %-50s %s\n' "Docker context not configured" "[MANUAL] Run 'cai setup'"
                ((skip_count++))
                ;;
            runtime_not_found)
                printf '  %-50s %s\n' "Sysbox runtime not installed" "[MANUAL] Run 'cai setup'"
                ((skip_count++))
                ;;
            connection_refused|daemon_unavailable)
                printf '  %-50s %s\n' "Docker daemon not running" "[MANUAL] Start Docker"
                ((skip_count++))
                ;;
            permission_denied)
                printf '  %-50s %s\n' "Permission denied" "[MANUAL] Check docker group"
                ((skip_count++))
                ;;
            *)
                printf '  %-50s %s\n' "Sysbox not available" "[MANUAL] Run 'cai setup'"
                ((skip_count++))
                ;;
        esac
    else
        printf '  %-50s %s\n' "Sysbox" "[OK] Already configured"
    fi

    # Kernel compatibility check (WSL2 and Linux only)
    if [[ "$platform" == "wsl" ]] || [[ "$platform" == "linux" ]]; then
        if ! _cai_check_kernel_for_sysbox >/dev/null 2>&1; then
            printf '  %-50s %s\n' "Kernel version" "[MANUAL] Upgrade to 5.5+"
            ((skip_count++))
        fi
    fi

    printf '\n'

    # === Summary ===
    printf '%s\n' "Summary"
    printf '  %-50s %s\n' "Fixed:" "$fixed_count"
    printf '  %-50s %s\n' "Skipped (manual action required):" "$skip_count"
    printf '  %-50s %s\n' "Failed:" "$fail_count"

    printf '\n'

    # Final status
    if [[ $fail_count -gt 0 ]]; then
        printf '%s\n' "Some fixes failed. Check output above for details."
        return 1
    elif [[ $skip_count -gt 0 ]]; then
        printf '%s\n' "Some issues require manual action. Run 'cai setup' for full setup."
        return 1
    else
        printf '%s\n' "All fixable issues resolved."
        return 0
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
# Returns: 0 if Sysbox isolation is available
#          1 if no isolation available (cannot proceed)
_cai_doctor_json() {
    local sysbox_ok="false"
    local platform
    local platform_json
    local seccomp_status=""
    local seccomp_compatible="true"
    local seccomp_warning=""
    local sysbox_runtime=""
    local sysbox_context_exists="false"
    local sysbox_context_name="containai-secure"
    local recommended_action="setup_required"
    local kernel_version=""
    local kernel_compatible="true"

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

    # Check Sysbox with configured context name
    local sysbox_error=""
    if _cai_sysbox_available_for_context "$sysbox_context_name"; then
        sysbox_ok="true"
        sysbox_runtime="sysbox-runc"
        sysbox_context_exists="true"
    else
        sysbox_error="${_CAI_SYSBOX_CONTEXT_ERROR:-unknown}"
        # Check if context exists even if not usable
        if docker context inspect "$sysbox_context_name" >/dev/null 2>&1; then
            sysbox_context_exists="true"
        fi
    fi

    # Platform-specific checks
    if [[ "$platform" == "wsl" ]] || [[ "$platform" == "linux" ]]; then
        # Kernel version check (WSL2 and Linux need kernel 5.5+ for Sysbox)
        kernel_version=$(_cai_check_kernel_for_sysbox) && kernel_compatible="true" || kernel_compatible="false"
    fi

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
    fi

    # Isolation requires Sysbox available AND compatible kernel
    local isolation_available="false"
    if [[ "$sysbox_ok" == "true" ]] && [[ "$kernel_compatible" == "true" ]]; then
        isolation_available="true"
        recommended_action="ready"
    elif [[ "$sysbox_ok" == "true" ]] && [[ "$kernel_compatible" == "false" ]]; then
        # Sysbox installed but kernel too old
        recommended_action="upgrade_kernel"
    else
        # Determine recommended action based on error code
        case "$sysbox_error" in
            socket_not_found)
                if [[ "$platform" == "macos" ]]; then
                    recommended_action="start_lima_vm"
                else
                    recommended_action="setup_required"
                fi
                ;;
            permission_denied)
                if [[ "$platform" == "macos" ]]; then
                    recommended_action="restart_lima_vm"
                else
                    recommended_action="setup_required"
                fi
                ;;
            connection_refused)
                if [[ "$platform" == "macos" ]]; then
                    recommended_action="start_docker_in_lima"
                else
                    recommended_action="start_docker"
                fi
                ;;
            *)
                recommended_action="setup_required"
                ;;
        esac
    fi

    # Check containai-docker status
    local containai_docker_ok="false"
    local containai_docker_error=""
    local containai_docker_sysbox_default="false"
    local containai_docker_default_runtime=""

    if _cai_containai_docker_available; then
        containai_docker_ok="true"
        containai_docker_default_runtime=$(_cai_containai_docker_default_runtime) || containai_docker_default_runtime=""
        if _cai_containai_docker_sysbox_is_default; then
            containai_docker_sysbox_default="true"
        fi
    else
        containai_docker_error="${_CAI_CONTAINAI_ERROR:-unknown}"
    fi

    # Check SSH setup
    local ssh_key_ok="false"
    local ssh_config_dir_ok="false"
    local ssh_include_ok="false"
    local ssh_version_ok="false"
    local ssh_version_json=""
    local ssh_all_ok="false"

    # Check OpenSSH version
    if ssh_version_json=$(_cai_check_ssh_version 2>/dev/null); then
        ssh_version_ok="true"
    fi

    # Check SSH key exists
    if [[ -f "$_CAI_SSH_KEY_PATH" ]]; then
        ssh_key_ok="true"
    fi

    # Check SSH config directory exists
    if [[ -d "$_CAI_SSH_CONFIG_DIR" ]]; then
        ssh_config_dir_ok="true"
    fi

    # Check Include directive in ~/.ssh/config
    local ssh_config="$HOME/.ssh/config"
    local include_pattern='^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]+[^#]*containai\.d/\*\.conf'
    if [[ -f "$ssh_config" ]] && grep -qE "$include_pattern" "$ssh_config" 2>/dev/null; then
        ssh_include_ok="true"
    fi

    # All SSH checks pass?
    if [[ "$ssh_version_ok" == "true" ]] && [[ "$ssh_key_ok" == "true" ]] && \
       [[ "$ssh_config_dir_ok" == "true" ]] && [[ "$ssh_include_ok" == "true" ]]; then
        ssh_all_ok="true"
    fi

    # Output JSON
    printf '{\n'
    printf '  "sysbox": {\n'
    printf '    "available": %s,\n' "$sysbox_ok"
    if [[ -n "$sysbox_runtime" ]]; then
        printf '    "runtime": "%s",\n' "$sysbox_runtime"
    else
        printf '    "runtime": null,\n'
    fi
    printf '    "context_exists": %s,\n' "$sysbox_context_exists"
    printf '    "context_name": "%s",\n' "$(_cai_json_escape "$sysbox_context_name")"
    if [[ -n "$sysbox_error" ]]; then
        printf '    "error": "%s"\n' "$(_cai_json_escape "$sysbox_error")"
    else
        printf '    "error": null\n'
    fi
    printf '  },\n'
    printf '  "containai_docker": {\n'
    printf '    "available": %s,\n' "$containai_docker_ok"
    printf '    "context_name": "%s",\n' "$_CAI_CONTAINAI_DOCKER_CONTEXT"
    printf '    "socket": "%s",\n' "$_CAI_CONTAINAI_DOCKER_SOCKET"
    if [[ -n "$containai_docker_default_runtime" ]]; then
        printf '    "default_runtime": "%s",\n' "$(_cai_json_escape "$containai_docker_default_runtime")"
    else
        printf '    "default_runtime": null,\n'
    fi
    printf '    "sysbox_is_default": %s,\n' "$containai_docker_sysbox_default"
    if [[ -n "$containai_docker_error" ]]; then
        printf '    "error": "%s"\n' "$(_cai_json_escape "$containai_docker_error")"
    else
        printf '    "error": null\n'
    fi
    printf '  },\n'
    printf '  "platform": {\n'
    printf '    "type": "%s",\n' "$platform_json"
    if [[ "$platform" == "wsl" ]] || [[ "$platform" == "linux" ]]; then
        printf '    "kernel_version": "%s",\n' "$(_cai_json_escape "$kernel_version")"
        printf '    "kernel_compatible": %s,\n' "$kernel_compatible"
    fi
    if [[ "$platform" == "wsl" ]]; then
        printf '    "seccomp_compatible": %s,\n' "$seccomp_compatible"
        if [[ -n "$seccomp_warning" ]]; then
            printf '    "warning": "%s"\n' "$(_cai_json_escape "$seccomp_warning")"
        else
            printf '    "warning": null\n'
        fi
    else
        printf '    "warning": null\n'
    fi
    printf '  },\n'

    # Resources section
    local resources detected_memory_gb detected_cpus container_memory container_cpus
    resources=$(_cai_detect_resources 50 2 1)
    detected_memory_gb=$(printf '%s' "$resources" | awk '{print $1}')
    detected_cpus=$(printf '%s' "$resources" | awk '{print $2}')
    container_memory=$(printf '%s' "$resources" | awk '{print $3}')
    container_cpus=$(printf '%s' "$resources" | awk '{print $4}')

    # Check if config overrides are set
    local json_config_memory="${_CAI_CONTAINER_MEMORY:-}"
    local json_config_cpus="${_CAI_CONTAINER_CPUS:-}"

    printf '  "resources": {\n'
    printf '    "host_memory_gb": %s,\n' "$detected_memory_gb"
    printf '    "host_cpus": %s,\n' "$detected_cpus"
    printf '    "container_memory": "%s",\n' "$container_memory"
    printf '    "container_cpus": %s,\n' "$container_cpus"
    if [[ -n "$json_config_memory" ]]; then
        printf '    "config_memory": "%s",\n' "$(_cai_json_escape "$json_config_memory")"
    else
        printf '    "config_memory": null,\n'
    fi
    if [[ -n "$json_config_cpus" ]]; then
        printf '    "config_cpus": %s\n' "$json_config_cpus"
    else
        printf '    "config_cpus": null\n'
    fi
    printf '  },\n'
    printf '  "ssh": {\n'
    printf '    "version_ok": %s,\n' "$ssh_version_ok"
    if [[ -n "$ssh_version_json" ]]; then
        printf '    "version": "%s",\n' "$(_cai_json_escape "$ssh_version_json")"
    else
        printf '    "version": null,\n'
    fi
    printf '    "key_exists": %s,\n' "$ssh_key_ok"
    printf '    "key_path": "%s",\n' "$(_cai_json_escape "$_CAI_SSH_KEY_PATH")"
    printf '    "config_dir_exists": %s,\n' "$ssh_config_dir_ok"
    printf '    "config_dir": "%s",\n' "$(_cai_json_escape "$_CAI_SSH_CONFIG_DIR")"
    printf '    "include_directive_present": %s,\n' "$ssh_include_ok"
    printf '    "all_ok": %s\n' "$ssh_all_ok"
    printf '  },\n'
    printf '  "summary": {\n'
    printf '    "sysbox_ok": %s,\n' "$sysbox_ok"
    printf '    "containai_docker_ok": %s,\n' "$containai_docker_ok"
    printf '    "ssh_ok": %s,\n' "$ssh_all_ok"
    printf '    "isolation_available": %s,\n' "$isolation_available"
    printf '    "recommended_action": "%s"\n' "$recommended_action"
    printf '  }\n'
    printf '}\n'

    # Exit code: 0 if Sysbox available AND SSH configured, 1 if not
    if [[ "$isolation_available" == "true" ]] && [[ "$ssh_all_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

return 0
