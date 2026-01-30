#!/usr/bin/env bash
# ==============================================================================
# ContainAI Core Library - Logging, error handling, utility functions
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_info()     - Info message (stderr, only when verbose)
#   _cai_warn()     - Warning message (stderr, always)
#   _cai_error()    - Error message (stderr, always)
#   _cai_debug()    - Debug message (stderr, only when CONTAINAI_DEBUG=1)
#   _cai_ok()       - Success message (stderr, only when verbose)
#   _cai_step()     - Step progress message (stderr, only when verbose)
#   _cai_set_verbose() - Enable verbose output
#   _cai_set_quiet()   - Enable quiet mode (overrides verbose)
#   _cai_is_verbose()  - Check if verbose output is enabled
#   _cai_prompt_confirm() - Prompt for user confirmation with CAI_YES support
#
# Output format:
#   [INFO] message   - Informational (stderr, verbose only)
#   [OK] message     - Success/completion (stderr, verbose only)
#   -> message       - Step progress (stderr, verbose only)
#   [WARN] message   - Warning (stderr, always)
#   [ERROR] message  - Error (stderr, always)
#   [DEBUG] message  - Debug (stderr, when enabled)
#
# Verbosity precedence:
#   1. _CAI_QUIET=1 overrides everything (--quiet wins)
#   2. _CAI_VERBOSE=1 enables verbose output (--verbose)
#   3. CONTAINAI_VERBOSE=1 env var fallback
#
# Usage: source lib/core.sh
# ==============================================================================

# Require bash 4+ (before using BASH_SOURCE and bash 4 features like ${var,,})
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/core.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    echo "[ERROR] lib/core.sh requires bash 4.0 or later (found $BASH_VERSION)" >&2
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
# Verbose/Quiet State Management
# ==============================================================================

# Global state variables (reset at each containai() invocation)
_CAI_VERBOSE=""
_CAI_QUIET=""

# Enable verbose output
_cai_set_verbose() { _CAI_VERBOSE=1; }

# Enable quiet mode (overrides verbose)
_cai_set_quiet() { _CAI_QUIET=1; }

# Check if verbose output is enabled
# Precedence: quiet > verbose > CONTAINAI_VERBOSE env var
_cai_is_verbose() {
    [[ "${_CAI_QUIET:-}" == "1" ]] && return 1  # --quiet wins
    [[ "${_CAI_VERBOSE:-}" == "1" ]] || [[ "${CONTAINAI_VERBOSE:-}" == "1" ]]
}

# ==============================================================================
# Logging functions - ASCII markers per memory convention
# ==============================================================================

# Info message (stderr, only when verbose)
# Uses printf to avoid echo mis-handling messages starting with -n/-e
_cai_info() {
    _cai_is_verbose || return 0
    printf '%s\n' "[INFO] $*" >&2
}

# Success message (stderr, only when verbose)
_cai_ok() {
    _cai_is_verbose || return 0
    printf '%s\n' "[OK] $*" >&2
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

# Step progress message (stderr, only when verbose)
_cai_step() {
    _cai_is_verbose || return 0
    printf '%s\n' "-> $*" >&2
}

# Dry-run message (stderr, always emits - users need to see what would happen)
_cai_dryrun() {
    printf '%s\n' "[INFO] [DRY-RUN] $*" >&2
}

# Spacing newline (stderr, only when verbose)
# Use this instead of raw `printf '\n'` in setup/update flows
_cai_spacing() {
    _cai_is_verbose || return 0
    printf '\n' >&2
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

# ==============================================================================
# User Interaction
# ==============================================================================

# Prompt user for confirmation with CAI_YES support
# Arguments: $1 = message
#            $2 = default_yes ("true" for default Y, otherwise default N)
# Returns: 0 if confirmed, 1 if denied
# Honors CAI_YES=1 for non-interactive mode
# Reads from /dev/tty when stdin is a pipe (for curl|bash installs)
_cai_prompt_confirm() {
    local message="$1"
    local default_yes="${2:-false}"
    local prompt_suffix confirm

    # Auto-confirm if CAI_YES=1
    if [[ "${CAI_YES:-}" == "1" ]]; then
        return 0
    fi

    if [[ "$default_yes" == "true" ]]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi

    # Try /dev/tty for piped stdin (curl|bash installs)
    # Test /dev/tty is usable before relying on it (cron/CI may not have a controlling TTY)
    if [[ ! -t 0 ]] && [[ -e /dev/tty ]] && : < /dev/tty 2>/dev/null; then
        # Write prompt to /dev/tty too, so it's visible even if stdout is redirected
        printf '%s %s ' "$message" "$prompt_suffix" > /dev/tty 2>/dev/null || true
        if ! read -r confirm < /dev/tty; then
            # EOF on /dev/tty
            return 1
        fi
    elif [[ -t 0 ]]; then
        printf '%s %s ' "$message" "$prompt_suffix"
        if ! read -r confirm; then
            # EOF on stdin
            return 1
        fi
    else
        # No TTY available, can't prompt
        return 1
    fi

    # Normalize input: trim whitespace, lowercase
    confirm="${confirm,,}"     # lowercase (bash 4+)
    confirm="${confirm//[[:space:]]/}"  # strip whitespace

    # Evaluate response based on default
    # Only accept explicit y/yes/n/no/empty - reject ambiguous input like "maybe"
    if [[ "$default_yes" == "true" ]]; then
        # Default Y: empty/y/yes confirms, n/no denies, other input denies (safe default)
        case "$confirm" in
            ""|y|yes) return 0 ;;
            n|no)     return 1 ;;
            *)        return 1 ;;  # Ambiguous input defaults to deny for safety
        esac
    else
        # Default N: y/yes confirms, empty/n/no/other denies
        case "$confirm" in
            y|yes) return 0 ;;
            *)     return 1 ;;
        esac
    fi
}

return 0
