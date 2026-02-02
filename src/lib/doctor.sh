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
        return 0 # Don't block, just warn
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
#   - "containai-docker" for isolated daemon (all platforms)
#   - Legacy "containai-secure" as fallback for old installs
#   - Config override if specified and available
#   - Nothing (return 1) if no isolation available
# Arguments: $1 = config override for context name (optional)
#            $2 = debug flag ("debug" to enable debug output)
#            $3 = verbose flag ("true" to show auto-repair messages)
# Returns: 0=context selected, 1=no isolation available
# Outputs: Debug messages to stderr if debug flag is set
# Note: Auto-repairs containai-docker context if endpoint is wrong (e.g., after Docker Desktop updates)
_cai_select_context() {
    local config_context_name="${1:-}"
    local debug_flag="${2:-}"
    local verbose_flag="${3:-false}"
    local in_sysbox_container="false"
    if _cai_is_sysbox_container; then
        in_sysbox_container="true"
    fi

    # Try contexts in order:
    # 1. Config override (if provided)
    # 2. containai-docker (isolated daemon on Linux/WSL2, Lima VM on macOS)
    # 3. containai-secure (legacy fallback for old installs)
    local context_name="${config_context_name:-}"
    local primary_context="$_CAI_CONTAINAI_DOCKER_CONTEXT"  # containai-docker
    local fallback_context="${_CAI_LEGACY_CONTEXT:-containai-secure}"

    # Auto-repair containai-docker context if endpoint is wrong
    # This handles Docker Desktop updates on Windows that reset the context
    # Skip inside containers - they use default context, not containai-docker
    if ! _cai_is_container; then
        _cai_auto_repair_containai_context "$verbose_flag" || true
    fi

    # Inside a container, always use the default context (self-contained daemon)
    if _cai_is_container; then
        local default_context="default"
        if _cai_sysbox_available_for_context "$default_context"; then
            if [[ "$debug_flag" == "debug" ]]; then
                if [[ "$in_sysbox_container" == "true" ]]; then
                    printf '%s\n' "[DEBUG] Context selection: Using default context inside Sysbox container" >&2
                else
                    printf '%s\n' "[DEBUG] Context selection: Using default context inside container" >&2
                fi
            fi
            printf '%s' "$default_context"
            return 0
        fi
        if [[ "$debug_flag" == "debug" ]]; then
            printf '%s\n' "[DEBUG] Context selection: Default context not available inside container" >&2
        fi
        return 1
    fi

    # If config specified a context, try it first
    if [[ -n "$context_name" ]]; then
        if _cai_sysbox_available_for_context "$context_name"; then
            if [[ "$debug_flag" == "debug" ]]; then
                printf '%s\n' "[DEBUG] Context selection: Using config context '$context_name' with Sysbox" >&2
            fi
            printf '%s' "$context_name"
            return 0
        fi
        if [[ "$debug_flag" == "debug" ]]; then
            printf '%s\n' "[DEBUG] Context selection: Config context '$context_name' not available" >&2
        fi
    fi

    # Try primary context (containai-docker) - the isolated daemon (all platforms)
    if _cai_sysbox_available_for_context "$primary_context"; then
        if [[ "$debug_flag" == "debug" ]]; then
            printf '%s\n' "[DEBUG] Context selection: Using primary context '$primary_context' with Sysbox" >&2
        fi
        if [[ -n "$config_context_name" ]]; then
            echo "[WARN] Config context '$config_context_name' not available, using '$primary_context'" >&2
        fi
        printf '%s' "$primary_context"
        return 0
    fi

    # Try fallback context (containai-secure) - legacy installs only
    if _cai_sysbox_available_for_context "$fallback_context"; then
        if [[ "$debug_flag" == "debug" ]]; then
            printf '%s\n' "[DEBUG] Context selection: Using fallback context '$fallback_context' with Sysbox" >&2
        fi
        if [[ -n "$config_context_name" ]]; then
            echo "[WARN] Config context '$config_context_name' not available, using '$fallback_context'" >&2
        fi
        printf '%s' "$fallback_context"
        return 0
    fi

    # No isolation available
    if [[ "$debug_flag" == "debug" ]]; then
        printf '%s\n' "[DEBUG] Context selection: No isolation available (tried: $primary_context, $fallback_context)" >&2
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
    local context_name="${1:-$_CAI_CONTAINAI_DOCKER_CONTEXT}"
    local skip_runtime_check="false"
    _CAI_SYSBOX_CONTEXT_ERROR=""
    if _cai_is_sysbox_container; then
        skip_runtime_check="true"
    fi

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

    # Nested Sysbox is unsupported; treat outer Sysbox isolation as sufficient
    # and skip runtime verification when already inside a Sysbox container.
    if [[ "$skip_runtime_check" == "true" ]]; then
        return 0
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

# Check if Sysbox is available on the containai-docker context
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
    local context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"

    # Determine expected socket based on platform
    # - WSL2: Uses dedicated socket at _CAI_CONTAINAI_DOCKER_SOCKET
    # - macOS: Uses Lima socket at _CAI_LIMA_SOCKET_PATH
    # - Native Linux: Uses default socket (until setup is migrated)
    local socket platform
    platform=$(_cai_detect_platform)
    case "$platform" in
        wsl)
            socket="${_CAI_CONTAINAI_DOCKER_SOCKET:-/var/run/containai-docker.sock}"
            ;;
        macos)
            socket="${_CAI_LIMA_SOCKET_PATH:-$HOME/.lima/containai-docker/sock/docker.sock}"
            ;;
        linux)
            # Native Linux currently uses default socket (will be migrated in fn-14-nm0.3)
            socket="/var/run/docker.sock"
            ;;
        *)
            socket="${_CAI_CONTAINAI_DOCKER_SOCKET:-/var/run/containai-docker.sock}"
            ;;
    esac

    # Check if socket exists
    if [[ ! -S "$socket" ]]; then
        _CAI_SYSBOX_ERROR="socket_not_found"
        return 1
    fi

    # Check if context exists
    if docker context inspect "$context_name" >/dev/null 2>&1; then
        _CAI_SYSBOX_CONTEXT_EXISTS="true"
    else
        _CAI_SYSBOX_ERROR="context_not_found"
        return 1
    fi

    # Check if we can connect to the daemon
    local info_output rc
    info_output=$(_cai_timeout 10 docker --context "$context_name" info 2>&1) && rc=0 || rc=$?

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

# Check isolated containai-docker bridge status (Linux/WSL2 only)
# Returns: 0=ok, 1=missing or misconfigured
# Sets: _CAI_DOCTOR_BRIDGE_ERROR to "ip_missing", "missing", or "addr_missing"
_cai_doctor_bridge_status() {
    _CAI_DOCTOR_BRIDGE_ERROR=""

    if ! command -v ip >/dev/null 2>&1; then
        _CAI_DOCTOR_BRIDGE_ERROR="ip_missing"
        return 1
    fi

    if ! ip link show "$_CAI_CONTAINAI_DOCKER_BRIDGE" >/dev/null 2>&1; then
        _CAI_DOCTOR_BRIDGE_ERROR="missing"
        return 1
    fi

    if ip -4 addr show dev "$_CAI_CONTAINAI_DOCKER_BRIDGE" 2>/dev/null \
        | grep -q "$_CAI_CONTAINAI_DOCKER_BRIDGE_ADDR"; then
        return 0
    fi

    _CAI_DOCTOR_BRIDGE_ERROR="addr_missing"
    return 1
}

# Repair isolated containai-docker bridge (Linux/WSL2 only)
# Returns: 0=success, 1=failure, 2=ip command missing
_cai_doctor_fix_bridge() {
    if ! command -v ip >/dev/null 2>&1; then
        return 2
    fi

    if ! ip link show "$_CAI_CONTAINAI_DOCKER_BRIDGE" >/dev/null 2>&1; then
        if ! sudo ip link add name "$_CAI_CONTAINAI_DOCKER_BRIDGE" type bridge; then
            return 1
        fi
    fi

    if ! ip -4 addr show dev "$_CAI_CONTAINAI_DOCKER_BRIDGE" 2>/dev/null \
        | grep -q "$_CAI_CONTAINAI_DOCKER_BRIDGE_ADDR"; then
        if ! sudo ip addr add "$_CAI_CONTAINAI_DOCKER_BRIDGE_ADDR" dev "$_CAI_CONTAINAI_DOCKER_BRIDGE"; then
            return 1
        fi
    fi

    if ! sudo ip link set "$_CAI_CONTAINAI_DOCKER_BRIDGE" up; then
        return 1
    fi

    return 0
}

# Run doctor command with text output
# Args: build_templates ("true" to run heavy template build checks)
# Returns: 0 if Sysbox isolation is available
#          1 if no isolation available (cannot proceed)
_cai_doctor() {
    local build_templates="${1:-false}"
    local sysbox_ok="false"
    local docker_cli_ok="false"
    local docker_daemon_ok="false"
    local platform
    local seccomp_status=""
    local kernel_ok="true" # Default to true (macOS doesn't need kernel check)
    local kernel_version=""
    local in_container="false"
    local in_sysbox_container="false"

    platform=$(_cai_detect_platform)
    if _cai_is_container; then
        in_container="true"
    fi
    if _cai_is_sysbox_container; then
        in_sysbox_container="true"
    fi

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

    # Resolve context: use _cai_select_context which tries config override,
    # then containai-docker, then legacy fallback for old installs
    local sysbox_context_name=""
    local config_context
    if [[ "$in_sysbox_container" == "true" ]]; then
        sysbox_ok="true"
        printf '  %-44s %s\n' "Outer Sysbox container:" "[OK] Detected"
    else
        config_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || config_context=""
        sysbox_context_name=$(_cai_select_context "$config_context" 2>/dev/null) || sysbox_context_name=""

        # Check Sysbox availability with resolved context name
        if [[ -n "$sysbox_context_name" ]] && _cai_sysbox_available_for_context "$sysbox_context_name"; then
            sysbox_ok="true"
            printf '  %-44s %s\n' "Sysbox available:" "[OK]"
            printf '  %-44s %s\n' "Runtime: sysbox-runc" "[OK]"
            printf '  %-44s %s\n' "Context '$sysbox_context_name':" "[OK] Configured"

            # Show sysbox version information (only on Linux/WSL2, not macOS)
            if [[ "$platform" != "macos" ]]; then
                # Always use binary version (authoritative) - dpkg version is unreliable
                local installed_sysbox_version=""
                installed_sysbox_version=$(_cai_sysbox_installed_binary_version 2>/dev/null) || \
                    installed_sysbox_version=$(_cai_sysbox_installed_version 2>/dev/null) || \
                    installed_sysbox_version=""

                if [[ -n "$installed_sysbox_version" ]]; then
                    printf '  %-44s %s\n' "Installed version: $installed_sysbox_version" "[OK]"
                fi

                # Get bundled version and check for updates
                local arch bundled_version sysbox_update_needed="false"
                arch=$(uname -m)
                case "$arch" in
                    x86_64)  arch="amd64" ;;
                    aarch64) arch="arm64" ;;
                esac

                bundled_version=$(_cai_sysbox_bundled_version "$arch" 2>/dev/null) || bundled_version=""

                if [[ -n "$bundled_version" ]]; then
                    if _cai_sysbox_needs_update "$arch" 2>/dev/null; then
                        sysbox_update_needed="true"
                        printf '  %-44s %s\n' "Bundled version: $bundled_version" "[WARN] Update available"
                        printf '  %-44s %s\n' "" "(Run 'cai update' to upgrade)"
                    else
                        printf '  %-44s %s\n' "Bundled version: $bundled_version" "[OK] Up to date"
                    fi
                fi
            fi
        else
            printf '  %-44s %s\n' "Sysbox available:" "[ERROR] Not configured"
            local sysbox_error="${_CAI_SYSBOX_CONTEXT_ERROR:-${_CAI_SYSBOX_ERROR:-}}"
            # Default context name for error messages if none was selected
            local display_context="${sysbox_context_name:-containai-docker}"
            case "$sysbox_error" in
                socket_not_found)
                    if [[ "$platform" == "macos" ]]; then
                        printf '  %-44s %s\n' "" "(Lima VM not running or not provisioned)"
                        printf '  %-44s %s\n' "" "(Run 'cai setup' or 'limactl start $_CAI_LIMA_VM_NAME')"
                    else
                        printf '  %-44s %s\n' "" "(Run 'cai setup' to install Sysbox)"
                    fi
                    ;;
                context_not_found|"")
                    printf '  %-44s %s\n' "" "(Run 'cai setup' to configure '$display_context' context)"
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
                        printf '  %-44s %s\n' "" "(Try: limactl shell $_CAI_LIMA_VM_NAME sudo systemctl start docker)"
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

        # Show sysbox version from inside Lima VM
        # First check VM status to provide better error messages
        local lima_vm_status=""
        if command -v limactl >/dev/null 2>&1 && _cai_lima_vm_exists "$_CAI_LIMA_VM_NAME" 2>/dev/null; then
            lima_vm_status=$(_cai_lima_vm_status "$_CAI_LIMA_VM_NAME" 2>/dev/null) || lima_vm_status=""
        fi

        local lima_sysbox_version=""
        lima_sysbox_version=$(_cai_lima_sysbox_version 2>/dev/null) || lima_sysbox_version=""
        if [[ -n "$lima_sysbox_version" ]]; then
            # Extract just the version part (e.g., "0.6.4+containai.20250124" from "sysbox-runc version 0.6.4+containai.20250124")
            local lima_sysbox_display
            lima_sysbox_display=$(printf '%s' "$lima_sysbox_version" | sed 's/sysbox-runc[[:space:]]*version[[:space:]]*//')
            printf '  %-44s %s\n' "Sysbox version (in VM): $lima_sysbox_display" "[OK]"

            # Check for available updates using detected VM architecture
            if _cai_lima_sysbox_needs_update 2>/dev/null; then
                local lima_vm_arch="${_CAI_LIMA_VM_ARCH:-amd64}"
                local lima_bundled_version
                lima_bundled_version=$(_cai_sysbox_bundled_version "$lima_vm_arch" 2>/dev/null) || lima_bundled_version=""
                if [[ -n "$lima_bundled_version" ]]; then
                    printf '  %-44s %s\n' "Bundled version: $lima_bundled_version" "[WARN] Update available"
                    printf '  %-44s %s\n' "" "(Run 'cai update' to upgrade)"
                fi
            fi
        else
            # Differentiate between VM not running vs sysbox not installed
            if [[ -z "$lima_vm_status" ]]; then
                printf '  %-44s %s\n' "Sysbox version (in VM):" "[SKIP] VM not found"
            elif [[ "$lima_vm_status" != "Running" ]]; then
                printf '  %-44s %s\n' "Sysbox version (in VM):" "[SKIP] VM not running ($lima_vm_status)"
            else
                printf '  %-44s %s\n' "Sysbox version (in VM):" "[WARN] sysbox not installed/queryable"
            fi
        fi

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
    local docker_context_for_checks

    # Resolve context: use _cai_select_context which tries config override,
    # then containai-docker, then legacy fallback for old installs.
    # Inside a container, always use default context.
    if [[ "$in_container" == "true" ]]; then
        docker_context_for_checks="default"
    else
        local config_context
        config_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || config_context=""
        docker_context_for_checks=$(_cai_select_context "$config_context" 2>/dev/null) || docker_context_for_checks=""
        # Default for error reporting if no context available
        if [[ -z "$docker_context_for_checks" ]]; then
            docker_context_for_checks="$_CAI_CONTAINAI_DOCKER_CONTEXT"
        fi
    fi

    printf '%s\n' "ContainAI Docker"

    if [[ "$in_container" == "true" ]]; then
        local display_socket="/var/run/docker.sock"
        local info_output info_rc
        info_output=$(_cai_timeout 5 env DOCKER_CONTEXT= DOCKER_HOST= docker info 2>&1) && info_rc=0 || info_rc=$?
        if [[ $info_rc -eq 0 ]]; then
            containai_docker_ok="true"
            printf '  %-44s %s\n' "Context 'default':" "[OK]"
            printf '  %-44s %s\n' "Socket: $display_socket" "[OK]"
            local actual_default
            actual_default=$(env DOCKER_CONTEXT= DOCKER_HOST= docker info --format '{{.DefaultRuntime}}' 2>/dev/null || true)
            if [[ -z "$actual_default" ]]; then
                actual_default="unknown"
            fi

            if [[ "$in_sysbox_container" == "true" ]]; then
                printf '  %-44s %s\n' "Default runtime: $actual_default" "[OK]"
            else
                local runtimes
                runtimes=$(env DOCKER_CONTEXT= DOCKER_HOST= docker info --format '{{json .Runtimes}}' 2>/dev/null || true)
                if printf '%s' "$runtimes" | grep -q "sysbox-runc"; then
                    printf '  %-44s %s\n' "Runtime: sysbox-runc" "[OK] Available"
                else
                    printf '  %-44s %s\n' "Runtime: sysbox-runc" "[ERROR] Not found"
                fi

                if [[ "$actual_default" == "sysbox-runc" ]]; then
                    containai_docker_sysbox_default="true"
                    printf '  %-44s %s\n' "Default runtime: sysbox-runc" "[OK]"
                else
                    printf '  %-44s %s\n' "Default runtime: ${actual_default:-unknown}" "[WARN]"
                    printf '  %-44s %s\n' "" "(Expected sysbox-runc as default)"
                fi
            fi
        else
            printf '  %-44s %s\n' "ContainAI Docker:" "[ERROR] Not accessible"
            printf '  %-44s %s\n' "" "(Default Docker daemon not reachable inside container)"
        fi
    else
        # Check containai docker availability
        # Socket path display is platform-dependent
        local display_socket
        if _cai_is_macos; then
            display_socket="$HOME/.lima/$_CAI_CONTAINAI_DOCKER_CONTEXT/sock/docker.sock"
        else
            display_socket="$_CAI_CONTAINAI_DOCKER_SOCKET"
        fi

        # On Linux/WSL2, check systemd service status first
        if ! _cai_is_macos; then
            if _cai_containai_docker_service_active; then
                printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[OK] active"
            else
                local service_state="${_CAI_CONTAINAI_SERVICE_STATE:-unknown}"
                case "$service_state" in
                    no_systemd)
                        printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[SKIP] systemd not available"
                        ;;
                    systemd_not_running)
                        # Check if unit file exists even if systemd isn't running
                        if _cai_containai_docker_service_exists; then
                            printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[WARN] installed but systemd not running"
                        else
                            printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[SKIP] systemd not running"
                        fi
                        ;;
                    inactive)
                        printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[ERROR] inactive"
                        printf '  %-44s %s\n' "" "(Start with: sudo systemctl start containai-docker)"
                        ;;
                    failed)
                        printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[ERROR] failed"
                        printf '  %-44s %s\n' "" "(Check logs: journalctl -u containai-docker)"
                        ;;
                    activating)
                        printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[WARN] activating..."
                        ;;
                    deactivating)
                        printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[WARN] deactivating..."
                        ;;
                    unknown)
                        # State is unknown - check if service exists
                        if _cai_containai_docker_service_exists; then
                            printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[ERROR] unknown state"
                        else
                            printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[NOT INSTALLED]"
                            printf '  %-44s %s\n' "" "(Run 'cai setup' to install)"
                        fi
                        ;;
                    *)
                        # Any other state (reloading, maintenance, etc.)
                        printf '  %-44s %s\n' "Service '$_CAI_CONTAINAI_DOCKER_SERVICE':" "[WARN] $service_state"
                        ;;
                esac
            fi

            # Check isolated bridge (cai0) on Linux/WSL2 hosts
            if [[ "$in_container" == "false" ]]; then
                if _cai_doctor_bridge_status; then
                    printf '  %-44s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE':" "[OK]"
                else
                    case "${_CAI_DOCTOR_BRIDGE_ERROR:-unknown}" in
                        ip_missing)
                            printf '  %-44s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE':" "[WARN] ip tool missing"
                            printf '  %-44s %s\n' "" "(Install iproute2 to check/repair bridge)"
                            ;;
                        missing)
                            printf '  %-44s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE':" "[ERROR] missing"
                            printf '  %-44s %s\n' "" "(Run 'cai doctor fix' to create bridge)"
                            ;;
                        addr_missing)
                            printf '  %-44s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE':" "[WARN] address missing"
                            printf '  %-44s %s\n' "" "(Run 'cai doctor fix' to repair bridge)"
                            ;;
                        *)
                            printf '  %-44s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE':" "[WARN] unknown"
                            ;;
                    esac
                fi
            fi
        fi

        if _cai_containai_docker_available; then
            containai_docker_ok="true"
            printf '  %-44s %s\n' "Context '$_CAI_CONTAINAI_DOCKER_CONTEXT':" "[OK]"
            printf '  %-44s %s\n' "Socket: $display_socket" "[OK]"

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
                    printf '  %-44s %s\n' "" "(Context '$_CAI_CONTAINAI_DOCKER_CONTEXT' not configured)"
                    printf '  %-44s %s\n' "" "(Run 'cai setup' to create isolated Docker daemon)"
                    ;;
                wrong_endpoint)
                    printf '  %-44s %s\n' "" "(Context '$_CAI_CONTAINAI_DOCKER_CONTEXT' points to wrong socket)"
                    printf '  %-44s %s\n' "" "(Expected: unix://$display_socket)"
                    printf '  %-44s %s\n' "" "(Run 'cai setup' to reconfigure)"
                    ;;
                socket_not_found)
                    printf '  %-44s %s\n' "" "(Socket $display_socket not found)"
                    if _cai_is_macos; then
                        printf '  %-44s %s\n' "" "(Run 'cai setup' or start Lima VM: limactl start $_CAI_LIMA_VM_NAME)"
                    else
                        printf '  %-44s %s\n' "" "(Run 'cai setup' or start service: sudo systemctl start containai-docker)"
                    fi
                    ;;
                connection_refused | daemon_unavailable)
                    if _cai_is_macos; then
                        printf '  %-44s %s\n' "" "(Lima VM '$_CAI_LIMA_VM_NAME' not running)"
                        printf '  %-44s %s\n' "" "(Try: limactl start $_CAI_LIMA_VM_NAME)"
                    else
                        printf '  %-44s %s\n' "" "(containai-docker service not running)"
                        printf '  %-44s %s\n' "" "(Try: sudo systemctl start containai-docker)"
                    fi
                    ;;
                permission_denied)
                    printf '  %-44s %s\n' "" "(Permission denied accessing Docker socket)"
                    if ! _cai_is_macos; then
                        printf '  %-44s %s\n' "" "(Add user to docker group: sudo usermod -aG docker \$USER)"
                    fi
                    ;;
                timeout)
                    printf '  %-44s %s\n' "" "(Docker command timed out)"
                    if _cai_is_macos; then
                        printf '  %-44s %s\n' "" "(Check Lima VM status: limactl list)"
                    else
                        printf '  %-44s %s\n' "" "(Check if daemon is responsive: sudo systemctl status containai-docker)"
                    fi
                    ;;
                no_timeout)
                    printf '  %-44s %s\n' "" "(No timeout command available)"
                    printf '  %-44s %s\n' "" "(Install coreutils: apt install coreutils)"
                    ;;
                *)
                    printf '  %-44s %s\n' "" "(Run 'cai setup' to install isolated Docker daemon)"
                    ;;
            esac
        fi
    fi

    printf '\n'

    # === Network Security Section ===
    # Only check on Linux/WSL2 hosts (not macOS, not inside containers where outer rules apply)
    local network_security_ok="true"
    local network_status=""
    if [[ "$platform" == "linux" ]] || [[ "$platform" == "wsl" ]]; then
        if [[ "$in_container" == "false" ]]; then
            printf '%s\n' "Network Security"

            network_status=$(_cai_network_doctor_status)
            case "$network_status" in
                ok)
                    printf '  %-44s %s\n' "iptables rules:" "[OK]"
                    printf '  %-44s %s\n' "" "${_CAI_NETWORK_DOCTOR_DETAIL:-}"
                    ;;
                skipped)
                    printf '  %-44s %s\n' "iptables rules:" "[SKIP]"
                    printf '  %-44s %s\n' "" "${_CAI_NETWORK_DOCTOR_DETAIL:-}"
                    ;;
                missing)
                    network_security_ok="false"
                    printf '  %-44s %s\n' "iptables rules:" "[ERROR] Not configured"
                    printf '  %-44s %s\n' "" "${_CAI_NETWORK_DOCTOR_DETAIL:-}"
                    ;;
                partial)
                    network_security_ok="false"
                    printf '  %-44s %s\n' "iptables rules:" "[WARN] Incomplete"
                    printf '  %-44s %s\n' "" "${_CAI_NETWORK_DOCTOR_DETAIL:-}"
                    ;;
                error)
                    network_security_ok="false"
                    printf '  %-44s %s\n' "iptables rules:" "[ERROR]"
                    printf '  %-44s %s\n' "" "${_CAI_NETWORK_DOCTOR_DETAIL:-}"
                    ;;
            esac

            printf '\n'
        fi
    fi

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
        running_containers=$(_cai_timeout 5 docker --context "$docker_context_for_checks" ps --filter "label=containai.workspace" --format '{{.Names}}' 2>/dev/null | head -1) || running_containers=""
        if [[ -n "$running_containers" ]]; then
            local test_container="$running_containers"
            local ssh_port
            ssh_port=$(_cai_timeout 5 docker --context "$docker_context_for_checks" inspect "$test_container" --format '{{index .Config.Labels "containai.ssh-port"}}' 2>/dev/null) || ssh_port=""
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
    if [[ "$ssh_version_ok" == "true" ]] && [[ "$ssh_key_ok" == "true" ]] \
        && [[ "$ssh_config_dir_ok" == "true" ]] && [[ "$ssh_include_ok" == "true" ]]; then
        ssh_all_ok="true"
    fi

    printf '\n'

    # === Templates Section ===
    local template_all_ok="true"
    if ! _cai_doctor_template_checks "$build_templates" "$docker_context_for_checks"; then
        template_all_ok="false"
    fi

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
    if [[ "$in_sysbox_container" == "true" ]]; then
        if [[ "$containai_docker_ok" == "true" ]]; then
            printf '  %-44s %s\n' "ContainAI Docker:" "[OK] Nested Sysbox mode"
        else
            printf '  %-44s %s\n' "ContainAI Docker:" "[ERROR] Not accessible"
        fi
    elif [[ "$containai_docker_ok" == "true" ]] && [[ "$containai_docker_sysbox_default" == "true" ]]; then
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

    # Network Security summary (Linux/WSL2 hosts only)
    if [[ "$platform" == "linux" ]] || [[ "$platform" == "wsl" ]]; then
        if [[ "$in_container" == "false" ]]; then
            if [[ "$network_security_ok" == "true" ]]; then
                printf '  %-44s %s\n' "Network Security:" "[OK] Rules configured"
            else
                printf '  %-44s %s\n' "Network Security:" "[ERROR] Rules missing"
                printf '  %-44s %s\n' "Recommended:" "Run 'cai setup' to configure network rules"
            fi
        fi
    fi

    # Template summary
    if [[ "$template_all_ok" == "true" ]]; then
        printf '  %-44s %s\n' "Templates:" "[OK] Ready"
    else
        printf '  %-44s %s\n' "Templates:" "[ERROR] Issues found"
        printf '  %-44s %s\n' "Recommended:" "Run 'cai doctor fix template' to recover"
    fi

    # Exit code: 0 if isolation ready AND SSH configured AND network OK AND templates OK, 1 if not
    if [[ "$isolation_ready" == "true" ]] && [[ "$ssh_all_ok" == "true" ]] \
        && [[ "$network_security_ok" == "true" ]] && [[ "$template_all_ok" == "true" ]]; then
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
            if ssh-keygen -y -f "$ssh_key_path" >"$ssh_pubkey_path" 2>/dev/null; then
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
        if printf '%s\n' "$include_line" >"$ssh_config" && chmod 600 "$ssh_config"; then
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
                } >"$temp_file" && cp "$temp_file" "$ssh_config" && rm -f "$temp_file"; then
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
        # Check if any Docker context is reachable (default, containai-docker, or legacy fallback)
        local docker_reachable=false
        if _cai_timeout 5 docker info >/dev/null 2>&1; then
            docker_reachable=true
        elif docker context inspect "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1 \
            && _cai_timeout 5 docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" info >/dev/null 2>&1; then
            docker_reachable=true
        elif docker context inspect "${_CAI_LEGACY_CONTEXT:-containai-secure}" >/dev/null 2>&1 \
            && _cai_timeout 5 docker --context "${_CAI_LEGACY_CONTEXT:-containai-secure}" info >/dev/null 2>&1; then
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

    # === ContainAI Docker Bridge Fix ===
    printf '%s\n' "ContainAI Docker"
    if [[ "$platform" == "linux" ]] || [[ "$platform" == "wsl" ]]; then
        if _cai_is_container; then
            printf '  %-50s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE'" "[SKIP] running in container"
            ((skip_count++))
        elif _cai_doctor_bridge_status; then
            printf '  %-50s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE'" "[OK]"
        else
            case "${_CAI_DOCTOR_BRIDGE_ERROR:-unknown}" in
                ip_missing)
                    printf '  %-50s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE'" "[SKIP] ip tool missing"
                    ((skip_count++))
                    ;;
                missing|addr_missing)
                    printf '  %-50s' "Repairing bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE'"
                    if _cai_doctor_fix_bridge; then
                        printf '%s\n' "[FIXED]"
                        ((fixed_count++))
                    else
                        printf '%s\n' "[FAIL]"
                        ((fail_count++))
                    fi
                    ;;
                *)
                    printf '  %-50s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE'" "[SKIP] unknown status"
                    ((skip_count++))
                    ;;
            esac
        fi
    else
        printf '  %-50s %s\n' "Bridge '$_CAI_CONTAINAI_DOCKER_BRIDGE'" "[SKIP] not supported"
        ((skip_count++))
    fi

    printf '\n'

    # === Network Security Rules Fix ===
    printf '%s\n' "Network Security"
    if [[ "$platform" == "linux" ]] || [[ "$platform" == "wsl" ]]; then
        if _cai_is_container; then
            printf '  %-50s %s\n' "iptables rules" "[SKIP] running in container"
            ((skip_count++))
        else
            # Check if iptables is available first
            if ! _cai_iptables_available; then
                printf '  %-50s %s\n' "iptables rules" "[SKIP] iptables not installed"
                ((skip_count++))
            elif ! _cai_iptables_can_run; then
                printf '  %-50s %s\n' "iptables rules" "[SKIP] insufficient permissions"
                ((skip_count++))
            else
                local network_status
                network_status=$(_cai_network_doctor_status)
                case "$network_status" in
                    ok)
                        printf '  %-50s %s\n' "iptables rules" "[OK]"
                        ;;
                    skipped)
                        printf '  %-50s %s\n' "iptables rules" "[SKIP] ${_CAI_NETWORK_DOCTOR_DETAIL:-}"
                        ((skip_count++))
                        ;;
                    missing | partial | error)
                        printf '  %-50s' "Applying iptables rules"
                        if _cai_apply_network_rules "false" >/dev/null 2>&1; then
                            printf '%s\n' "[FIXED]"
                            ((fixed_count++))
                        else
                            printf '%s\n' "[FAIL]"
                            ((fail_count++))
                        fi
                        ;;
                esac
            fi
        fi
    else
        printf '  %-50s %s\n' "iptables rules" "[SKIP] not supported on $platform"
        ((skip_count++))
    fi

    printf '\n'

    # === Unfixable Issues (informational) ===
    printf '%s\n' "Cannot Auto-Fix"

    # Sysbox availability
    local sysbox_context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"
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
            connection_refused | daemon_unavailable)
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
# Doctor Fix Subcommand Hierarchy
# ==============================================================================

# Dispatch for 'cai doctor fix' subcommand
# Routes to appropriate fix target based on arguments
# Arguments: $@ = remaining arguments after 'fix'
# Returns: 0=success, 1=error
_cai_doctor_fix_dispatch() {
    local target="${1:-}"

    # Resolve effective Docker context for operations
    # Inside containers, use default context (self-contained daemon)
    # Note: We let warnings from context resolution surface for debugging,
    # since doctor fix is meant to remediate setup issues
    local effective_context=""
    local config_context
    if _cai_is_container; then
        effective_context="default"
    else
        config_context=$(_containai_resolve_secure_engine_context) || config_context=""
        effective_context=$(_cai_select_context "$config_context") || effective_context="$_CAI_CONTAINAI_DOCKER_CONTEXT"
    fi

    case "$target" in
        "")
            # 'cai doctor fix' with no target - show available targets
            _cai_doctor_fix_show_targets "$effective_context"
            return 0
            ;;
        --all)
            # 'cai doctor fix --all' - run all fixes
            _cai_doctor_fix_all "$effective_context"
            return $?
            ;;
        volume)
            shift
            _cai_doctor_fix_volume "$effective_context" "$@"
            return $?
            ;;
        container)
            shift
            _cai_doctor_fix_container "$effective_context" "$@"
            return $?
            ;;
        template)
            shift
            _cai_doctor_fix_template "$@"
            return $?
            ;;
        --help | -h)
            _containai_doctor_help
            return 0
            ;;
        *)
            echo "[ERROR] Unknown fix target: $target" >&2
            echo "Valid targets: volume, container, template, --all" >&2
            echo "Use 'cai doctor --help' for usage" >&2
            return 1
            ;;
    esac
}

# Show available fix targets and what can be fixed
# Arguments: $1 = effective Docker context
_cai_doctor_fix_show_targets() {
    local ctx="$1"
    local platform
    platform=$(_cai_detect_platform)

    printf '%s\n' "ContainAI Doctor Fix"
    printf '%s\n' "===================="
    printf '\n'
    printf '%s\n' "Available fix targets:"
    printf '\n'

    # List containers
    printf '%s\n' "  Containers:"
    local containers=""
    if [[ -n "$ctx" ]] && command -v docker >/dev/null 2>&1; then
        containers=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            ps -a --filter "label=containai.managed=true" --format '{{.Names}}' 2>/dev/null) || containers=""
    fi
    if [[ -n "$containers" ]]; then
        local c
        while IFS= read -r c; do
            [[ -z "$c" ]] && continue
            printf '    - %s\n' "$c"
        done <<< "$containers"
    else
        printf '    (none found)\n'
    fi
    printf '\n'

    # List volumes (derived from containers)
    printf '%s\n' "  Volumes:"
    if [[ "$platform" == "macos" ]]; then
        printf '    (volume fix not available on macOS - volumes are inside Lima VM)\n'
    else
        local volumes=""
        if [[ -n "$containers" ]]; then
            local c
            while IFS= read -r c; do
                [[ -z "$c" ]] && continue
                local vols
                vols=$(_cai_doctor_get_container_volumes_for_context "$ctx" "$c" 2>/dev/null) || vols=""
                if [[ -n "$vols" ]]; then
                    volumes="${volumes}${vols}"$'\n'
                fi
            done <<< "$containers"
        fi
        # Deduplicate volumes
        if [[ -n "$volumes" ]]; then
            local unique_volumes
            unique_volumes=$(printf '%s' "$volumes" | sort -u | grep -v '^$')
            local v
            while IFS= read -r v; do
                [[ -z "$v" ]] && continue
                printf '    - %s\n' "$v"
            done <<< "$unique_volumes"
        else
            printf '    (none found)\n'
        fi
    fi
    printf '\n'

    printf '%s\n' "Commands:"
    printf '  cai doctor fix --all              Fix everything\n'
    printf '  cai doctor fix container --all    Fix all containers (SSH refresh)\n'
    printf '  cai doctor fix container <name>   Fix specific container\n'
    if [[ "$platform" != "macos" ]]; then
        printf '  cai doctor fix volume --all       Fix all volumes (ownership repair)\n'
        printf '  cai doctor fix volume <name>      Fix specific volume\n'
    fi
    printf '\n'

    return 0
}

# Fix all targets (containers and volumes)
# Arguments: $1 = effective Docker context
_cai_doctor_fix_all() {
    local ctx="$1"
    local platform
    local had_error="false"
    platform=$(_cai_detect_platform)

    printf '%s\n' "ContainAI Doctor Fix (All)"
    printf '%s\n' "=========================="
    printf '\n'

    # Run base doctor fix first (SSH keys, config, etc.)
    printf '%s\n' "=== Base Configuration ==="
    printf '\n'
    if ! _cai_doctor_fix; then
        had_error="true"
    fi
    printf '\n'

    # Fix all containers
    printf '%s\n' "=== Containers ==="
    printf '\n'
    if ! _cai_doctor_fix_container "$ctx" --all; then
        had_error="true"
    fi
    printf '\n'

    # Fix all volumes (Linux/WSL2 only)
    if [[ "$platform" != "macos" ]]; then
        printf '%s\n' "=== Volumes ==="
        printf '\n'
        if ! _cai_doctor_fix_volume "$ctx" --all; then
            had_error="true"
        fi
        printf '\n'
    fi

    # Fix all templates
    printf '%s\n' "=== Templates ==="
    printf '\n'
    if ! _cai_doctor_fix_template --all; then
        had_error="true"
    fi

    if [[ "$had_error" == "true" ]]; then
        return 1
    fi
    return 0
}

# Fix volume ownership
# Arguments: $1 = effective Docker context
#            $2... = --all or volume name
_cai_doctor_fix_volume() {
    local ctx="$1"
    shift
    local target="${1:-}"
    local platform
    platform=$(_cai_detect_platform)

    # Platform check - volume fix is Linux/WSL2 only
    if [[ "$platform" == "macos" ]]; then
        _cai_info "Volume repair is not supported on macOS"
        _cai_info "Volumes are inside the Lima VM and cannot be accessed directly"
        return 0
    fi

    # Check nested mode - also not supported
    if _cai_is_container; then
        _cai_info "Volume repair is not supported in nested mode"
        _cai_info "Use volume repair from the host system"
        return 0
    fi

    case "$target" in
        "")
            # List volumes with status
            _cai_doctor_fix_volume_list "$ctx"
            return 0
            ;;
        --all)
            # Fix all volumes (pass context for context-aware repair)
            _cai_doctor_repair "$ctx" "" "false"
            return $?
            ;;
        --help | -h)
            _containai_doctor_help
            return 0
            ;;
        -*)
            # Docker volume names must start with [a-zA-Z0-9], not dash
            echo "[ERROR] Invalid volume name: $target" >&2
            echo "Volume names must start with a letter or number" >&2
            return 1
            ;;
        *)
            # Fix specific volume
            _cai_doctor_fix_volume_single "$ctx" "$target"
            return $?
            ;;
    esac
}

# List volumes with their status
# Arguments: $1 = effective Docker context
_cai_doctor_fix_volume_list() {
    local ctx="$1"

    printf '%s\n' "ContainAI Doctor Fix (Volume List)"
    printf '%s\n' "==================================="
    printf '\n'
    printf '%s\n' "Note: Volume fix is only available on Linux/WSL2 hosts."
    printf '%s\n' "Not supported on macOS (volumes inside Lima VM) or nested mode."
    printf '\n'

    # Get all managed containers
    local containers=""
    if [[ -n "$ctx" ]] && command -v docker >/dev/null 2>&1; then
        containers=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            ps -a --filter "label=containai.managed=true" --format '{{.Names}}' 2>/dev/null) || containers=""
    fi

    if [[ -z "$containers" ]]; then
        _cai_info "No ContainAI-managed containers found"
        return 0
    fi

    printf '%s\n' "Volumes from managed containers:"
    printf '\n'

    local volumes_root="$_CAI_CONTAINAI_DOCKER_DATA/volumes"

    # Collect all volumes from containers
    local c
    while IFS= read -r c; do
        [[ -z "$c" ]] && continue
        local vols
        vols=$(_cai_doctor_get_container_volumes_for_context "$ctx" "$c" 2>/dev/null) || vols=""
        if [[ -n "$vols" ]]; then
            local v
            while IFS= read -r v; do
                [[ -z "$v" ]] && continue
                local volume_path="$volumes_root/$v/_data"
                local status="[OK]"
                if [[ -d "$volume_path" ]]; then
                    local corrupted_count
                    corrupted_count=$(_cai_doctor_check_volume_ownership "$volume_path" 2>/dev/null) || corrupted_count=""
                    if [[ -n "$corrupted_count" ]] && [[ "$corrupted_count" != "0" ]]; then
                        status="[CORRUPT] $corrupted_count files with nobody:nogroup"
                    fi
                else
                    status="[SKIP] Path not accessible"
                fi
                printf '  %-30s %s (container: %s)\n' "$v" "$status" "$c"
            done <<< "$vols"
        fi
    done <<< "$containers"

    printf '\n'
    printf '%s\n' "Commands:"
    printf '  cai doctor fix volume --all       Fix all volumes\n'
    printf '  cai doctor fix volume <name>      Fix specific volume\n'

    return 0
}

# Fix a single volume
# Arguments: $1 = effective Docker context
#            $2 = volume name
_cai_doctor_fix_volume_single() {
    local ctx="$1"
    local volume_name="$2"

    printf '%s\n' "ContainAI Doctor Fix (Volume: $volume_name)"
    printf '%s\n' "============================================"
    printf '\n'

    # Find which container owns this volume
    local containers=""
    if [[ -n "$ctx" ]] && command -v docker >/dev/null 2>&1; then
        containers=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            ps -a --filter "label=containai.managed=true" --format '{{.Names}}' 2>/dev/null) || containers=""
    fi

    local owner_container=""
    local c
    while IFS= read -r c; do
        [[ -z "$c" ]] && continue
        local vols
        vols=$(_cai_doctor_get_container_volumes_for_context "$ctx" "$c" 2>/dev/null) || vols=""
        # Use -Fqx for fixed string matching (volume names may contain '.' which is regex wildcard)
        if printf '%s' "$vols" | grep -Fqx "$volume_name"; then
            owner_container="$c"
            break
        fi
    done <<< "$containers"

    if [[ -z "$owner_container" ]]; then
        _cai_error "Volume '$volume_name' not found in any managed container"
        _cai_info "Use 'cai doctor fix volume' to list available volumes"
        return 1
    fi

    # Get target UID/GID from container (use context-aware version)
    local target_ownership
    if target_ownership=$(_cai_doctor_detect_uid_for_context "$ctx" "$owner_container" 2>/dev/null); then
        printf '  %-50s %s\n' "Target ownership:" "$target_ownership (from container $owner_container)"
    else
        target_ownership="1000:1000"
        printf '  %-50s %s\n' "Target ownership:" "$target_ownership (default - could not detect)"
    fi

    # Check rootfs for corruption (context-aware)
    if _cai_doctor_check_rootfs_tainted_for_context "$ctx" "$owner_container"; then
        printf '  %-50s %s\n' "Rootfs:" "[WARN] Tainted - consider recreating container"
    fi

    # Repair the volume
    _cai_doctor_repair_volume "$volume_name" "$target_ownership" "false"
    return $?
}

# Fix container SSH configuration
# Arguments: $1 = effective Docker context
#            $2... = --all or container name
_cai_doctor_fix_container() {
    local ctx="$1"
    shift
    local target="${1:-}"

    case "$target" in
        "")
            # List containers with status
            _cai_doctor_fix_container_list "$ctx"
            return 0
            ;;
        --all)
            # Fix all containers
            _cai_doctor_fix_container_all "$ctx"
            return $?
            ;;
        --help | -h)
            _containai_doctor_help
            return 0
            ;;
        *)
            # Fix specific container (use -- to prevent option injection)
            _cai_doctor_fix_container_single "$ctx" "$target"
            return $?
            ;;
    esac
}

# List containers with their SSH status
# Arguments: $1 = effective Docker context
_cai_doctor_fix_container_list() {
    local ctx="$1"

    printf '%s\n' "ContainAI Doctor Fix (Container List)"
    printf '%s\n' "======================================"
    printf '\n'

    # Get all managed containers
    local containers=""
    if [[ -n "$ctx" ]] && command -v docker >/dev/null 2>&1; then
        containers=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            ps -a --filter "label=containai.managed=true" --format '{{.Names}}\t{{.Status}}' 2>/dev/null) || containers=""
    fi

    if [[ -z "$containers" ]]; then
        _cai_info "No ContainAI-managed containers found"
        return 0
    fi

    printf '%s\n' "Managed containers:"
    printf '\n'

    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name status
        name=$(printf '%s' "$line" | cut -f1)
        status=$(printf '%s' "$line" | cut -f2-)

        # Check SSH config
        local ssh_status="[OK]"
        local config_file="$_CAI_SSH_CONFIG_DIR/${name}.conf"
        if [[ ! -f "$config_file" ]]; then
            ssh_status="[MISSING] SSH config"
        fi

        printf '  %-30s %-20s %s\n' "$name" "($status)" "$ssh_status"
    done <<< "$containers"

    printf '\n'
    printf '%s\n' "Commands:"
    printf '  cai doctor fix container --all    Fix all containers\n'
    printf '  cai doctor fix container <name>   Fix specific container\n'

    return 0
}

# Fix all containers (SSH refresh)
# Arguments: $1 = effective Docker context
_cai_doctor_fix_container_all() {
    local ctx="$1"
    local fixed_count=0
    local skip_count=0
    local fail_count=0

    printf '%s\n' "ContainAI Doctor Fix (All Containers)"
    printf '%s\n' "======================================"
    printf '\n'

    # Get all managed containers (names only, then inspect for state)
    local container_names=""
    if [[ -n "$ctx" ]] && command -v docker >/dev/null 2>&1; then
        container_names=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            ps -a --filter "label=containai.managed=true" --format '{{.Names}}' 2>/dev/null) || container_names=""
    fi

    if [[ -z "$container_names" ]]; then
        _cai_info "No ContainAI-managed containers found"
        return 0
    fi

    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue

        # Get container state via inspect (more reliable than ps format)
        # Note: --format must come before -- since -- ends flag parsing
        local state
        state=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            inspect --type container --format '{{.State.Status}}' -- "$name" 2>/dev/null) || state="unknown"

        printf '  Container: %s (%s)\n' "$name" "$state"

        if [[ "$state" != "running" ]]; then
            printf '    %-46s %s\n' "SSH refresh:" "[SKIP] Container not running"
            skip_count=$((skip_count + 1))
            continue
        fi

        # Get SSH port
        local ssh_port
        ssh_port=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            port -- "$name" 22 2>/dev/null | head -1 | sed 's/.*://') || ssh_port=""

        if [[ -z "$ssh_port" ]]; then
            printf '    %-46s %s\n' "SSH refresh:" "[SKIP] No SSH port mapped"
            skip_count=$((skip_count + 1))
            continue
        fi

        # Refresh SSH configuration (force update)
        # Note: errors from _cai_setup_container_ssh are visible so users can debug failures
        # set -e safe increment: use $((var+1)) instead of ((var++))
        if _cai_setup_container_ssh "$name" "$ssh_port" "$ctx" "true"; then
            printf '    %-46s %s\n' "SSH refresh:" "[FIXED]"
            fixed_count=$((fixed_count + 1))
        else
            printf '    %-46s %s\n' "SSH refresh:" "[FAIL]"
            fail_count=$((fail_count + 1))
        fi
    done <<< "$container_names"

    printf '\n'
    printf '%s\n' "Summary"
    printf '  %-50s %s\n' "Fixed:" "$fixed_count"
    printf '  %-50s %s\n' "Skipped:" "$skip_count"
    printf '  %-50s %s\n' "Failed:" "$fail_count"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Fix a single container (SSH refresh)
# Arguments: $1 = effective Docker context
#            $2 = container name
_cai_doctor_fix_container_single() {
    local ctx="$1"
    local container_name="$2"

    printf '%s\n' "ContainAI Doctor Fix (Container: $container_name)"
    printf '%s\n' "=================================================="
    printf '\n'

    # Verify container exists and is managed
    # Note: --format must come before -- since -- ends flag parsing
    local container_labels
    container_labels=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
        inspect --type container --format '{{index .Config.Labels "containai.managed"}}' \
        -- "$container_name" 2>/dev/null) || {
        _cai_error "Container '$container_name' not found"
        return 1
    }

    if [[ "$container_labels" != "true" ]]; then
        _cai_warn "Container '$container_name' is not a ContainAI-managed container"
        _cai_info "Only containers with label 'containai.managed=true' can be fixed"
        return 1
    fi

    # Check container state
    local container_state
    container_state=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
        inspect --type container --format '{{.State.Status}}' \
        -- "$container_name" 2>/dev/null) || container_state=""

    printf '  Container: %s (%s)\n' "$container_name" "$container_state"

    if [[ "$container_state" != "running" ]]; then
        printf '    %-46s %s\n' "SSH refresh:" "[SKIP] Container not running"
        _cai_info "Start the container with 'cai shell' or 'cai run' first"
        return 0
    fi

    # Get SSH port
    local ssh_port
    ssh_port=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
        port -- "$container_name" 22 2>/dev/null | head -1 | sed 's/.*://') || ssh_port=""

    if [[ -z "$ssh_port" ]]; then
        printf '    %-46s %s\n' "SSH refresh:" "[SKIP] No SSH port mapped"
        return 0
    fi

    # Refresh SSH configuration (force update)
    if _cai_setup_container_ssh "$container_name" "$ssh_port" "$ctx" "true"; then
        printf '    %-46s %s\n' "SSH refresh:" "[FIXED]"
        return 0
    else
        printf '    %-46s %s\n' "SSH refresh:" "[FAIL]"
        return 1
    fi
}

# ==============================================================================
# Doctor Fix Template
# ==============================================================================

# Fix template issues by restoring from repo
# Arguments: [template_name] - defaults to "default"
#            --all - restore all repo-shipped templates
# Returns: 0=fixed, 1=error
_cai_doctor_fix_template() {
    local template_name=""
    local fix_all="false"
    local arg

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --all)
                fix_all="true"
                ;;
            -*)
                _cai_error "Unknown option: $arg"
                return 1
                ;;
            *)
                if [[ -n "$template_name" ]]; then
                    _cai_error "Only one template name allowed (got '$template_name' and '$arg')"
                    return 1
                fi
                template_name="$arg"
                ;;
        esac
    done

    # Reject --all combined with a template name
    if [[ "$fix_all" == "true" && -n "$template_name" ]]; then
        _cai_error "Cannot use --all with a specific template name"
        return 1
    fi

    _cai_info "ContainAI Doctor Fix - Templates"
    _cai_info "================================="
    printf '\n'

    local fixed_count=0
    local fail_count=0

    if [[ "$fix_all" == "true" ]]; then
        # Fix all repo-shipped templates
        local entry name
        for entry in "${_CAI_REPO_TEMPLATES[@]}"; do
            name="${entry%%:*}"
            _cai_info "Template '$name':"
            if _cai_doctor_fix_single_template "$name"; then
                ((fixed_count++)) || true
            else
                ((fail_count++)) || true
            fi
            printf '\n'
        done
    elif [[ -n "$template_name" ]]; then
        # Fix specific template
        _cai_info "Template '$template_name':"
        if _cai_doctor_fix_single_template "$template_name"; then
            ((fixed_count++)) || true
        else
            ((fail_count++)) || true
        fi
    else
        # Default: fix 'default' template
        _cai_info "Template 'default':"
        if _cai_doctor_fix_single_template "default"; then
            ((fixed_count++)) || true
        else
            ((fail_count++)) || true
        fi
    fi

    printf '\n'
    _cai_info "Summary"
    _cai_info "  Fixed: $fixed_count"
    _cai_info "  Failed: $fail_count"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Fix a single template by restoring from repo
# Arguments: $1 = template_name
# Returns: 0=fixed, 1=error
_cai_doctor_fix_single_template() {
    local template_name="$1"
    local template_path target_dir source_file backup_path
    local is_repo_template="false"
    local entry name src

    # Validate template name
    if ! _cai_validate_template_name "$template_name" 2>/dev/null; then
        printf '  %-46s %s\n' "Validate:" "[FAIL] Invalid template name"
        return 1
    fi

    template_path="$_CAI_TEMPLATE_DIR/$template_name/Dockerfile"
    target_dir="$_CAI_TEMPLATE_DIR/$template_name"

    # Check if this is a repo-shipped template
    for entry in "${_CAI_REPO_TEMPLATES[@]}"; do
        name="${entry%%:*}"
        src="${entry#*:}"
        if [[ "$name" == "$template_name" ]]; then
            is_repo_template="true"
            source_file="$src"
            break
        fi
    done

    # Backup existing template if present
    if [[ -f "$template_path" ]]; then
        backup_path="${template_path}.backup.$(date +%Y%m%d-%H%M%S)"
        _cai_info "  Backing up to ${backup_path##*/}..."
        if cp "$template_path" "$backup_path" 2>/dev/null; then
            _cai_ok "  Backup: ${backup_path}"
        else
            _cai_error "  Backup failed"
            return 1
        fi
    fi

    # Restore from repo if it's a repo-shipped template
    if [[ "$is_repo_template" == "true" ]]; then
        local repo_dir
        if ! repo_dir=$(_cai_get_repo_templates_dir 2>/dev/null); then
            _cai_error "  Cannot find repo templates directory"
            return 1
        fi

        local full_source="$repo_dir/$source_file"
        if [[ ! -f "$full_source" ]]; then
            _cai_error "  Source not found: $source_file"
            return 1
        fi

        # Create directory if needed
        if [[ ! -d "$target_dir" ]]; then
            if ! mkdir -p "$target_dir" 2>/dev/null; then
                _cai_error "  Failed to create directory: $target_dir"
                return 1
            fi
        fi

        _cai_info "  Restoring from: $full_source"
        _cai_info "  Restoring to:   $template_path"
        if cp "$full_source" "$template_path" 2>/dev/null; then
            _cai_ok "  Restored successfully"
            return 0
        else
            _cai_error "  Failed to restore template"
            return 1
        fi
    else
        # User-created template - can only backup, cannot restore
        printf '  %-46s %s\n' "Restore:" "[FAIL] User template, cannot restore from repo"
        if [[ -n "${backup_path:-}" ]]; then
            _cai_info "  Backup saved at: $backup_path"
        fi
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
# Args: build_templates ("true" to run heavy template build checks)
# Returns: 0 if Sysbox isolation is available
#          1 if no isolation available (cannot proceed)
_cai_doctor_json() {
    local build_templates="${1:-false}"
    local sysbox_ok="false"
    local platform
    local platform_json
    local seccomp_status=""
    local seccomp_compatible="true"
    local seccomp_warning=""
    local sysbox_runtime=""
    local sysbox_context_exists="false"
    local sysbox_context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"
    local recommended_action="setup_required"
    local kernel_version=""
    local kernel_compatible="true"
    local in_container="false"
    local in_sysbox_container="false"

    platform=$(_cai_detect_platform)
    if _cai_is_container; then
        in_container="true"
    fi
    if _cai_is_sysbox_container; then
        in_sysbox_container="true"
    fi
    # Normalize platform type for JSON (wsl -> wsl2 per spec)
    if [[ "$platform" == "wsl" ]]; then
        platform_json="wsl2"
    else
        platform_json="$platform"
    fi

    # Resolve context: use _cai_select_context which tries config override,
    # then containai-docker, then legacy fallback for old installs.
    # Inside a container, always use default context.
    if [[ "$in_container" == "true" ]]; then
        sysbox_context_name="default"
    else
        local config_context
        config_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || config_context=""
        sysbox_context_name=$(_cai_select_context "$config_context" 2>/dev/null) || sysbox_context_name=""
        # Default for error reporting if no context available
        if [[ -z "$sysbox_context_name" ]]; then
            sysbox_context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"
        fi
    fi

    # Check Sysbox with resolved context name
    local sysbox_error=""
    if [[ "$in_sysbox_container" == "true" ]]; then
        sysbox_ok="true"
        sysbox_runtime="sysbox-runc"
        sysbox_context_exists="true"
    elif _cai_sysbox_available_for_context "$sysbox_context_name"; then
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

    # Sysbox version information (Linux/WSL2 only)
    # Always use binary version (authoritative) - dpkg version is unreliable
    local sysbox_installed_version=""
    local sysbox_bundled_version=""
    local sysbox_needs_update_json="false"
    if [[ "$platform" != "macos" ]] && [[ "$sysbox_ok" == "true" ]]; then
        sysbox_installed_version=$(_cai_sysbox_installed_binary_version 2>/dev/null) || \
            sysbox_installed_version=$(_cai_sysbox_installed_version 2>/dev/null) || \
            sysbox_installed_version=""

        local arch
        arch=$(uname -m)
        case "$arch" in
            x86_64)  arch="amd64" ;;
            aarch64) arch="arm64" ;;
        esac
        sysbox_bundled_version=$(_cai_sysbox_bundled_version "$arch" 2>/dev/null) || sysbox_bundled_version=""
        if _cai_sysbox_needs_update "$arch" 2>/dev/null; then
            sysbox_needs_update_json="true"
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
            unavailable | unknown)
                seccomp_compatible="false"
                ;;
        esac
    fi

    # Isolation requires Sysbox available AND compatible kernel
    local isolation_available="false"
    if [[ "$in_sysbox_container" == "true" ]]; then
        isolation_available="true"
        recommended_action="ready"
    elif [[ "$sysbox_ok" == "true" ]] && [[ "$kernel_compatible" == "true" ]]; then
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
    local containai_docker_service_active="false"
    local containai_docker_service_state=""
    local containai_docker_service_exists="false"
    local containai_context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"
    local containai_socket="$_CAI_CONTAINAI_DOCKER_SOCKET"

    if [[ "$in_container" == "true" ]]; then
        containai_context_name="default"
        containai_socket="/var/run/docker.sock"
        local info_output info_rc
        info_output=$(_cai_timeout 10 env DOCKER_CONTEXT= DOCKER_HOST= docker info 2>&1) && info_rc=0 || info_rc=$?
        if [[ $info_rc -eq 0 ]]; then
            containai_docker_ok="true"
            containai_docker_default_runtime=$(env DOCKER_CONTEXT= DOCKER_HOST= docker info --format '{{.DefaultRuntime}}' 2>/dev/null || true)
            if [[ "$containai_docker_default_runtime" == "sysbox-runc" ]]; then
                containai_docker_sysbox_default="true"
            fi
        else
            if printf '%s' "$info_output" | grep -qi "permission denied"; then
                containai_docker_error="permission_denied"
            elif printf '%s' "$info_output" | grep -qi "connection refused"; then
                containai_docker_error="connection_refused"
            else
                containai_docker_error="daemon_unavailable"
            fi
        fi
    else
        # Check systemd service status (Linux/WSL2 only)
        if [[ "$platform" != "macos" ]]; then
            if _cai_containai_docker_service_exists; then
                containai_docker_service_exists="true"
            fi
            if _cai_containai_docker_service_active; then
                containai_docker_service_active="true"
            fi
            containai_docker_service_state="${_CAI_CONTAINAI_SERVICE_STATE:-unknown}"
        fi

        if _cai_containai_docker_available; then
            containai_docker_ok="true"
            containai_docker_default_runtime=$(_cai_containai_docker_default_runtime) || containai_docker_default_runtime=""
            if _cai_containai_docker_sysbox_is_default; then
                containai_docker_sysbox_default="true"
            fi
        else
            containai_docker_error="${_CAI_CONTAINAI_ERROR:-unknown}"
        fi
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
    if [[ "$ssh_version_ok" == "true" ]] && [[ "$ssh_key_ok" == "true" ]] \
        && [[ "$ssh_config_dir_ok" == "true" ]] && [[ "$ssh_include_ok" == "true" ]]; then
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
    # Sysbox version fields (Linux/WSL2 only)
    if [[ -n "$sysbox_installed_version" ]]; then
        printf '    "installed_version": "%s",\n' "$(_cai_json_escape "$sysbox_installed_version")"
    else
        printf '    "installed_version": null,\n'
    fi
    if [[ -n "$sysbox_bundled_version" ]]; then
        printf '    "bundled_version": "%s",\n' "$(_cai_json_escape "$sysbox_bundled_version")"
    else
        printf '    "bundled_version": null,\n'
    fi
    printf '    "needs_update": %s,\n' "$sysbox_needs_update_json"
    if [[ -n "$sysbox_error" ]]; then
        printf '    "error": "%s"\n' "$(_cai_json_escape "$sysbox_error")"
    else
        printf '    "error": null\n'
    fi
    printf '  },\n'
    printf '  "containai_docker": {\n'
    printf '    "available": %s,\n' "$containai_docker_ok"
    printf '    "context_name": "%s",\n' "$containai_context_name"
    printf '    "socket": "%s",\n' "$containai_socket"
    # Service status (Linux/WSL2 only)
    if [[ "$platform" != "macos" ]] && [[ "$in_container" != "true" ]]; then
        printf '    "service_name": "%s",\n' "$_CAI_CONTAINAI_DOCKER_SERVICE"
        printf '    "service_exists": %s,\n' "$containai_docker_service_exists"
        printf '    "service_active": %s,\n' "$containai_docker_service_active"
        if [[ -n "$containai_docker_service_state" ]]; then
            printf '    "service_state": "%s",\n' "$(_cai_json_escape "$containai_docker_service_state")"
        else
            printf '    "service_state": null,\n'
        fi
    fi
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
    if [[ "$platform" == "macos" ]]; then
        # Add Lima sysbox version info for macOS
        local lima_sysbox_json=""
        local lima_sysbox_needs_update_json="false"
        lima_sysbox_json=$(_cai_lima_sysbox_version 2>/dev/null) || lima_sysbox_json=""
        if [[ -n "$lima_sysbox_json" ]]; then
            # Extract just the version part
            lima_sysbox_json=$(printf '%s' "$lima_sysbox_json" | sed 's/sysbox-runc[[:space:]]*version[[:space:]]*//')
            if _cai_lima_sysbox_needs_update 2>/dev/null; then
                lima_sysbox_needs_update_json="true"
            fi
        fi
        if [[ -n "$lima_sysbox_json" ]]; then
            printf '    "lima_sysbox_version": "%s",\n' "$(_cai_json_escape "$lima_sysbox_json")"
        else
            printf '    "lima_sysbox_version": null,\n'
        fi
        printf '    "lima_sysbox_needs_update": %s,\n' "$lima_sysbox_needs_update_json"
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

    # Network security section (Linux/WSL2 hosts only)
    local network_security_ok_json="true"
    local network_status_json=""
    local network_detail_json=""
    local network_applicable="false"

    if [[ "$platform" == "linux" ]] || [[ "$platform" == "wsl" ]]; then
        if [[ "$in_container" == "false" ]]; then
            network_applicable="true"
            network_status_json=$(_cai_network_doctor_status)
            network_detail_json="${_CAI_NETWORK_DOCTOR_DETAIL:-}"
            case "$network_status_json" in
                ok | skipped)
                    network_security_ok_json="true"
                    ;;
                *)
                    network_security_ok_json="false"
                    ;;
            esac
        fi
    fi

    printf '  "network_security": {\n'
    printf '    "applicable": %s,\n' "$network_applicable"
    if [[ "$network_applicable" == "true" ]]; then
        printf '    "status": "%s",\n' "$(_cai_json_escape "$network_status_json")"
        if [[ -n "$network_detail_json" ]]; then
            printf '    "detail": "%s",\n' "$(_cai_json_escape "$network_detail_json")"
        else
            printf '    "detail": null,\n'
        fi
        printf '    "ok": %s\n' "$network_security_ok_json"
    else
        printf '    "status": null,\n'
        printf '    "detail": null,\n'
        printf '    "ok": true\n'
    fi
    printf '  },\n'

    # Template checks
    local template_all_ok="true"
    _cai_doctor_template_checks_json "$build_templates" "$sysbox_context_name" || template_all_ok="false"

    printf '  "summary": {\n'
    printf '    "sysbox_ok": %s,\n' "$sysbox_ok"
    printf '    "containai_docker_ok": %s,\n' "$containai_docker_ok"
    printf '    "ssh_ok": %s,\n' "$ssh_all_ok"
    printf '    "network_security_ok": %s,\n' "$network_security_ok_json"
    printf '    "templates_ok": %s,\n' "$template_all_ok"
    printf '    "isolation_available": %s,\n' "$isolation_available"
    printf '    "recommended_action": "%s"\n' "$recommended_action"
    printf '  }\n'
    printf '}\n'

    # Exit code: 0 if Sysbox available AND SSH configured AND network OK AND templates OK, 1 if not
    if [[ "$isolation_available" == "true" ]] && [[ "$ssh_all_ok" == "true" ]] \
        && [[ "$network_security_ok_json" == "true" ]] && [[ "$template_all_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# ==============================================================================
# Volume Ownership Repair (Linux/WSL2 only)
# ==============================================================================

# Check if a path appears to have id-mapping corruption
# Arguments: $1 = path to check
# Returns: 0=corrupted (nobody:nogroup), 1=not corrupted or not found
# Note: Files owned by 65534:65534 (nobody:nogroup) indicate id-mapped mount
#       corruption after sysbox restart (kernel bug workaround)
_cai_doctor_check_path_ownership() {
    local path="$1"
    local owner_uid owner_gid

    if [[ ! -e "$path" ]]; then
        return 1
    fi

    # Get UID/GID using stat
    # Linux: stat -c "%u:%g"
    # macOS: stat -f "%u:%g" (not used on macOS, but for consistency)
    owner_uid=$(stat -c "%u" "$path" 2>/dev/null) || return 1
    owner_gid=$(stat -c "%g" "$path" 2>/dev/null) || return 1

    # Check for nobody:nogroup (65534:65534)
    if [[ "$owner_uid" == "65534" ]] || [[ "$owner_gid" == "65534" ]]; then
        return 0  # Corrupted
    fi

    return 1  # Not corrupted
}

# Check if a volume has id-mapping corruption
# Arguments: $1 = volume path (under /var/lib/containai-docker/volumes)
# Returns: 0=has corruption, 1=no corruption or error
# Outputs: Number of corrupted files on stdout
_cai_doctor_check_volume_ownership() {
    local volume_path="$1"
    local corrupted_count=0

    # Validate path is under containai-docker volumes
    local volumes_root="$_CAI_CONTAINAI_DOCKER_DATA/volumes"
    case "$volume_path" in
        "$volumes_root"/*)
            # Path is under volumes root - OK
            ;;
        *)
            # Not under volumes root - reject
            return 1
            ;;
    esac

    # Reject paths with .. segments (traversal attack)
    if [[ "$volume_path" == *"/../"* ]] || [[ "$volume_path" == *"/.."* ]]; then
        return 1
    fi

    # Check if path exists
    if [[ ! -d "$volume_path" ]]; then
        return 1
    fi

    # Count files with nobody:nogroup ownership using find
    # -xdev prevents crossing filesystem boundaries
    # -not -type l skips symlinks to prevent traversal attacks
    # Use -print0 to handle filenames with newlines safely
    local file
    while IFS= read -r -d '' file; do
        if _cai_doctor_check_path_ownership "$file"; then
            ((corrupted_count++))
        fi
    done < <(find "$volume_path" -xdev -not -type l -print0 2>/dev/null || true)

    printf '%d' "$corrupted_count"
    [[ "$corrupted_count" -gt 0 ]]
}

# Detect UID/GID from a running container
# Arguments: $1 = container name or ID
# Returns: 0=success, 1=container not running or error
# Outputs: "uid:gid" on stdout (e.g., "1000:1000")
_cai_doctor_detect_uid() {
    local container="$1"

    # Get container info from containai-docker context
    local user_info
    user_info=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" \
        inspect --type container "$container" \
        --format '{{.Config.User}}' 2>/dev/null) || return 1

    # Check container state for exec capability
    local container_state
    container_state=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" \
        inspect --type container "$container" \
        --format '{{.State.Running}}' 2>/dev/null) || container_state=""

    # If user is specified in numeric format "uid:gid" or "uid", use it directly
    if [[ -n "$user_info" ]] && [[ "$user_info" =~ ^[0-9]+(:[0-9]+)?$ ]]; then
        if [[ "$user_info" == *:* ]]; then
            printf '%s' "$user_info"
            return 0
        else
            # Just UID, assume same GID
            printf '%s:%s' "$user_info" "$user_info"
            return 0
        fi
    fi

    # For running containers, get the effective UID/GID via exec
    # This handles: empty Config.User, root, or named users
    if [[ "$container_state" == "true" ]]; then
        local id_output gid_output

        # If user_info is a non-root name, resolve that specific user
        if [[ -n "$user_info" ]] && [[ "$user_info" != "root" ]]; then
            # Parse user:group if present
            local user_name
            if [[ "$user_info" == *:* ]]; then
                user_name="${user_info%%:*}"
            else
                user_name="$user_info"
            fi
            id_output=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" \
                exec "$container" id -u "$user_name" 2>/dev/null) || id_output=""
            gid_output=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" \
                exec "$container" id -g "$user_name" 2>/dev/null) || gid_output=""
            if [[ -n "$id_output" ]] && [[ -n "$gid_output" ]]; then
                printf '%s:%s' "$id_output" "$gid_output"
                return 0
            fi
        fi

        # Get the effective UID/GID of the container's default process
        # This works for empty Config.User, root, or when named user resolution failed
        id_output=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" \
            exec "$container" id -u 2>/dev/null) || id_output=""
        gid_output=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" \
            exec "$container" id -g 2>/dev/null) || gid_output=""
        if [[ -n "$id_output" ]] && [[ -n "$gid_output" ]]; then
            printf '%s:%s' "$id_output" "$gid_output"
            return 0
        fi
    fi

    # Could not detect - caller should use fallback
    return 1
}

# Detect container's effective UID:GID (context-aware version)
# Arguments: $1 = Docker context name
#            $2 = container name or ID
# Returns: 0=detected, 1=could not detect (container stopped or other issue)
# Outputs: "uid:gid" on stdout (e.g., "1000:1000")
_cai_doctor_detect_uid_for_context() {
    local ctx="$1"
    local container="$2"

    # Get container info (--format before -- since -- ends flag parsing)
    local user_info
    user_info=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
        inspect --type container --format '{{.Config.User}}' \
        -- "$container" 2>/dev/null) || return 1

    # Check container state for exec capability
    local container_state
    container_state=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
        inspect --type container --format '{{.State.Running}}' \
        -- "$container" 2>/dev/null) || container_state=""

    # If user is specified in numeric format "uid:gid" or "uid", use it directly
    if [[ -n "$user_info" ]] && [[ "$user_info" =~ ^[0-9]+(:[0-9]+)?$ ]]; then
        if [[ "$user_info" == *:* ]]; then
            printf '%s' "$user_info"
            return 0
        else
            # Just UID, assume same GID
            printf '%s:%s' "$user_info" "$user_info"
            return 0
        fi
    fi

    # For running containers, get the effective UID/GID via exec
    # This handles: empty Config.User, root, or named users
    if [[ "$container_state" == "true" ]]; then
        local id_output gid_output

        # If user_info is a non-root name, resolve that specific user
        if [[ -n "$user_info" ]] && [[ "$user_info" != "root" ]]; then
            # Parse user:group if present
            local user_name
            if [[ "$user_info" == *:* ]]; then
                user_name="${user_info%%:*}"
            else
                user_name="$user_info"
            fi
            id_output=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
                exec -- "$container" id -u "$user_name" 2>/dev/null) || id_output=""
            gid_output=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
                exec -- "$container" id -g "$user_name" 2>/dev/null) || gid_output=""
            if [[ -n "$id_output" ]] && [[ -n "$gid_output" ]]; then
                printf '%s:%s' "$id_output" "$gid_output"
                return 0
            fi
        fi

        # Get the effective UID/GID of the container's default process
        id_output=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            exec -- "$container" id -u 2>/dev/null) || id_output=""
        gid_output=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            exec -- "$container" id -g 2>/dev/null) || gid_output=""
        if [[ -n "$id_output" ]] && [[ -n "$gid_output" ]]; then
            printf '%s:%s' "$id_output" "$gid_output"
            return 0
        fi
    fi

    # Could not detect - caller should use fallback
    return 1
}

# Get volumes attached to a container
# Arguments: $1 = container name or ID
# Returns: 0=success (may have 0 volumes), 1=error
# Outputs: Volume names (one per line) on stdout
# Note: Uses hardcoded context - prefer _cai_doctor_get_container_volumes_for_context
_cai_doctor_get_container_volumes() {
    local container="$1"
    local mounts

    # Get mount info
    mounts=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" \
        inspect --type container "$container" \
        --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' 2>/dev/null) || return 1

    printf '%s' "$mounts"
    return 0
}

# Get volumes attached to a container (context-aware version)
# Arguments: $1 = Docker context name
#            $2 = container name or ID
# Returns: 0=success (may have 0 volumes), 1=error
# Outputs: Volume names (one per line) on stdout
_cai_doctor_get_container_volumes_for_context() {
    local ctx="$1"
    local container="$2"
    local mounts

    # Get mount info using specified context (--format before -- since -- ends flag parsing)
    mounts=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
        inspect --type container --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' \
        -- "$container" 2>/dev/null) || return 1

    printf '%s' "$mounts"
    return 0
}

# Repair ownership on a single volume
# Arguments: $1 = volume name
#            $2 = target uid:gid (e.g., "1000:1000")
#            $3 = dry_run flag ("true" or "false")
# Returns: 0=success or no action needed, 1=error
# Outputs: Status messages to stdout
_cai_doctor_repair_volume() {
    local volume_name="$1"
    local target_ownership="$2"
    local dry_run="$3"
    local target_uid target_gid

    # Parse target ownership
    target_uid="${target_ownership%%:*}"
    target_gid="${target_ownership##*:}"

    # Construct volume data path
    local volumes_root="$_CAI_CONTAINAI_DOCKER_DATA/volumes"
    local volume_data_path="$volumes_root/$volume_name/_data"

    # Validate volume path exists
    if [[ ! -d "$volume_data_path" ]]; then
        printf '  %-50s %s\n' "Volume '$volume_name':" "[SKIP] Not found"
        return 0
    fi

    # Check for corruption
    local corrupted_count
    corrupted_count=$(_cai_doctor_check_volume_ownership "$volume_data_path" 2>/dev/null) || corrupted_count=""

    if [[ -z "$corrupted_count" ]] || [[ "$corrupted_count" == "0" ]]; then
        printf '  %-50s %s\n' "Volume '$volume_name':" "[OK] No corruption"
        return 0
    fi

    # Report corruption
    printf '  %-50s %s\n' "Volume '$volume_name':" "[CORRUPT] $corrupted_count files with nobody:nogroup"

    if [[ "$dry_run" == "true" ]]; then
        printf '  %-50s %s\n' "  Would chown to $target_ownership" "[DRY-RUN]"
        return 0
    fi

    # Perform repair using sudo chown
    # Use -h to affect symlinks themselves (not targets)
    # Use find with -xdev to prevent cross-filesystem traversal
    # Use -not -type l to skip symlinks
    printf '  %-50s' "  Repairing to $target_ownership..."
    if sudo find "$volume_data_path" -xdev -not -type l \
        \( -user 65534 -o -group 65534 \) \
        -exec chown -h "$target_uid:$target_gid" {} + 2>/dev/null; then
        printf ' %s\n' "[FIXED]"
        return 0
    else
        printf ' %s\n' "[FAIL]"
        return 1
    fi
}

# Check if rootfs shows id-mapping corruption
# Arguments: $1 = container name or ID
# Returns: 0=tainted (has corruption), 1=clean or cannot check
_cai_doctor_check_rootfs_tainted() {
    local container="$1"

    # Get container rootfs path from containai-docker context
    local rootfs_path
    rootfs_path=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" \
        inspect --type container "$container" \
        --format '{{.GraphDriver.Data.MergedDir}}' 2>/dev/null) || return 1

    if [[ -z "$rootfs_path" ]] || [[ ! -d "$rootfs_path" ]]; then
        return 1
    fi

    # Check a few key paths for corruption
    local check_paths=("/etc" "/home" "/var")
    local path
    for path in "${check_paths[@]}"; do
        local full_path="$rootfs_path$path"
        if [[ -d "$full_path" ]] && _cai_doctor_check_path_ownership "$full_path"; then
            return 0  # Tainted
        fi
    done

    return 1  # Clean
}

# Check if rootfs shows id-mapping corruption (context-aware version)
# Arguments: $1 = Docker context
#            $2 = container name or ID
# Returns: 0=tainted (has corruption), 1=clean or cannot check
_cai_doctor_check_rootfs_tainted_for_context() {
    local ctx="$1"
    local container="$2"

    # Get container rootfs path (--format before -- since -- ends flag parsing)
    local rootfs_path
    rootfs_path=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
        inspect --type container --format '{{.GraphDriver.Data.MergedDir}}' \
        -- "$container" 2>/dev/null) || return 1

    if [[ -z "$rootfs_path" ]] || [[ ! -d "$rootfs_path" ]]; then
        return 1
    fi

    # Check a few key paths for corruption
    local check_paths=("/etc" "/home" "/var")
    local path
    for path in "${check_paths[@]}"; do
        local full_path="$rootfs_path$path"
        if [[ -d "$full_path" ]] && _cai_doctor_check_path_ownership "$full_path"; then
            return 0  # Tainted
        fi
    done

    return 1  # Clean
}

# Main entry point for repair mode
# Arguments: $1 = Docker context (use effective context from caller)
#            $2 = container_filter ("" for --all, container name/id for --container)
#            $3 = dry_run flag ("true" or "false")
# Returns: 0=success, 1=error
_cai_doctor_repair() {
    local ctx="${1:-$_CAI_CONTAINAI_DOCKER_CONTEXT}"
    local container_filter="$2"
    local dry_run="$3"
    local platform
    local fixed_count=0
    local skip_count=0
    local fail_count=0
    local warn_count=0

    platform=$(_cai_detect_platform)

    # Platform check - repair is Linux/WSL2 only
    if [[ "$platform" == "macos" ]]; then
        _cai_info "Volume repair is not supported on macOS (volumes are inside Lima VM)"
        return 0
    fi

    printf '%s\n' "ContainAI Doctor (Repair Mode)"
    printf '%s\n' "=============================="
    printf '\n'

    # Check if containai-docker is available
    if ! _cai_containai_docker_available; then
        _cai_error "ContainAI Docker is not available"
        _cai_info "Run 'cai setup' to configure containai-docker"
        return 1
    fi

    # Verify volumes root exists
    local volumes_root="$_CAI_CONTAINAI_DOCKER_DATA/volumes"
    if [[ ! -d "$volumes_root" ]]; then
        _cai_info "Volumes directory does not exist: $volumes_root"
        _cai_info "No volumes to repair"
        return 0
    fi

    printf '%s\n' "Scanning volumes..."
    printf '\n'

    # Get containers to process
    local containers=""
    if [[ -n "$container_filter" ]]; then
        # Specific container - verify it exists and has the managed label
        # Note: --format before -- since -- ends flag parsing
        local container_labels
        container_labels=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            inspect --type container --format '{{index .Config.Labels "containai.managed"}}' \
            -- "$container_filter" 2>/dev/null) || {
            _cai_error "Container '$container_filter' not found"
            return 1
        }
        if [[ "$container_labels" != "true" ]]; then
            _cai_warn "Container '$container_filter' is not a ContainAI-managed container"
            _cai_info "Only containers with label 'containai.managed=true' can be repaired"
            return 1
        fi
        containers="$container_filter"
    else
        # All managed containers
        containers=$(DOCKER_CONTEXT= DOCKER_HOST= docker --context "$ctx" \
            ps -a --filter "label=containai.managed=true" --format '{{.Names}}' 2>/dev/null) || containers=""
    fi

    if [[ -z "$containers" ]]; then
        _cai_info "No ContainAI-managed containers found"
        return 0
    fi

    # Process each container
    local container
    while IFS= read -r container; do
        [[ -z "$container" ]] && continue

        printf '%s\n' "Container: $container"

        # Check rootfs for corruption (context-aware)
        if _cai_doctor_check_rootfs_tainted_for_context "$ctx" "$container"; then
            printf '  %-50s %s\n' "Rootfs:" "[WARN] Tainted - consider recreating container"
            ((warn_count++)) || true
        fi

        # Get target UID/GID (context-aware)
        local target_ownership
        if target_ownership=$(_cai_doctor_detect_uid_for_context "$ctx" "$container" 2>/dev/null); then
            printf '  %-50s %s\n' "Target ownership:" "$target_ownership (from container)"
        else
            target_ownership="1000:1000"
            printf '  %-50s %s\n' "Target ownership:" "$target_ownership (default - container not running)"
            warn_count=$((warn_count + 1))
        fi

        # Get volumes for this container (context-aware)
        local volumes
        volumes=$(_cai_doctor_get_container_volumes_for_context "$ctx" "$container" 2>/dev/null) || volumes=""

        if [[ -z "$volumes" ]]; then
            printf '  %-50s %s\n' "Volumes:" "[SKIP] No volumes attached"
            printf '\n'
            continue
        fi

        # Process each volume
        local volume
        while IFS= read -r volume; do
            [[ -z "$volume" ]] && continue
            # set -e safe increment: use $((var+1)) instead of ((var++))
            if _cai_doctor_repair_volume "$volume" "$target_ownership" "$dry_run"; then
                fixed_count=$((fixed_count + 1))
            else
                fail_count=$((fail_count + 1))
            fi
        done <<< "$volumes"

        printf '\n'
    done <<< "$containers"

    # Summary
    printf '%s\n' "Summary"
    if [[ "$dry_run" == "true" ]]; then
        printf '  %-50s %s\n' "Mode:" "[DRY-RUN] No changes made"
    fi
    printf '  %-50s %s\n' "Volumes checked:" "$((fixed_count + fail_count))"
    printf '  %-50s %s\n' "Volumes ok:" "$fixed_count"
    printf '  %-50s %s\n' "Warnings:" "$warn_count"
    printf '  %-50s %s\n' "Failures:" "$fail_count"

    if [[ "$warn_count" -gt 0 ]]; then
        printf '\n'
        _cai_warn "Some containers have tainted rootfs or used default UID/GID"
        _cai_info "Consider recreating affected containers with 'cai stop <name> && cai run ...'"
    fi

    if [[ "$fail_count" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# Reset Lima (macOS only)
# ==============================================================================

# Reset the Lima VM and Docker context
# Deletes VM, removes Docker context, clears template hash
# Uses _cai_prompt_confirm() for confirmation (supports CAI_YES=1)
# Depends on: _cai_lima_vm_exists, _cai_lima_vm_status from lib/setup.sh
# Returns: 0 on success, 1 on error
_cai_doctor_reset_lima() {
    local platform
    platform=$(_cai_detect_platform)

    # Only available on macOS
    if [[ "$platform" != "macos" ]]; then
        _cai_error "--reset-lima is only available on macOS"
        return 1
    fi

    # Require limactl - this is a Lima VM reset command
    if ! command -v limactl >/dev/null 2>&1; then
        _cai_error "limactl is not installed"
        _cai_info "Install Lima first: brew install lima"
        return 1
    fi

    _cai_warn "This will delete the ContainAI Lima VM ($_CAI_LIMA_VM_NAME) and Docker context."
    _cai_warn "Workspace data on the host is preserved."

    if ! _cai_prompt_confirm "Continue?" false; then
        _cai_info "Reset cancelled"
        return 0
    fi

    local had_error="false"

    # Best-effort stop - ignore "not found" errors
    _cai_info "Stopping VM (if running)..."
    if ! limactl stop "$_CAI_LIMA_VM_NAME" 2>/dev/null; then
        # Only error if VM exists but stop failed for other reasons
        if limactl list "$_CAI_LIMA_VM_NAME" 2>/dev/null | grep -q "$_CAI_LIMA_VM_NAME"; then
            _cai_warn "Failed to stop VM '$_CAI_LIMA_VM_NAME' (may already be stopped)"
        fi
    fi

    # Attempt delete unconditionally - "not found" is non-fatal
    _cai_info "Deleting VM..."
    local delete_output
    delete_output=$(limactl delete --force "$_CAI_LIMA_VM_NAME" 2>&1) || {
        # Check if error is "not found" (non-fatal) vs actual failure
        if [[ "$delete_output" == *"not found"* ]] || [[ "$delete_output" == *"does not exist"* ]]; then
            _cai_info "VM '$_CAI_LIMA_VM_NAME' does not exist (already deleted)"
        else
            _cai_error "Failed to delete VM '$_CAI_LIMA_VM_NAME': $delete_output"
            had_error="true"
        fi
    }

    # Remove Docker context (switch away if active, then force remove)
    if command -v docker >/dev/null 2>&1 && docker context inspect "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
        _cai_info "Removing Docker context..."
        # Switch away if this context is currently active
        local current_context
        current_context=$(docker context show 2>/dev/null || true)
        if [[ "$current_context" == "$_CAI_CONTAINAI_DOCKER_CONTEXT" ]]; then
            docker context use default >/dev/null 2>&1 || true
        fi
        if ! docker context rm -f "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
            _cai_error "Failed to remove Docker context '$_CAI_CONTAINAI_DOCKER_CONTEXT'"
            had_error="true"
        fi
    fi

    # Remove template hash
    rm -f "$HOME/.config/containai/lima-template.hash"

    if [[ "$had_error" == "true" ]]; then
        _cai_error "Lima VM reset completed with errors"
        return 1
    fi

    _cai_ok "Lima VM reset complete"
    _cai_info "Run 'cai setup' to recreate the VM"
    return 0
}

# ==============================================================================
# Template Checks
# ==============================================================================

# Check if a template exists (filesystem check only)
# Args: template_name (defaults to "default")
# Returns: 0=exists, 1=missing, 2=invalid name
# Outputs: status string to stdout ("ok", "missing", "invalid_name")
_cai_doctor_check_template_exists() {
    local template_name="${1:-default}"
    local template_path

    # Validate template name
    if ! _cai_validate_template_name "$template_name" 2>/dev/null; then
        printf '%s' "invalid_name"
        return 2
    fi

    template_path="$_CAI_TEMPLATE_DIR/$template_name/Dockerfile"

    if [[ -f "$template_path" ]]; then
        printf '%s' "ok"
        return 0
    else
        printf '%s' "missing"
        return 1
    fi
}

# Check basic Dockerfile syntax (FROM line exists)
# This is a fast filesystem check, no Docker daemon needed
# Args: template_name (defaults to "default")
# Returns: 0=valid, 1=invalid syntax, 2=template not found
# Outputs: error status string to stdout ("ok", "no_from", "missing")
_cai_doctor_check_template_syntax() {
    local template_name="${1:-default}"
    local template_path
    local from_found="false"
    local line

    # Validate template name
    if ! _cai_validate_template_name "$template_name" 2>/dev/null; then
        printf '%s' "invalid_name"
        return 2
    fi

    template_path="$_CAI_TEMPLATE_DIR/$template_name/Dockerfile"

    if [[ ! -f "$template_path" ]]; then
        printf '%s' "missing"
        return 2
    fi

    # Parse Dockerfile looking for FROM line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        # Check for FROM line (case-insensitive)
        if [[ "$line" =~ ^[Ff][Rr][Oo][Mm][[:space:]]+ ]]; then
            from_found="true"
            break
        fi
    done < "$template_path"

    if [[ "$from_found" == "true" ]]; then
        printf '%s' "ok"
        return 0
    else
        printf '%s' "no_from"
        return 1
    fi
}

# Perform heavy template validation by attempting actual Docker build
# This is opt-in only via --build-templates flag
# Args: template_name [docker_context]
# Returns: 0=build successful, 1=build failed
# Outputs: error status string to stdout ("ok", "build_failed", "missing")
_cai_doctor_check_template_build() {
    local template_name="${1:-default}"
    local docker_context="${2:-}"
    local template_path image_tag

    # Validate template name
    if ! _cai_validate_template_name "$template_name" 2>/dev/null; then
        printf '%s' "invalid_name"
        return 1
    fi

    template_path="$_CAI_TEMPLATE_DIR/$template_name/Dockerfile"

    if [[ ! -f "$template_path" ]]; then
        printf '%s' "missing"
        return 1
    fi

    # Build docker command array
    local -a docker_cmd=(docker)
    if [[ -n "$docker_context" ]]; then
        docker_cmd=(docker --context "$docker_context")
    fi

    # Template directory is the build context
    local template_dir
    template_dir="$(dirname "$template_path")"

    # Image tag for test build
    image_tag="containai-template-${template_name}:local"

    # Attempt the build
    if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" build -t "$image_tag" "$template_dir" >/dev/null 2>&1; then
        printf '%s' "ok"
        return 0
    else
        printf '%s' "build_failed"
        return 1
    fi
}

# Run all template checks for doctor output (text format)
# Args: build_templates ("true" to run heavy build checks)
#       docker_context (optional docker context for build checks)
# Outputs: Formatted text report to stdout
# Returns: 0 if all checks pass, 1 if any check fails
_cai_doctor_template_checks() {
    local build_templates="${1:-false}"
    local docker_context="${2:-}"
    local template_exists_status template_syntax_status template_build_status
    local template_path="$_CAI_TEMPLATE_DIR/default/Dockerfile"
    local all_ok="true"

    printf '%s\n' "Templates"

    # Check if default template exists
    template_exists_status=$(_cai_doctor_check_template_exists "default")
    case "$template_exists_status" in
        ok)
            printf '  %-44s %s\n' "Template 'default':" "[OK]"
            ;;
        missing)
            all_ok="false"
            printf '  %s\n' "[FAIL] Template 'default' missing"
            printf '  %-44s %s\n' "" "Run 'cai doctor fix template' to recover"
            ;;
        invalid_name)
            # Should never happen for "default"
            all_ok="false"
            printf '  %-44s %s\n' "Template 'default':" "[ERROR] Invalid name"
            ;;
    esac

    # Only run syntax check if template exists
    if [[ "$template_exists_status" == "ok" ]]; then
        template_syntax_status=$(_cai_doctor_check_template_syntax "default")
        case "$template_syntax_status" in
            ok)
                printf '  %-44s %s\n' "Dockerfile syntax:" "[OK] FROM line found"

                # Run base image validation (warn only, don't fail)
                # Only check if syntax is valid (FROM line exists)
                local suppress_warning="${_CAI_TEMPLATE_SUPPRESS_BASE_WARNING:-false}"
                if _cai_validate_template_base "$template_path" "true" 2>/dev/null; then
                    printf '  %-44s %s\n' "Base image:" "[OK] ContainAI base"
                elif [[ "$suppress_warning" != "true" ]]; then
                    # Not ContainAI base, show warning
                    printf '  %-44s %s\n' "Base image:" "[WARN] Not ContainAI"
                    printf '  %-44s %s\n' "" "(ContainAI features may not work)"
                fi
                # If suppressed, don't show anything about base image
                ;;
            no_from)
                all_ok="false"
                printf '  %-44s %s\n' "Dockerfile syntax:" "[FAIL] No FROM line"
                printf '  %-44s %s\n' "" "Dockerfile must have a FROM instruction"
                printf '  %-44s %s\n' "" "Run 'cai doctor fix template' to recover"
                ;;
        esac
    fi

    # Heavy build check (opt-in only)
    if [[ "$build_templates" == "true" ]]; then
        if [[ "$template_exists_status" != "ok" ]]; then
            printf '  %-44s %s\n' "Docker build:" "[SKIP] Template missing"
        else
            printf '  %-44s' "Docker build:"
            template_build_status=$(_cai_doctor_check_template_build "default" "$docker_context")
            case "$template_build_status" in
                ok)
                    printf ' %s\n' "[OK] Build successful"
                    ;;
                build_failed)
                    all_ok="false"
                    printf ' %s\n' "[FAIL] Build failed"
                    printf '  %-44s %s\n' "" "Check Dockerfile for errors or Docker availability"
                    ;;
            esac
        fi
    fi

    printf '\n'

    # Return status
    if [[ "$all_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Run template checks for doctor JSON output
# Args: build_templates ("true" to run heavy build checks)
#       docker_context (optional docker context for build checks)
# Outputs: JSON object fields to stdout (no surrounding braces)
# Returns: 0 if all checks pass, 1 otherwise
_cai_doctor_template_checks_json() {
    local build_templates="${1:-false}"
    local docker_context="${2:-}"
    local template_exists_status template_syntax_status template_build_status
    local template_path="$_CAI_TEMPLATE_DIR/default/Dockerfile"
    local base_valid="false"
    local all_ok="true"

    # Check if default template exists
    template_exists_status=$(_cai_doctor_check_template_exists "default")
    if [[ "$template_exists_status" != "ok" ]]; then
        all_ok="false"
    fi

    # Syntax check (only if exists)
    if [[ "$template_exists_status" == "ok" ]]; then
        template_syntax_status=$(_cai_doctor_check_template_syntax "default")
        if [[ "$template_syntax_status" != "ok" ]]; then
            all_ok="false"
        fi

        # Base validation (only if syntax is valid - FROM line exists)
        if [[ "$template_syntax_status" == "ok" ]]; then
            if _cai_validate_template_base "$template_path" "true" 2>/dev/null; then
                base_valid="true"
            fi
        fi
    else
        template_syntax_status="not_checked"
    fi

    # Build check (only if requested and template exists)
    if [[ "$build_templates" == "true" ]] && [[ "$template_exists_status" == "ok" ]]; then
        template_build_status=$(_cai_doctor_check_template_build "default" "$docker_context")
        if [[ "$template_build_status" != "ok" ]]; then
            all_ok="false"
        fi
    else
        template_build_status="not_checked"
    fi

    # Output JSON fields
    printf '  "templates": {\n'
    printf '    "default": {\n'
    printf '      "exists": %s,\n' "$([[ "$template_exists_status" == "ok" ]] && printf 'true' || printf 'false')"
    printf '      "path": "%s",\n' "$(_cai_json_escape "$template_path")"
    printf '      "syntax_valid": %s,\n' "$([[ "$template_syntax_status" == "ok" ]] && printf 'true' || printf 'false')"
    printf '      "base_valid": %s,\n' "$base_valid"
    if [[ "$build_templates" == "true" ]]; then
        printf '      "build_ok": %s,\n' "$([[ "$template_build_status" == "ok" ]] && printf 'true' || printf 'false')"
        printf '      "build_checked": true\n'
    else
        printf '      "build_ok": null,\n'
        printf '      "build_checked": false\n'
    fi
    printf '    },\n'
    printf '    "all_ok": %s\n' "$all_ok"
    printf '  },\n'

    if [[ "$all_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

return 0
