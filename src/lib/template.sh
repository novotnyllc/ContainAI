#!/usr/bin/env bash
# ==============================================================================
# ContainAI Template Library - Template directory management
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_get_template_dir()       - Return path to templates directory
#   _cai_get_template_path()      - Return path to template Dockerfile
#   _cai_ensure_template_dir()    - Create template directory if missing
#   _cai_template_exists()        - Check if a named template exists
#   _cai_validate_template_name() - Validate template name (no path traversal)
#
# Template directory structure:
#   ~/.config/containai/templates/
#   ├── default/
#   │   └── Dockerfile
#   └── my-custom/
#       └── Dockerfile
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
#   - Requires lib/ssh.sh for _CAI_CONFIG_DIR constant
#
# Usage: source lib/template.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "[ERROR] lib/template.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s\n' "[ERROR] lib/template.sh must be sourced, not executed directly" >&2
    printf '%s\n' "Usage: source lib/template.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_TEMPLATE_LOADED:-}" ]]; then
    return 0
fi
_CAI_TEMPLATE_LOADED=1

# ==============================================================================
# Constants
# ==============================================================================

# Template directory path (uses _CAI_CONFIG_DIR from ssh.sh if available)
_CAI_TEMPLATE_DIR="${_CAI_CONFIG_DIR:-$HOME/.config/containai}/templates"

# ==============================================================================
# Template Name Validation
# ==============================================================================

# Validate template name to prevent path traversal
# Pattern: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
# Rejects: empty, slashes, .., or names not matching safe pattern
# Returns: 0=valid, 1=invalid
_cai_validate_template_name() {
    local name="${1:-}"

    # Check empty
    if [[ -z "$name" ]]; then
        return 1
    fi

    # Check for path traversal attempts
    if [[ "$name" == */* ]] || [[ "$name" == ".." ]] || [[ "$name" == "." ]]; then
        return 1
    fi

    # Check pattern: must start with alphanumeric, followed by alphanumeric, underscore, dot, or dash
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# Template Path Functions
# ==============================================================================

# Get path to templates directory
# Outputs: path to templates directory (stdout, no newline)
_cai_get_template_dir() {
    printf '%s' "$_CAI_TEMPLATE_DIR"
}

# Get path to template Dockerfile
# Args: template_name (defaults to "default")
# Outputs: path to Dockerfile (stdout, no newline)
# Returns: 0 on success, 1 if template name is invalid
_cai_get_template_path() {
    local template_name="${1:-default}"

    if ! _cai_validate_template_name "$template_name"; then
        _cai_error "Invalid template name: $template_name"
        return 1
    fi

    printf '%s' "$_CAI_TEMPLATE_DIR/$template_name/Dockerfile"
}

# Ensure template directory exists
# Args: template_name (optional, creates only base dir if not specified)
# Returns: 0 on success, 1 on failure
_cai_ensure_template_dir() {
    local template_name="${1:-}"
    local target_dir

    if [[ -n "$template_name" ]]; then
        if ! _cai_validate_template_name "$template_name"; then
            _cai_error "Invalid template name: $template_name"
            return 1
        fi
        target_dir="$_CAI_TEMPLATE_DIR/$template_name"
    else
        target_dir="$_CAI_TEMPLATE_DIR"
    fi

    if [[ -d "$target_dir" ]]; then
        return 0
    fi

    if ! mkdir -p "$target_dir" 2>/dev/null; then
        _cai_error "Failed to create template directory: $target_dir"
        return 1
    fi

    _cai_debug "Created template directory: $target_dir"
    return 0
}

# Check if a named template exists
# Args: template_name
# Returns: 0 if template Dockerfile exists, 1 otherwise
_cai_template_exists() {
    local template_name="${1:-default}"
    local template_path

    if ! _cai_validate_template_name "$template_name"; then
        return 1
    fi

    template_path="$_CAI_TEMPLATE_DIR/$template_name/Dockerfile"
    [[ -f "$template_path" ]]
}
