#!/usr/bin/env bash
# ==============================================================================
# ContainAI Core Library - Logging, error handling, utility functions
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_info()     - Info message (stdout)
#   _cai_warn()     - Warning message (stderr)
#   _cai_error()    - Error message (stderr)
#   _cai_debug()    - Debug message (stderr, only when CONTAINAI_DEBUG=1)
#   _cai_ok()       - Success message (stdout)
#   _cai_step()     - Step progress message (stdout)
#
# Output format:
#   [INFO] message   - Informational
#   [OK] message     - Success/completion
#   [WARN] message   - Warning (stderr)
#   [ERROR] message  - Error (stderr)
#   [DEBUG] message  - Debug (stderr, when enabled)
#
# Usage: source lib/core.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/core.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/core.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/core.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_CORE_LOADED:-}" ]]; then
    return 0
fi
_CAI_CORE_LOADED=1

# ==============================================================================
# Logging functions - ASCII markers per memory convention
# ==============================================================================

# Info message (stdout)
# Uses printf to avoid echo mis-handling messages starting with -n/-e
_cai_info() {
    printf '%s\n' "[INFO] $*"
}

# Success message (stdout)
_cai_ok() {
    printf '%s\n' "[OK] $*"
}

# Warning message (stderr)
_cai_warn() {
    printf '%s\n' "[WARN] $*" >&2
}

# Error message (stderr)
_cai_error() {
    printf '%s\n' "[ERROR] $*" >&2
}

# Debug message (stderr, only when CONTAINAI_DEBUG=1)
_cai_debug() {
    if [[ "${CONTAINAI_DEBUG:-0}" == "1" ]]; then
        printf '%s\n' "[DEBUG] $*" >&2
    fi
}

# Step progress message (stdout)
_cai_step() {
    printf '%s\n' "-> $*"
}

# ==============================================================================
# Utility functions
# ==============================================================================

# Check if a command exists using 'command -v' (per memory convention - not 'which')
# Arguments: $1 = command name
# Returns: 0=exists, 1=not found
_cai_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Require a command to exist, exit with error if not
# Arguments: $1 = command name, $2 = optional error context
# Returns: 0 if exists, 1 if missing (with error message)
_cai_require_command() {
    local cmd="$1"
    local context="${2:-}"

    if ! _cai_command_exists "$cmd"; then
        if [[ -n "$context" ]]; then
            _cai_error "$cmd is required for $context"
        else
            _cai_error "$cmd is not installed or not in PATH"
        fi
        return 1
    fi
    return 0
}

return 0
