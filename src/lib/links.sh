#!/usr/bin/env bash
# ==============================================================================
# ContainAI Links - cai links subcommand
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _containai_links_check - Verify container symlinks match link-spec.json
#   _containai_links_fix   - Repair broken/missing symlinks in container
#
# Usage:
#   source lib/links.sh
#   _containai_links_check "container-name" "context"
#   _containai_links_fix "container-name" "context"
#
# The actual link verification and repair runs inside the container via SSH,
# using /usr/local/lib/containai/link-repair.sh which is shipped in the image.
#
# Dependencies:
#   - docker (for container inspection)
#   - ssh.sh (_cai_ssh_run for remote execution)
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "[ERROR] lib/links.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    printf '%s\n' "[ERROR] lib/links.sh must be sourced, not executed directly" >&2
    printf '%s\n' "Usage: source lib/links.sh" >&2
    exit 1
fi

# ==============================================================================
# Output helpers
# ==============================================================================
_links_info() {
    # Delegate to _cai_info for verbose gating; fallback if not available
    if declare -f _cai_info >/dev/null 2>&1; then
        _cai_info "$@"
    else
        printf '%s\n' "[INFO] $*" >&2
    fi
}
_links_error() { printf '%s\n' "[ERROR] $*" >&2; }
_links_warn() { printf '%s\n' "[WARN] $*" >&2; }

# ==============================================================================
# Container resolution helpers
# ==============================================================================

# Resolve container name from workspace path
# If container_name is provided, validates it exists
# If not provided, resolves from workspace using shared lookup (label → new name → legacy hash)
# Arguments:
#   $1 = container name (optional, empty for auto-resolution)
#   $2 = workspace path (required if container_name empty)
#   $3 = docker context (optional)
# Returns: 0 on success, 1 on failure
# Outputs: container name to stdout
_links_resolve_container() {
    local container_name="$1"
    local workspace="$2"
    local context="${3:-}"

    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    if [[ -n "$container_name" ]]; then
        # Validate container exists
        if ! "${docker_cmd[@]}" inspect --type container "$container_name" >/dev/null 2>&1; then
            _links_error "Container not found: $container_name"
            return 1
        fi
        printf '%s' "$container_name"
        return 0
    fi

    # Resolve from workspace
    if [[ -z "$workspace" ]]; then
        _links_error "Either container name or workspace path is required"
        return 1
    fi

    # Try to find container by workspace label first
    local label_filter="containai.workspace=$workspace"
    local found_containers
    found_containers=$("${docker_cmd[@]}" ps -aq --filter "label=$label_filter" 2>/dev/null | head -2)

    if [[ -n "$found_containers" ]]; then
        local match_count
        match_count=$(printf '%s\n' "$found_containers" | grep -c . || echo 0)
        if [[ "$match_count" -gt 1 ]]; then
            _links_error "Multiple containers found for workspace: $workspace"
            return 1
        fi
        local first_container
        first_container=$(printf '%s\n' "$found_containers" | head -1)
        container_name=$("${docker_cmd[@]}" inspect --format '{{.Name}}' "$first_container" 2>/dev/null)
        container_name="${container_name#/}"
        printf '%s' "$container_name"
        return 0
    fi

    # Fallback: use shared lookup order (label → new name → legacy hash)
    local find_rc
    if container_name=$(_cai_find_workspace_container "$workspace" "$context"); then
        printf '%s' "$container_name"
        return 0
    fi
    find_rc=$?
    if [[ $find_rc -eq 2 ]]; then
        # Multiple containers error already printed by _cai_find_workspace_container
        return 1
    fi
    _links_error "No container found for workspace: $workspace"
    _links_error "Start a container first with: cai shell $workspace"
    return 1
}

# Check if container is running, start it if stopped (for fix operations)
# Arguments:
#   $1 = container name
#   $2 = docker context (optional)
#   $3 = start_if_stopped ("true" to start stopped containers)
# Returns: 0 if running, 1 if cannot proceed
_links_ensure_container_running() {
    local container_name="$1"
    local context="${2:-}"
    local start_if_stopped="${3:-false}"

    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    local container_state
    container_state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' -- "$container_name" 2>/dev/null)

    if [[ "$container_state" == "running" ]]; then
        return 0
    fi

    if [[ "$start_if_stopped" == "true" ]]; then
        _links_info "Container '$container_name' is not running (state: $container_state), starting..."
        if ! "${docker_cmd[@]}" start "$container_name" >/dev/null 2>&1; then
            _links_error "Failed to start container: $container_name"
            return 1
        fi
        # Wait briefly for container to initialize
        sleep 1
        return 0
    fi

    _links_error "Container '$container_name' is not running (state: $container_state)"
    _links_error "Start the container first with: cai shell"
    return 1
}

# ==============================================================================
# Main link operations
# ==============================================================================

# Check symlinks in container against link-spec.json
# Runs /usr/local/lib/containai/link-repair.sh --check in the container via SSH
# Arguments:
#   $1 = container name
#   $2 = docker context (optional)
#   $3 = quiet ("true" to suppress output)
# Returns: 0 if all links OK, 1 if issues found
_containai_links_check() {
    local container_name="$1"
    local context="${2:-}"
    local quiet="${3:-false}"

    # Ensure _cai_ssh_run is available
    if ! declare -f _cai_ssh_run >/dev/null 2>&1; then
        _links_error "_cai_ssh_run not found - ssh.sh not loaded"
        return 1
    fi

    # Ensure container is running
    if ! _links_ensure_container_running "$container_name" "$context" "false"; then
        return 1
    fi

    # Build command to run in container
    local -a check_cmd=(/usr/local/lib/containai/link-repair.sh --check)
    if [[ "$quiet" == "true" ]]; then
        check_cmd+=(--quiet)
    fi

    # Run via SSH
    # _cai_ssh_run args: container_name context force_update quiet detached allocate_tty [--login-shell] cmd...
    local ssh_output ssh_exit_code
    if ssh_output=$(_cai_ssh_run "$container_name" "$context" "false" "$quiet" "false" "false" "${check_cmd[@]}" 2>&1); then
        ssh_exit_code=0
    else
        ssh_exit_code=$?
    fi

    # Output results (unless quiet)
    if [[ "$quiet" != "true" && -n "$ssh_output" ]]; then
        printf '%s\n' "$ssh_output"
    fi

    # Return exit code from link-repair.sh
    # 0 = all links OK, 1 = issues found or errors occurred
    return $ssh_exit_code
}

# Fix symlinks in container based on link-spec.json
# Runs /usr/local/lib/containai/link-repair.sh --fix in the container via SSH
# Arguments:
#   $1 = container name
#   $2 = docker context (optional)
#   $3 = quiet ("true" to suppress output)
#   $4 = dry_run ("true" to show what would be fixed without making changes)
# Returns: 0 on success, 1 on errors
_containai_links_fix() {
    local container_name="$1"
    local context="${2:-}"
    local quiet="${3:-false}"
    local dry_run="${4:-false}"

    # Ensure _cai_ssh_run is available
    if ! declare -f _cai_ssh_run >/dev/null 2>&1; then
        _links_error "_cai_ssh_run not found - ssh.sh not loaded"
        return 1
    fi

    # Ensure container is running (start if stopped for fix operations)
    if ! _links_ensure_container_running "$container_name" "$context" "true"; then
        return 1
    fi

    # Build command to run in container
    local -a fix_cmd=(/usr/local/lib/containai/link-repair.sh)
    if [[ "$dry_run" == "true" ]]; then
        fix_cmd+=(--dry-run)
    else
        fix_cmd+=(--fix)
    fi
    if [[ "$quiet" == "true" ]]; then
        fix_cmd+=(--quiet)
    fi

    # Run via SSH
    local ssh_output ssh_exit_code
    if ssh_output=$(_cai_ssh_run "$container_name" "$context" "false" "$quiet" "false" "false" "${fix_cmd[@]}" 2>&1); then
        ssh_exit_code=0
    else
        ssh_exit_code=$?
    fi

    # Output results (unless quiet)
    if [[ "$quiet" != "true" && -n "$ssh_output" ]]; then
        printf '%s\n' "$ssh_output"
    fi

    return $ssh_exit_code
}

return 0
