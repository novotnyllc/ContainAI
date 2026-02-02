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
#   _cai_ensure_base_image()       - Check/pull base image with user prompt
#   _cai_build_template()          - Build template Dockerfile using Docker context
#   _cai_get_template_image_name() - Get image name for a template (no build)
#   _cai_validate_template_base()  - Validate Dockerfile FROM uses ContainAI base
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
#   - Requires lib/registry.sh for _cai_base_image() and registry helpers
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

# Validate template name to prevent path traversal and Docker build failures
# Pattern: ^[a-z0-9][a-z0-9_.-]*$ (lowercase only - Docker repos must be lowercase)
# Rejects: empty, slashes, .., uppercase, or names not matching safe pattern
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

    # Check pattern: must start with lowercase alphanumeric, followed by lowercase alphanumeric, underscore, dot, or dash
    # Lowercase only because template names are used in Docker image repo names (containai-template-{name}:local)
    # and Docker repository names must be lowercase
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9_.-]*$ ]]; then
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

# ==============================================================================
# Base Image Management
# ==============================================================================

# Ensure ContainAI base image is available locally, prompting user if needed
# Args: $1 = docker_context (optional)
# Returns: 0 if image is available (or pulled), 1 if user declined or error
# Note: Uses _cai_base_image() from registry.sh to get channel-aware base image
# Note: In non-interactive mode without CAI_YES, exits with error
_cai_ensure_base_image() {
    local docker_context="${1:-}"
    local base_image

    # Get the base image for current channel
    if command -v _cai_base_image >/dev/null 2>&1; then
        base_image=$(_cai_base_image)
    else
        # Fallback if registry.sh not loaded
        base_image="ghcr.io/novotnyllc/containai:latest"
    fi

    # Build docker command
    local -a docker_cmd=(docker)
    if [[ -n "$docker_context" ]]; then
        docker_cmd=(docker --context "$docker_context")
    fi

    # Check if image exists locally
    # Clear DOCKER_HOST/DOCKER_CONTEXT to make --context flag authoritative
    if DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" image inspect "$base_image" >/dev/null 2>&1; then
        # Image exists locally - freshness check is done in container.sh after template build
        _cai_debug "Base image '$base_image' found locally"
        return 0
    fi

    # Image not present - need to prompt user
    _cai_notice "No local ContainAI base image found."

    # Try to get metadata from registry (for size/date display)
    local metadata size_str created_str
    if command -v _cai_ghcr_image_metadata >/dev/null 2>&1; then
        if metadata=$(_cai_ghcr_image_metadata "$base_image" 2>/dev/null); then
            local size_bytes created_raw
            size_bytes=$(printf '%s' "$metadata" | python3 -c "import sys,json; print(json.load(sys.stdin).get('size',0))" 2>/dev/null) || size_bytes=0
            created_raw=$(printf '%s' "$metadata" | python3 -c "import sys,json; print(json.load(sys.stdin).get('created',''))" 2>/dev/null) || created_raw=""
            if [[ "$size_bytes" -gt 0 ]] && command -v _cai_format_size >/dev/null 2>&1; then
                size_str=$(_cai_format_size "$size_bytes")
            fi
            # Format created date (extract YYYY-MM-DD from ISO format)
            if [[ -n "$created_raw" ]]; then
                created_str="${created_raw:0:10}"  # First 10 chars: YYYY-MM-DD
            fi
        fi
    fi

    # Display image info
    printf '%s\n' "         Image: $base_image" >&2
    if [[ -n "${size_str:-}" ]]; then
        printf '%s\n' "         Size: $size_str (compressed)" >&2
    fi
    if [[ -n "${created_str:-}" ]]; then
        printf '%s\n' "         Published: $created_str" >&2
    fi
    printf '\n' >&2

    # Build the manual pull command (include context if set)
    local pull_cmd
    if [[ -n "$docker_context" ]]; then
        pull_cmd="docker --context $docker_context pull $base_image"
    else
        pull_cmd="docker pull $base_image"
    fi

    # Check if we can prompt for confirmation
    # CAI_YES=1 means auto-confirm
    if [[ "${CAI_YES:-}" == "1" ]]; then
        _cai_info "Pulling base image (CAI_YES=1)..."
        if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" pull "$base_image"; then
            _cai_error "Failed to pull base image: $base_image"
            return 1
        fi
        return 0
    fi

    # Check for non-interactive mode
    if [[ ! -t 0 ]] && { [[ ! -e /dev/tty ]] || ! : < /dev/tty 2>/dev/null; }; then
        _cai_error "Non-interactive mode: cannot prompt for base image pull"
        _cai_error "Set CAI_YES=1 to auto-confirm, or pull the image manually:"
        _cai_error "  $pull_cmd"
        return 1
    fi

    # Prompt user for confirmation (default yes)
    if _cai_prompt_confirm "Pull image?" "true"; then
        _cai_info "Pulling base image..."
        if ! DOCKER_CONTEXT= DOCKER_HOST= "${docker_cmd[@]}" pull "$base_image"; then
            _cai_error "Failed to pull base image: $base_image"
            return 1
        fi
        _cai_ok "Base image pulled successfully"
        return 0
    else
        _cai_error "Base image required for template build"
        _cai_error "Pull the image manually and try again:"
        _cai_error "  $pull_cmd"
        return 1
    fi
}

# ==============================================================================
# Template Build Functions
# ==============================================================================

# Build a template Dockerfile and return the image name
# Uses the same Docker context as container creation for consistency
# Args: template_name [docker_context] [dry_run] [suppress_base_warning]
#   template_name          - Name of the template (e.g., "default", "my-custom")
#   docker_context         - Docker context to use (optional, uses default if empty)
#   dry_run                - If "true", outputs TEMPLATE_BUILD_CMD instead of building
#   suppress_base_warning  - If "true", suppress base image validation warnings
# Returns: 0 on success, 1 on failure
# Outputs: Image name (stdout) on success: containai-template-{name}:local
# Note: For dry-run mode, outputs TEMPLATE_BUILD_CMD=<command> to stdout
#       The command is shell-escaped and includes env var clearing prefix
# Note: Validates that Dockerfile uses ContainAI base image; warns if not
# Note: Prompts to pull base image if not present locally
_cai_build_template() {
    local template_name="${1:-default}"
    local docker_context="${2:-}"
    local dry_run="${3:-false}"
    local suppress_base_warning="${4:-false}"

    # Validate template name
    if ! _cai_validate_template_name "$template_name"; then
        _cai_error "Invalid template name: $template_name"
        return 1
    fi

    # Get template Dockerfile path (triggers first-use install if needed)
    local dockerfile_path
    if ! dockerfile_path=$(_cai_require_template "$template_name" "$dry_run"); then
        return 1
    fi

    # Validate layer stack (warn if not based on ContainAI, unless suppressed)
    # This is a warning only - we proceed with build regardless of result
    # Return code 2 (parse error) is logged but doesn't block build
    if [[ "$dry_run" != "true" ]]; then
        _cai_validate_template_base "$dockerfile_path" "$suppress_base_warning" || true
    fi

    # Template directory is the build context (parent of Dockerfile)
    local template_dir
    template_dir="$(dirname "$dockerfile_path")"

    # Image tag: containai-template-{name}:local
    local image_tag="containai-template-${template_name}:local"

    # Build docker command array based on context
    local -a docker_cmd=(docker)
    if [[ -n "$docker_context" ]]; then
        docker_cmd=(docker --context "$docker_context")
    fi

    # Check if base image needs to be pulled (not in dry-run mode)
    if [[ "$dry_run" != "true" ]]; then
        if ! _cai_ensure_base_image "$docker_context"; then
            return 1
        fi
    fi

    # Construct the build command
    local -a build_args=("${docker_cmd[@]}" build -t "$image_tag" "$template_dir")

    # Handle dry-run mode
    if [[ "$dry_run" == "true" ]]; then
        # Output machine-parseable format with proper shell escaping
        # Use printf %q to escape each argument, preserving argument boundaries
        local build_cmd_str=""
        local arg
        for arg in "${build_args[@]}"; do
            if [[ -n "$build_cmd_str" ]]; then
                build_cmd_str+=" "
            fi
            # Use printf %q to shell-escape each argument
            build_cmd_str+=$(printf '%q' "$arg")
        done
        # Include env var clearing prefix to match actual execution
        printf '%s\n' "TEMPLATE_BUILD_CMD=DOCKER_CONTEXT= DOCKER_HOST= $build_cmd_str"
        printf '%s\n' "TEMPLATE_IMAGE=$image_tag"
        printf '%s\n' "TEMPLATE_NAME=$template_name"
        return 0
    fi

    # Build the template
    _cai_info "Building template '$template_name'..."
    # Clear DOCKER_HOST/DOCKER_CONTEXT to make --context flag authoritative
    # Stream output directly on failure to avoid memory issues with large builds
    local build_rc
    if DOCKER_CONTEXT= DOCKER_HOST= "${build_args[@]}" >/dev/null 2>&1; then
        build_rc=0
    else
        build_rc=$?
    fi

    if [[ $build_rc -ne 0 ]]; then
        _cai_error "Failed to build template '$template_name' (exit code: $build_rc)"
        _cai_error "Re-running build to show output:"
        # Re-run with output visible for debugging (output goes to stderr)
        DOCKER_CONTEXT= DOCKER_HOST= "${build_args[@]}" >&2 || true
        return 1
    fi

    _cai_info "Template '$template_name' built successfully: $image_tag"

    # Output the image name for use by caller
    printf '%s' "$image_tag"
    return 0
}

# Get the template image name without building
# Useful for checking if a template image exists or for label creation
# Args: template_name
# Returns: 0 on success, 1 if template name is invalid
# Outputs: Image name (stdout): containai-template-{name}:local
_cai_get_template_image_name() {
    local template_name="${1:-default}"

    if ! _cai_validate_template_name "$template_name"; then
        _cai_error "Invalid template name: $template_name"
        return 1
    fi

    printf '%s' "containai-template-${template_name}:local"
}

# ==============================================================================
# Layer Stack Validation
# ==============================================================================

# Validate that template Dockerfile is based on ContainAI images
# Parses FROM line with ARG variable substitution
# Args: dockerfile_path [suppress_warning]
#   dockerfile_path    - Path to Dockerfile to validate
#   suppress_warning   - If "true", suppress warning output (config-driven)
# Returns: 0 if valid ContainAI base, 1 if invalid/unresolved, 2 if parse error
# Outputs: Warning message to stderr if invalid (unless suppressed)
#
# Accepted patterns:
#   - containai:*
#   - ghcr.io/novotnyllc/containai*
#   - containai-template-*:local (chained templates)
#
# Handles ARG substitution for patterns like:
#   ARG BASE_IMAGE=ghcr.io/novotnyllc/containai:latest
#   FROM $BASE_IMAGE
_cai_validate_template_base() {
    local dockerfile_path="${1:-}"
    local suppress_warning="${2:-false}"

    if [[ -z "$dockerfile_path" ]]; then
        _cai_error "Dockerfile path required"
        return 2
    fi

    if [[ ! -f "$dockerfile_path" ]]; then
        _cai_error "Dockerfile not found: $dockerfile_path"
        return 2
    fi

    # Parse Dockerfile to collect ARG values and find FROM line
    # We only care about the first FROM (base stage)
    local -A arg_values=()
    local from_line=""
    local line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" == \#* ]] && continue

        # Parse ARG lines: ARG NAME or ARG NAME=value
        if [[ "$line" =~ ^[Aa][Rr][Gg][[:space:]]+([A-Za-z_][A-Za-z0-9_]*)([[:space:]]*=[[:space:]]*(.*))? ]]; then
            key="${BASH_REMATCH[1]}"
            # Value is in capture group 3 (after the = sign)
            value="${BASH_REMATCH[3]:-}"
            # Remove quotes if present (simple case)
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            arg_values["$key"]="$value"
            continue
        fi

        # Parse FROM line (first one wins - this is the base image)
        # Handle: FROM image, FROM --platform=x image, FROM image AS stage
        if [[ "$line" =~ ^[Ff][Rr][Oo][Mm][[:space:]]+ ]]; then
            # Extract tokens after FROM
            local from_tokens="${line#*[Ff][Rr][Oo][Mm]}"
            from_tokens="${from_tokens#"${from_tokens%%[![:space:]]*}"}"  # trim leading
            # Skip --flag tokens and find the image
            local token
            while [[ -n "$from_tokens" ]]; do
                # Get first token
                token="${from_tokens%%[[:space:]]*}"
                # Advance to next token
                from_tokens="${from_tokens#"$token"}"
                from_tokens="${from_tokens#"${from_tokens%%[![:space:]]*}"}"
                # Skip flags (start with --)
                if [[ "$token" == --* ]]; then
                    continue
                fi
                # Found the image - stop at AS keyword
                if [[ "$token" == [Aa][Ss] ]]; then
                    break
                fi
                from_line="$token"
                break
            done
            [[ -n "$from_line" ]] && break
        fi
    done < "$dockerfile_path"

    # Check if we found a FROM line
    if [[ -z "$from_line" ]]; then
        _cai_error "No FROM line found in Dockerfile: $dockerfile_path"
        return 2
    fi

    # Resolve variable substitution in FROM line
    # Handles: $VAR, ${VAR}, ${VAR:-default}
    local resolved_image="$from_line"
    local var_name var_default has_unresolved="false" match replacement

    # Process ${VAR:-default} patterns first
    while [[ "$resolved_image" =~ \$\{([A-Za-z_][A-Za-z0-9_]*):-([^}]*)\} ]]; do
        match="${BASH_REMATCH[0]}"
        var_name="${BASH_REMATCH[1]}"
        var_default="${BASH_REMATCH[2]}"
        if [[ -n "${arg_values[$var_name]:-}" ]]; then
            replacement="${arg_values[$var_name]}"
        else
            replacement="$var_default"
        fi
        resolved_image="${resolved_image/"$match"/"$replacement"}"
    done

    # Process ${VAR} patterns
    while [[ "$resolved_image" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
        match="${BASH_REMATCH[0]}"
        var_name="${BASH_REMATCH[1]}"
        if [[ -n "${arg_values[$var_name]:-}" ]]; then
            replacement="${arg_values[$var_name]}"
            resolved_image="${resolved_image/"$match"/"$replacement"}"
        else
            has_unresolved="true"
            break
        fi
    done

    # Process $VAR patterns (without braces)
    while [[ "$resolved_image" =~ \$([A-Za-z_][A-Za-z0-9_]*) ]]; do
        match="${BASH_REMATCH[0]}"
        var_name="${BASH_REMATCH[1]}"
        if [[ -n "${arg_values[$var_name]:-}" ]]; then
            replacement="${arg_values[$var_name]}"
            resolved_image="${resolved_image/"$match"/"$replacement"}"
        else
            has_unresolved="true"
            break
        fi
    done

    # Check for unresolved variables
    if [[ "$has_unresolved" == "true" ]]; then
        if [[ "$suppress_warning" != "true" ]]; then
            cat >&2 <<'EOF'
[WARN] Your template uses an unresolved variable in FROM.
       Cannot validate if it's based on ContainAI images.
       ENTRYPOINT must not be overridden or systemd won't start.

       To suppress this warning, add to config.toml:
       [template]
       suppress_base_warning = true
EOF
        fi
        return 1
    fi

    # Check if resolved image matches ContainAI patterns
    # Patterns: containai:*, ghcr.io/novotnyllc/containai*, containai-template-*:local
    local is_valid="false"

    # Pattern 1: containai:* (local shorthand)
    if [[ "$resolved_image" =~ ^containai: ]]; then
        is_valid="true"
    fi

    # Pattern 2: ghcr.io/novotnyllc/containai*
    if [[ "$resolved_image" =~ ^ghcr\.io/novotnyllc/containai ]]; then
        is_valid="true"
    fi

    # Pattern 3: containai-template-*:local (chained templates)
    if [[ "$resolved_image" =~ ^containai-template-[a-zA-Z0-9_.-]+:local$ ]]; then
        is_valid="true"
    fi

    if [[ "$is_valid" == "true" ]]; then
        return 0
    fi

    # Invalid base image - emit warning
    if [[ "$suppress_warning" != "true" ]]; then
        cat >&2 <<'EOF'
[WARN] Your template is not based on ContainAI images.
       ContainAI features (systemd, agents, init) may not work.
       ENTRYPOINT must not be overridden or systemd won't start.

       To suppress this warning, add to config.toml:
       [template]
       suppress_base_warning = true
EOF
    fi
    return 1
}
