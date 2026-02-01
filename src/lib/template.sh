#!/usr/bin/env bash
# ==============================================================================
# ContainAI Template Library - Template directory management
# ==============================================================================
# This file must be sourced, not executed directly.
#
# First-use detection:
#   Use _cai_require_template() or _cai_template_exists_or_install() to access
#   templates with automatic installation of missing repo-shipped templates
#   (default, example-ml). This triggers "first-use" installation when a user
#   hasn't run setup or deleted a template.
#
# Provides:
#   _cai_require_template()        - Get template path with first-use auto-install (PRIMARY)
#   _cai_template_exists_or_install() - Check with first-use auto-install for repo templates
#   _cai_get_template_dir()        - Return path to templates directory
#   _cai_get_template_path()       - Return path to template Dockerfile (no auto-install)
#   _cai_ensure_template_dir()     - Create template directory if missing
#   _cai_template_exists()         - Check if a named template exists (no auto-install)
#   _cai_validate_template_name()  - Validate template name (no path traversal)
#   _cai_install_template()        - Install a single template from repo (if missing)
#   _cai_install_all_templates()   - Install all repo templates during setup
#   _cai_ensure_default_templates() - Install all missing default templates
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
#   - Uses _CAI_SCRIPT_DIR from containai.sh for repo source path
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

# Get path to template Dockerfile (simple path getter, no existence check)
# Args: template_name (defaults to "default")
# Outputs: path to Dockerfile (stdout, no newline)
# Returns: 0 on success, 1 if template name is invalid
# Note: Use _cai_require_template() for first-use auto-install behavior
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

# Check if a named template exists (without triggering first-use install)
# Args: template_name
# Returns: 0 if template Dockerfile exists, 1 otherwise
# Note: Use _cai_require_template() for first-use auto-install behavior
_cai_template_exists() {
    local template_name="${1:-default}"
    local template_path

    if ! _cai_validate_template_name "$template_name"; then
        return 1
    fi

    template_path="$_CAI_TEMPLATE_DIR/$template_name/Dockerfile"
    [[ -f "$template_path" ]]
}

# Check if template exists, auto-installing repo templates on first use
# This implements the "first-use detection" for repo-shipped templates
# Args: template_name
# Returns: 0 if template exists or was auto-installed, 1 otherwise
_cai_template_exists_or_install() {
    local template_name="${1:-default}"

    # If already exists, return success
    if _cai_template_exists "$template_name"; then
        return 0
    fi

    # Check if this is a repo-shipped template that can be auto-installed
    local entry
    for entry in "${_CAI_REPO_TEMPLATES[@]}"; do
        local name="${entry%%:*}"
        if [[ "$name" == "$template_name" ]]; then
            # First-use: auto-install missing repo template
            if _cai_install_template "$template_name" "false"; then
                return 0
            fi
            return 1
        fi
    done

    # Not a repo template and doesn't exist
    return 1
}

# Require a template to exist, triggering first-use installation if needed
# This is the main entry point for template access with first-use detection
# Args: template_name [dry_run]
# Returns: 0 if template exists or was installed, 1 on failure
# Outputs: path to template Dockerfile (stdout, no newline) on success
_cai_require_template() {
    local template_name="${1:-default}"
    local dry_run="${2:-false}"

    if ! _cai_validate_template_name "$template_name"; then
        _cai_error "Invalid template name: $template_name"
        return 1
    fi

    # First-use detection: install if missing
    if ! _cai_template_exists "$template_name"; then
        # Check if this is a repo-shipped template that can be auto-installed
        local entry found=""
        for entry in "${_CAI_REPO_TEMPLATES[@]}"; do
            local name="${entry%%:*}"
            if [[ "$name" == "$template_name" ]]; then
                found="true"
                break
            fi
        done

        if [[ "$found" == "true" ]]; then
            _cai_info "Template '$template_name' not found, installing from repo..."
            if ! _cai_install_template "$template_name" "$dry_run"; then
                _cai_error "Failed to install template '$template_name'"
                return 1
            fi
        else
            _cai_error "Template '$template_name' not found at $_CAI_TEMPLATE_DIR/$template_name/Dockerfile"
            _cai_error "Create a Dockerfile at that location or use a repo-shipped template (default, example-ml)"
            return 1
        fi
    fi

    printf '%s' "$_CAI_TEMPLATE_DIR/$template_name/Dockerfile"
}

# ==============================================================================
# Template Installation Functions
# ==============================================================================

# List of repo-shipped templates (name:source_file pairs)
# These are the templates that ship with ContainAI and can be restored
_CAI_REPO_TEMPLATES=("default:default.Dockerfile" "example-ml:example-ml.Dockerfile")

# Get the repo templates source directory
# Outputs: path to src/templates/ directory (stdout)
# Returns: 0 on success, 1 if not found
_cai_get_repo_templates_dir() {
    local templates_dir

    # Use _CAI_SCRIPT_DIR if available (set by containai.sh)
    if [[ -n "${_CAI_SCRIPT_DIR:-}" ]]; then
        templates_dir="$_CAI_SCRIPT_DIR/templates"
    else
        # Fallback: try to find relative to this file
        local script_dir
        script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        templates_dir="$(cd -- "$script_dir/.." && pwd)/templates"
    fi

    if [[ -d "$templates_dir" ]]; then
        printf '%s' "$templates_dir"
        return 0
    fi

    return 1
}

# Install a single template from repo to user config directory
# Args: template_name [dry_run]
# Returns: 0=installed/skipped, 1=error
# Skips if template already exists (preserves user customizations)
_cai_install_template() {
    local template_name="${1:-}"
    local dry_run="${2:-false}"
    local repo_dir source_file target_dir target_file

    if [[ -z "$template_name" ]]; then
        _cai_error "Template name required"
        return 1
    fi

    if ! _cai_validate_template_name "$template_name"; then
        _cai_error "Invalid template name: $template_name"
        return 1
    fi

    # Find the source file for this template
    local found_source=""
    local entry
    for entry in "${_CAI_REPO_TEMPLATES[@]}"; do
        local name="${entry%%:*}"
        local src="${entry#*:}"
        if [[ "$name" == "$template_name" ]]; then
            found_source="$src"
            break
        fi
    done

    if [[ -z "$found_source" ]]; then
        _cai_error "Template '$template_name' is not a repo-shipped template"
        return 1
    fi

    # Get repo templates directory
    if ! repo_dir=$(_cai_get_repo_templates_dir); then
        _cai_error "Cannot find repo templates directory"
        return 1
    fi

    source_file="$repo_dir/$found_source"
    if [[ ! -f "$source_file" ]]; then
        _cai_error "Source template not found: $source_file"
        return 1
    fi

    target_dir="$_CAI_TEMPLATE_DIR/$template_name"
    target_file="$target_dir/Dockerfile"

    # Skip if already exists (preserve user customizations)
    if [[ -f "$target_file" ]]; then
        _cai_debug "Template '$template_name' already exists, skipping"
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_dryrun "Would install template '$template_name' to $target_file"
        return 0
    fi

    # Create directory and copy file
    if ! mkdir -p "$target_dir" 2>/dev/null; then
        _cai_error "Failed to create template directory: $target_dir"
        return 1
    fi

    # Note: No -- before source_file since source_file is repo-controlled path
    # and template_name is validated (starts with alphanumeric, no dashes at start)
    if ! cp "$source_file" "$target_file"; then
        _cai_error "Failed to copy template: $source_file -> $target_file"
        return 1
    fi

    _cai_info "Installed template '$template_name' to $target_file"
    return 0
}

# Install all repo-shipped templates during setup
# Args: [dry_run]
# Returns: 0 on success, 1 on failure
# Skips templates that already exist (preserves user customizations)
_cai_install_all_templates() {
    local dry_run="${1:-false}"
    local entry name result=0

    for entry in "${_CAI_REPO_TEMPLATES[@]}"; do
        name="${entry%%:*}"
        if ! _cai_install_template "$name" "$dry_run"; then
            result=1
        fi
    done

    return $result
}

# First-use detection: ensure default templates are installed
# Called during container creation if templates are missing
# Args: [dry_run]
# Returns: 0 on success (all templates installed or already exist)
#          1 on failure (at least one required template could not be installed)
# Logs warning for each failed template but continues trying others
_cai_ensure_default_templates() {
    local dry_run="${1:-false}"
    local entry name failed="false"

    for entry in "${_CAI_REPO_TEMPLATES[@]}"; do
        name="${entry%%:*}"
        if ! _cai_template_exists "$name"; then
            if ! _cai_install_template "$name" "$dry_run"; then
                _cai_warn "Failed to install missing template '$name'"
                failed="true"
            fi
        fi
    done

    if [[ "$failed" == "true" ]]; then
        return 1
    fi

    return 0
}
