#!/usr/bin/env bash
# ==============================================================================
# ContainAI Platform Detection
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_detect_platform()    - Returns "wsl", "macos", or "linux"
#   _cai_is_wsl()             - Check if running under WSL
#   _cai_is_macos()           - Check if running on macOS
#   _cai_is_linux()           - Check if running on Linux (non-WSL)
#
# Resource detection:
#   _cai_detect_memory_bytes()     - Detect host memory in bytes
#   _cai_detect_cpu_count()        - Detect host CPU count
#   _cai_detect_resources()        - Detect host resources and compute container limits
#   _cai_default_container_memory() - Get default container memory limit (50% of host, 2GB min)
#   _cai_default_container_cpus()   - Get default container CPU limit (50% of host, 1 CPU min)
#
# Usage: source lib/platform.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/platform.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/platform.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/platform.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_PLATFORM_LOADED:-}" ]]; then
    return 0
fi
_CAI_PLATFORM_LOADED=1

# ==============================================================================
# Platform detection
# ==============================================================================

# Detect current platform
# Returns: "wsl", "macos", or "linux" via stdout
# Note: WSL is detected before generic Linux check
_cai_detect_platform() {
    # Check for macOS first (uname -s)
    if [[ "$(uname -s)" == "Darwin" ]]; then
        printf '%s' "macos"
        return 0
    fi

    # Check for WSL - multiple detection methods for reliability
    # Method 1: WSL_DISTRO_NAME environment variable (most reliable)
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        printf '%s' "wsl"
        return 0
    fi

    # Method 2: WSLInterop binfmt (exists on WSL)
    if [[ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]]; then
        printf '%s' "wsl"
        return 0
    fi

    # Method 3: Check /proc/version for Microsoft/WSL string
    if [[ -f "/proc/version" ]]; then
        local version_content
        version_content=$(cat /proc/version 2>/dev/null) || version_content=""
        if [[ "$version_content" == *[Mm]icrosoft* ]] || [[ "$version_content" == *WSL* ]]; then
            printf '%s' "wsl"
            return 0
        fi
    fi

    # Default to Linux for other cases
    printf '%s' "linux"
    return 0
}

# Check if running under WSL
# Returns: 0=yes, 1=no
_cai_is_wsl() {
    [[ "$(_cai_detect_platform)" == "wsl" ]]
}

# Check if running on macOS
# Returns: 0=yes, 1=no
_cai_is_macos() {
    [[ "$(_cai_detect_platform)" == "macos" ]]
}

# Check if running on Linux (non-WSL)
# Returns: 0=yes, 1=no
_cai_is_linux() {
    [[ "$(_cai_detect_platform)" == "linux" ]]
}

# ==============================================================================
# Host resource detection
# ==============================================================================

# Detect host memory in bytes
# Returns: Memory in bytes via stdout
# Falls back to 8GB (8589934592) if detection fails
_cai_detect_memory_bytes() {
    local mem_bytes=0

    case "$(_cai_detect_platform)" in
        macos)
            # macOS: sysctl hw.memsize returns bytes
            mem_bytes=$(sysctl -n hw.memsize 2>/dev/null) || mem_bytes=0
            ;;
        wsl|linux)
            # Linux/WSL: /proc/meminfo MemTotal is in kB
            if [[ -f /proc/meminfo ]]; then
                local mem_kb
                mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null) || mem_kb=0
                if [[ "$mem_kb" =~ ^[0-9]+$ ]] && [[ "$mem_kb" -gt 0 ]]; then
                    mem_bytes=$((mem_kb * 1024))
                fi
            fi
            ;;
    esac

    # Fallback to 8GB if detection fails
    if [[ "$mem_bytes" -le 0 ]]; then
        mem_bytes=8589934592
    fi

    printf '%s' "$mem_bytes"
}

# Detect host CPU count
# Returns: CPU count via stdout
# Falls back to 2 if detection fails
_cai_detect_cpu_count() {
    local cpu_count=0

    case "$(_cai_detect_platform)" in
        macos)
            # macOS: sysctl hw.ncpu
            cpu_count=$(sysctl -n hw.ncpu 2>/dev/null) || cpu_count=0
            ;;
        wsl|linux)
            # Linux/WSL: nproc or /proc/cpuinfo
            if command -v nproc >/dev/null 2>&1; then
                cpu_count=$(nproc 2>/dev/null) || cpu_count=0
            elif [[ -f /proc/cpuinfo ]]; then
                cpu_count=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null) || cpu_count=0
            fi
            ;;
    esac

    # Fallback to 2 if detection fails
    if [[ "$cpu_count" -le 0 ]]; then
        cpu_count=2
    fi

    printf '%s' "$cpu_count"
}

# Detect host resources and compute container limits
# Arguments:
#   $1 = percentage of host resources (default: 50)
#   $2 = minimum memory in GB (default: 2)
#   $3 = minimum CPUs (default: 1)
# Outputs: JSON with detected_memory_gb, detected_cpus, container_memory, container_cpus
# Note: container_memory is in Docker format (e.g., "4g")
_cai_detect_resources() {
    local percentage="${1:-50}"
    local min_memory_gb="${2:-2}"
    local min_cpus="${3:-1}"

    local mem_bytes cpu_count
    mem_bytes=$(_cai_detect_memory_bytes)
    cpu_count=$(_cai_detect_cpu_count)

    # Convert to GB for display (integer)
    local detected_memory_gb
    detected_memory_gb=$((mem_bytes / 1073741824))
    if [[ "$detected_memory_gb" -le 0 ]]; then
        detected_memory_gb=8
    fi

    # Calculate container limits (percentage of host)
    local container_memory_gb container_cpus
    container_memory_gb=$((detected_memory_gb * percentage / 100))
    container_cpus=$((cpu_count * percentage / 100))

    # Apply minimums
    if [[ "$container_memory_gb" -lt "$min_memory_gb" ]]; then
        container_memory_gb="$min_memory_gb"
    fi
    if [[ "$container_cpus" -lt "$min_cpus" ]]; then
        container_cpus="$min_cpus"
    fi

    # Format memory for Docker (e.g., "4g")
    local container_memory="${container_memory_gb}g"

    # Output as shell-parseable format (not JSON for simplicity in bash)
    # Format: detected_memory_gb detected_cpus container_memory container_cpus
    printf '%s %s %s %s' "$detected_memory_gb" "$cpu_count" "$container_memory" "$container_cpus"
}

# Get default container memory limit
# Uses dynamic detection at 50% of host with 2GB minimum
# Returns: Memory limit in Docker format (e.g., "4g")
_cai_default_container_memory() {
    local resources
    resources=$(_cai_detect_resources 50 2 1)
    # Parse third field (container_memory)
    printf '%s' "$resources" | awk '{print $3}'
}

# Get default container CPU limit
# Uses dynamic detection at 50% of host with 1 CPU minimum
# Returns: CPU count (integer)
_cai_default_container_cpus() {
    local resources
    resources=$(_cai_detect_resources 50 2 1)
    # Parse fourth field (container_cpus)
    printf '%s' "$resources" | awk '{print $4}'
}

return 0
