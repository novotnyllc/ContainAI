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

return 0
