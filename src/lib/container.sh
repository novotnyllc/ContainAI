#!/usr/bin/env bash
# ==============================================================================
# ContainAI Container Operations
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _containai_container_name     - Generate sanitized container name
#   _containai_check_isolation    - Detect container isolation status
#   _containai_ensure_volumes     - Ensure a volume exists (takes volume name param)
#   _containai_start_container    - Start or attach to container
#   _containai_stop_all           - Stop all ContainAI containers
#
# Container inspection helpers:
#   _containai_container_exists         - Check if container exists
#   _containai_get_container_label      - Get ContainAI label value
#   _containai_get_container_image      - Get container image name
#   _containai_get_container_data_volume - Get mounted data volume name
#   _containai_is_our_container         - Check if container belongs to ContainAI
#   _containai_check_container_ownership - Check ownership with error messaging
#   _containai_check_volume_match       - Check if volume matches desired
#
# Constants:
#   _CONTAINAI_IMAGE              - Default image name
#   _CONTAINAI_LABEL              - Container label for ContainAI ownership
#
# Dependencies:
#   - lib/core.sh (logging functions)
#   - lib/docker.sh (Docker availability checks)
#   - lib/doctor.sh (context selection: _cai_select_context, _cai_sysbox_available_for_context)
#
# Usage: source lib/container.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/container.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/container.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/container.sh" >&2
    exit 1
fi

# ==============================================================================
# Constants
# ==============================================================================

# Guard against re-sourcing
: "${_CONTAINAI_LABEL:=containai.managed=true}"
: "${_CONTAINAI_DEFAULT_REPO:=agent-sandbox}"
: "${_CONTAINAI_DEFAULT_AGENT:=claude}"
: "${_CONTAINAI_DEFAULT_CREDENTIALS:=none}"

# Map agent name to default image tag
# Format: agent -> tag
declare -A _CONTAINAI_AGENT_TAGS 2>/dev/null || true
_CONTAINAI_AGENT_TAGS=(
    [claude]="claude-code"
    [gemini]="gemini-cli"
)

# ==============================================================================
# Image resolution
# ==============================================================================

# Resolve the image to use based on agent and optional tag override
# Arguments: $1 = agent name (claude, gemini), $2 = optional image tag override
# Outputs: Full image name (repo:tag)
# Returns: 0 on success, 1 on invalid agent
_containai_resolve_image() {
    local agent="${1:-$_CONTAINAI_DEFAULT_AGENT}"
    local explicit_tag="${2:-}"
    local repo="$_CONTAINAI_DEFAULT_REPO"
    local tag

    # Validate agent and get default tag
    if [[ -z "${_CONTAINAI_AGENT_TAGS[$agent]:-}" ]]; then
        _cai_error "Unknown agent: $agent"
        _cai_error "  Supported agents: claude, gemini"
        return 1
    fi

    # Tag precedence: --image-tag > CONTAINAI_AGENT_TAG > agent default
    if [[ -n "$explicit_tag" ]]; then
        tag="$explicit_tag"
    elif [[ -n "${CONTAINAI_AGENT_TAG:-}" ]]; then
        tag="$CONTAINAI_AGENT_TAG"
    else
        tag="${_CONTAINAI_AGENT_TAGS[$agent]}"
    fi

    printf "agent-sandbox:latest"
    return 0
}

# Check if image exists locally
# Arguments: $1 = image name, $2 = context name (optional)
# Returns: 0 if exists, 1 if not found
_containai_check_image() {
    local image="$1"
    local context="${2:-}"
    local inspect_output
    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    if ! inspect_output=$("${docker_cmd[@]}" image inspect "$image" 2>&1); then
        if printf '%s' "$inspect_output" | grep -qiE "no such image|not found"; then
            _cai_error "Image not found: $image"
            if [[ -n "$context" ]]; then
                _cai_info "Pull the image with: docker --context $context pull $image"
            else
                _cai_info "Pull the image with: docker pull $image"
            fi
        else
            printf '%s\n' "$inspect_output" >&2
        fi
        return 1
    fi
    return 0
}

# ==============================================================================
# Volume name validation (local copy for independence from config.sh)
# ==============================================================================

# Validate Docker volume name pattern (private helper to avoid collision with config.sh)
# Pattern: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
# Length: 1-255 characters
# Returns: 0=valid, 1=invalid
_containai__validate_volume_name() {
    local name="$1"

    # Check length
    if [[ -z "$name" ]] || [[ ${#name} -gt 255 ]]; then
        return 1
    fi

    # Check pattern: must start with alphanumeric, followed by alphanumeric, underscore, dot, or dash
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# Docker availability check
# ==============================================================================

# Check if Docker is available and responsive
# Returns: 0=available, 1=not available (with error message)
# Note: Uses _cai_docker_available for timeout-protected daemon check
_containai_check_docker() {
    # Delegate to lib/docker.sh which has timeout protection
    # The 'verbose' flag enables actionable error messages
    if ! _cai_docker_available verbose; then
        return 1
    fi
    return 0
}

# ==============================================================================
# Container naming
# ==============================================================================

# Generate sanitized container name from git repo/branch or directory
# Format: <repo>-<branch> (sanitized)
# Returns: container name via stdout
_containai_container_name() {
    local name repo_name branch_name

    # Guard git usage to avoid "command not found" noise in minimal environments
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        repo_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)"

        # Check for detached HEAD
        if git symbolic-ref -q HEAD >/dev/null 2>&1; then
            branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
        else
            # Detached HEAD - use short SHA
            branch_name="detached-$(git rev-parse --short HEAD 2>/dev/null)"
        fi

        name="${repo_name}-${branch_name}"
    else
        # Fall back to current directory name
        name="$(basename "$(pwd)")"
    fi

    # Sanitize: lowercase, replace non-alphanumeric with dash, collapse repeated dashes
    # Use sed 's/--*/-/g' for POSIX portability (BSD/macOS compatible)
    name="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g')"

    # Strip leading/trailing dashes
    name="$(printf '%s' "$name" | sed 's/^-*//;s/-*$//')"

    # Handle empty or dash-only names
    if [[ -z "$name" || "$name" =~ ^-+$ ]]; then
        name="sandbox-$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-*//;s/-*$//')"
    fi

    # Truncate to 63 characters (Docker limit)
    name="${name:0:63}"

    # Final cleanup of trailing dashes from truncation
    name="$(printf '%s' "$name" | sed 's/-*$//')"

    # Final fallback if name became empty after all processing
    if [[ -z "$name" ]]; then
        local dir_fallback
        dir_fallback="$(basename "$(pwd)")"
        dir_fallback="$(printf '%s' "$dir_fallback" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-*//;s/-*$//')"
        if [[ -n "$dir_fallback" ]]; then
            name="sandbox-$dir_fallback"
            name="${name:0:63}"
            name="$(printf '%s' "$name" | sed 's/-*$//')"
        else
            name="sandbox-default"
        fi
    fi

    printf '%s' "$name"
}

# ==============================================================================
# Isolation detection
# ==============================================================================

# Container isolation detection (conservative - prefer return 2 over false positive/negative)
# Checks docker info for Sysbox runtime, rootless mode, or user namespace remapping.
# Requires: Docker must be available (call _containai_check_docker first)
# Returns: 0=isolated (detected), 1=not isolated (definite), 2=unknown (ambiguous)
_containai_check_isolation() {
    local runtime rootless userns

    # Guard: check docker availability
    if ! command -v docker >/dev/null 2>&1; then
        echo "[WARN] Unable to determine isolation status (docker not found)" >&2
        return 2
    fi

    # Use docker info --format for reliable structured output with timeout
    # Use if ! pattern for set -e safety
    if ! runtime=$(_cai_timeout 5 docker info --format '{{.DefaultRuntime}}' 2>/dev/null); then
        echo "[WARN] Unable to determine isolation status" >&2
        return 2
    fi
    if [[ -z "$runtime" ]]; then
        echo "[WARN] Unable to determine isolation status" >&2
        return 2
    fi

    # These can fail without blocking (we only use them if available)
    # Use timeout to avoid hanging on slow/unhealthy daemons
    rootless=$(_cai_timeout 5 docker info --format '{{.Rootless}}' 2>/dev/null) || rootless=""
    userns=$(_cai_timeout 5 docker info --format '{{.SecurityOptions}}' 2>/dev/null) || userns=""

    # Sysbox runtime provides isolation
    if [[ "$runtime" == "sysbox-runc" ]]; then
        return 0
    fi

    # Rootless mode
    if [[ "$rootless" == "true" ]]; then
        return 0
    fi

    # User namespace remapping enabled
    if printf '%s' "$userns" | grep -q "userns"; then
        return 0
    fi

    # Standard runc without isolation features
    if [[ "$runtime" == "runc" ]]; then
        echo "[WARN] No additional isolation detected (standard runtime)" >&2
        return 1
    fi

    echo "[WARN] Unable to determine isolation status" >&2
    return 2
}

# ==============================================================================
# Preflight checks
# ==============================================================================

# Preflight checks for isolation before container start
# Arguments: $1 = force flag ("true" to skip checks)
# Returns: 0=proceed, 1=block
_containai_preflight_checks() {
    local force_flag="$1"
    local isolation_rc

    if [[ "$force_flag" == "true" ]]; then
        echo "[WARN] Skipping isolation check (--force)" >&2
        if [[ "${CONTAINAI_REQUIRE_ISOLATION:-0}" == "1" ]]; then
            echo "*** WARNING: Bypassing isolation requirement with --force" >&2
            echo "*** Running without verified isolation may expose host system" >&2
        fi
        return 0
    fi

    # Guard for set -e safety (non-zero is valid control flow)
    if _containai_check_isolation; then
        isolation_rc=0
    else
        isolation_rc=$?
    fi

    if [[ "${CONTAINAI_REQUIRE_ISOLATION:-0}" == "1" ]]; then
        case $isolation_rc in
            0) ;;
            1)
                echo "[ERROR] Container isolation required but not detected. Use --force to bypass." >&2
                return 1
                ;;
            2)
                echo "[ERROR] Cannot verify isolation status. Use --force to bypass." >&2
                return 1
                ;;
        esac
    fi

    return 0
}

# ==============================================================================
# Volume management
# ==============================================================================

# Ensure a volume exists, creating it if necessary
# Arguments: $1 = volume name, $2 = quiet flag (optional, default false), $3 = context (optional)
# Returns: 0 on success, 1 on failure
_containai_ensure_volumes() {
    local volume_name="$1"
    local quiet="${2:-false}"
    local context="${3:-}"

    if [[ -z "$volume_name" ]]; then
        echo "[ERROR] Volume name is required" >&2
        return 1
    fi

    # Validate volume name
    if ! _containai__validate_volume_name "$volume_name"; then
        echo "[ERROR] Invalid volume name: $volume_name" >&2
        echo "  Volume names must start with alphanumeric and contain only [a-zA-Z0-9_.-]" >&2
        return 1
    fi

    # Build context-aware docker command
    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    if ! "${docker_cmd[@]}" volume inspect "$volume_name" >/dev/null 2>&1; then
        if [[ "$quiet" != "true" ]]; then
            echo "Creating volume: $volume_name"
        fi
        if ! "${docker_cmd[@]}" volume create "$volume_name" >/dev/null; then
            echo "[ERROR] Failed to create volume $volume_name" >&2
            return 1
        fi
    fi
    return 0
}

# ==============================================================================
# Container inspection helpers
# ==============================================================================

# Check if container exists
# Arguments: $1 = container name
# Returns: 0=exists, 1=does not exist, 2=docker error (daemon down, etc.)
_containai_container_exists() {
    local container_name="$1"
    local inspect_output

    # Use if ! pattern for set -e safety
    if inspect_output=$(docker inspect --type container --format '{{.Id}}' "$container_name" 2>&1); then
        return 0  # Container exists
    fi

    # Check if it's "no such" vs other errors
    if printf '%s' "$inspect_output" | grep -qiE "no such object|not found|error.*no such"; then
        return 1  # Container doesn't exist
    fi

    # Docker error (daemon down, permission, etc.)
    return 2
}

# Get label value for ContainAI container
# Arguments: $1 = container name
# Outputs to stdout: label value (may be empty)
# Returns: 0 on success, 1 on docker error
_containai_get_container_label() {
    local container_name="$1"
    local label_value

    # Use if ! pattern for set -e safety
    if ! label_value=$(docker inspect --format '{{ index .Config.Labels "containai.managed" }}' "$container_name" 2>/dev/null); then
        return 1
    fi
    # Normalize "<no value>" to empty
    if [[ "$label_value" == "<no value>" ]]; then
        label_value=""
    fi

    printf '%s' "$label_value"
    return 0
}

# Get the image name of a container (empty if not found or error)
_containai_get_container_image() {
    local container_name="$1"
    local image_name

    # Use if pattern for set -e safety
    if image_name=$(docker inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null); then
        printf '%s' "$image_name"
    else
        echo ""
    fi
}

# Get the data volume mounted at /mnt/agent-data from a container
# Returns: volume name or empty if not found
_containai_get_container_data_volume() {
    local container_name="$1"
    local volume_name

    # Use if pattern for set -e safety
    if volume_name=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' "$container_name" 2>/dev/null); then
        printf '%s' "$volume_name"
    else
        echo ""
    fi
}

# Check if an image name belongs to ContainAI (from our repo)
# Arguments: $1 = image name
# Returns: 0=ours, 1=not ours
_containai_is_our_image() {
    local image_name="$1"
    # Check if image starts with our repo prefix
    [[ "$image_name" == "${_CONTAINAI_DEFAULT_REPO}:"* ]]
}

# Verify container was created by ContainAI (has our label or uses our image)
# Returns: 0=ours (label or image matches), 1=foreign (no match), 2=docker error
_containai_is_our_container() {
    local container_name="$1"
    local exists_rc label_value image_name

    # Guard for set -e safety (non-zero is valid control flow)
    if _containai_container_exists "$container_name"; then
        exists_rc=0
    else
        exists_rc=$?
    fi
    if [[ $exists_rc -eq 1 ]]; then
        return 1  # Doesn't exist = not ours
    elif [[ $exists_rc -eq 2 ]]; then
        return 2  # Docker error
    fi

    # Get label value - use if ! pattern for set -e safety
    if ! label_value=$(_containai_get_container_label "$container_name"); then
        return 2  # Docker error
    fi

    # Check label
    if [[ "$label_value" == "true" ]]; then
        return 0
    fi

    # Fallback: check image (for containers without label)
    if [[ -z "$label_value" ]]; then
        image_name="$(_containai_get_container_image "$container_name")"
        if _containai_is_our_image "$image_name"; then
            return 0
        fi
    fi

    return 1
}

# Check container ownership with appropriate messaging
# Returns: 0=owned, 1=foreign (with error), 2=does not exist, 3=docker error
_containai_check_container_ownership() {
    local container_name="$1"
    local exists_rc is_ours_rc label_value actual_image

    # Guard for set -e safety (non-zero is valid control flow)
    if _containai_container_exists "$container_name"; then
        exists_rc=0
    else
        exists_rc=$?
    fi
    if [[ $exists_rc -eq 1 ]]; then
        return 2  # Container doesn't exist
    elif [[ $exists_rc -eq 2 ]]; then
        echo "[ERROR] Cannot check container ownership - Docker error" >&2
        return 3
    fi

    # Guard for set -e safety (non-zero is valid control flow)
    if _containai_is_our_container "$container_name"; then
        is_ours_rc=0
    else
        is_ours_rc=$?
    fi
    if [[ $is_ours_rc -eq 0 ]]; then
        return 0
    elif [[ $is_ours_rc -eq 2 ]]; then
        echo "[ERROR] Cannot check container ownership - Docker error" >&2
        return 3
    fi

    # Foreign container - show detailed info (use || true for set -e safety on info gathering)
    label_value=$(_containai_get_container_label "$container_name") || label_value=""
    actual_image="$(_containai_get_container_image "$container_name")"

    echo "[ERROR] Container '$container_name' exists but was not created by ContainAI" >&2
    echo "" >&2
    echo "  Expected label 'containai.managed': true" >&2
    echo "  Actual label 'containai.managed':   ${label_value:-<not set>}" >&2
    echo "  Expected image prefix:              ${_CONTAINAI_DEFAULT_REPO}:" >&2
    echo "  Actual image:                       ${actual_image:-<unknown>}" >&2
    echo "" >&2
    echo "This is a name collision with a container not managed by ContainAI." >&2
    echo "To recreate as a ContainAI-managed sandbox container, run: cai --restart" >&2
    echo "" >&2
    return 1
}

# Check if container's image matches the resolved image for the requested agent
# Arguments: $1 = container name, $2 = resolved image name, $3 = quiet flag
# Returns: 0 if match, 1 if mismatch (with warning)
_containai_check_image_match() {
    local container_name="$1"
    local resolved_image="$2"
    local quiet_flag="$3"
    local actual_image

    actual_image="$(_containai_get_container_image "$container_name")"

    if [[ -z "$actual_image" ]]; then
        # Can't determine image - allow proceeding
        return 0
    fi

    if [[ "$actual_image" != "$resolved_image" ]]; then
        if [[ "$quiet_flag" != "true" ]]; then
            echo "[WARN] Image mismatch for container '$container_name'" >&2
            echo "" >&2
            echo "  Container image: $actual_image" >&2
            echo "  Requested image: $resolved_image" >&2
            echo "" >&2
            echo "The container was created with a different agent/image." >&2
            echo "To use the requested agent, recreate the container:" >&2
            echo "  cai --restart" >&2
            echo "Or specify a different container name:" >&2
            echo "  cai --name <unique-name>" >&2
            echo "" >&2
        fi
        return 1
    fi

    return 0
}

# Check if container's mounted volume matches the desired volume
# Arguments: $1 = container name, $2 = desired volume name, $3 = quiet flag
# Returns: 0 if match or no mount found, 1 if mismatch (with warning)
_containai_check_volume_match() {
    local container_name="$1"
    local desired_volume="$2"
    local quiet_flag="$3"
    local mounted_volume

    mounted_volume=$(_containai_get_container_data_volume "$container_name")

    if [[ -z "$mounted_volume" ]]; then
        return 0
    fi

    if [[ "$mounted_volume" != "$desired_volume" ]]; then
        if [[ "$quiet_flag" != "true" ]]; then
            echo "[WARN] Volume mismatch for container '$container_name'" >&2
            echo "" >&2
            echo "  Container uses volume: $mounted_volume" >&2
            echo "  Workspace expects:     $desired_volume" >&2
            echo "" >&2
            echo "The container was created with a different workspace/config." >&2
            echo "To use the correct volume, recreate the container:" >&2
            echo "  cai --restart" >&2
            echo "Or specify a different container name:" >&2
            echo "  cai --name <unique-name>" >&2
            echo "" >&2
        fi
        return 1
    fi

    return 0
}

# ==============================================================================
# Start container
# ==============================================================================

# Start or attach to a ContainAI sandbox container
# This is the core container operation function
# Arguments:
#   --name <name>        Container name (default: auto-generated)
#   --workspace <path>   Workspace path (default: $PWD)
#   --data-volume <vol>  Data volume name (required)
#   --agent <name>       Agent to run (claude, gemini; default: claude)
#   --image-tag <tag>    Override image tag (default: agent-specific)
#   --credentials <mode> Credential mode (none, host; default: none)
#   --acknowledge-credential-risk  Required when using --credentials=host
#   --volume-mismatch-warn  Warn on volume mismatch instead of blocking (for implicit volumes)
#   --restart            Force recreate container
#   --force              Skip preflight checks
#   --detached           Run detached
#   --shell              Start with shell instead of agent
#   --quiet              Suppress verbose output
#   --debug              Enable debug logging
#   --mount-docker-socket Mount docker socket (dangerous)
#   --please-root-my-host Acknowledge docker socket danger
#   -e, --env <VAR=val>  Environment variable (repeatable)
#   -v, --volume <spec>  Extra volume mount (repeatable)
#   -- <agent_args>      Arguments to pass to agent
# Returns: 0 on success, 1 on failure
_containai_start_container() {
    local container_name=""
    local workspace=""
    local data_volume=""
    local explicit_config=""
    local agent=""
    local image_tag=""
    local credentials="$_CONTAINAI_DEFAULT_CREDENTIALS"
    local acknowledge_credential_risk=false
    local allow_host_credentials=false
    local ack_host_credentials=false
    local allow_host_docker_socket=false
    local ack_host_docker_socket=false
    local volume_mismatch_warn=false
    local restart_flag=false
    local force_flag=false
    local detached_flag=false
    local shell_flag=false
    local quiet_flag=false
    local debug_flag=false
    local mount_docker_socket=false
    local please_root_my_host=false
    local -a env_vars=()
    local -a extra_volumes=()
    local -a agent_args=()
    local arg

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --)
                shift
                agent_args=("$@")
                break
                ;;
            --name)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --name requires a value" >&2
                    return 1
                fi
                container_name="$2"
                shift 2
                ;;
            --name=*)
                container_name="${1#--name=}"
                shift
                ;;
            --workspace|-w)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --workspace requires a value" >&2
                    return 1
                fi
                workspace="$2"
                workspace="${workspace/#\~/$HOME}"
                shift 2
                ;;
            --workspace=*)
                workspace="${1#--workspace=}"
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            -w*)
                workspace="${1#-w}"
                workspace="${workspace/#\~/$HOME}"
                shift
                ;;
            --data-volume)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --data-volume requires a value" >&2
                    return 1
                fi
                data_volume="$2"
                shift 2
                ;;
            --data-volume=*)
                data_volume="${1#--data-volume=}"
                shift
                ;;
            --config)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                explicit_config="$2"
                shift 2
                ;;
            --config=*)
                explicit_config="${1#--config=}"
                if [[ -z "$explicit_config" ]]; then
                    echo "[ERROR] --config requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --agent)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --agent requires a value" >&2
                    return 1
                fi
                agent="$2"
                shift 2
                ;;
            --agent=*)
                agent="${1#--agent=}"
                if [[ -z "$agent" ]]; then
                    echo "[ERROR] --agent requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --image-tag)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --image-tag requires a value" >&2
                    return 1
                fi
                image_tag="$2"
                shift 2
                ;;
            --image-tag=*)
                image_tag="${1#--image-tag=}"
                if [[ -z "$image_tag" ]]; then
                    echo "[ERROR] --image-tag requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --credentials)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --credentials requires a value" >&2
                    return 1
                fi
                credentials="$2"
                shift 2
                ;;
            --credentials=*)
                credentials="${1#--credentials=}"
                if [[ -z "$credentials" ]]; then
                    echo "[ERROR] --credentials requires a value" >&2
                    return 1
                fi
                shift
                ;;
            --acknowledge-credential-risk)
                acknowledge_credential_risk=true
                shift
                ;;
            --volume-mismatch-warn)
                volume_mismatch_warn=true
                shift
                ;;
            --restart)
                restart_flag=true
                shift
                ;;
            --force)
                force_flag=true
                shift
                ;;
            --detached|-d)
                detached_flag=true
                shift
                ;;
            --shell)
                shell_flag=true
                shift
                ;;
            --quiet|-q)
                quiet_flag=true
                shift
                ;;
            --debug|-D)
                debug_flag=true
                shift
                ;;
            --mount-docker-socket)
                mount_docker_socket=true
                shift
                ;;
            --please-root-my-host)
                please_root_my_host=true
                shift
                ;;
            --allow-host-credentials)
                allow_host_credentials=true
                shift
                ;;
            --i-understand-this-exposes-host-credentials)
                ack_host_credentials=true
                shift
                ;;
            --allow-host-docker-socket)
                allow_host_docker_socket=true
                shift
                ;;
            --i-understand-this-grants-root-access)
                ack_host_docker_socket=true
                shift
                ;;
            --env|-e)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --env requires a value" >&2
                    return 1
                fi
                env_vars+=("$2")
                shift 2
                ;;
            --env=*)
                env_vars+=("${1#--env=}")
                shift
                ;;
            -e*)
                env_vars+=("${1#-e}")
                shift
                ;;
            --volume|-v)
                if [[ -z "${2-}" ]]; then
                    echo "[ERROR] --volume requires a value" >&2
                    return 1
                fi
                extra_volumes+=("$2")
                shift 2
                ;;
            --volume=*)
                extra_volumes+=("${1#--volume=}")
                shift
                ;;
            -v*)
                extra_volumes+=("${1#-v}")
                shift
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$data_volume" ]]; then
        echo "[ERROR] --data-volume is required" >&2
        return 1
    fi

    # Set agent default if not specified
    if [[ -z "$agent" ]]; then
        agent="$_CONTAINAI_DEFAULT_AGENT"
    fi

    # Reject legacy options that are no longer supported
    if [[ "$allow_host_credentials" == "true" ]] || [[ "$credentials" == "host" ]]; then
        echo "" >&2
        echo "[ERROR] --credentials=host and --allow-host-credentials are no longer supported" >&2
        echo "" >&2
        echo "Host credential sharing is not available with Sysbox isolation." >&2
        echo "" >&2
        echo "For credential access inside containers, use 'cai import' to copy credentials." >&2
        echo "" >&2
        return 1
    fi

    if [[ "$allow_host_docker_socket" == "true" ]] || [[ "$mount_docker_socket" == "true" ]]; then
        echo "" >&2
        echo "[ERROR] --mount-docker-socket and --allow-host-docker-socket are no longer supported" >&2
        echo "" >&2
        echo "Docker socket mounting is not available with Sysbox isolation." >&2
        echo "" >&2
        echo "Sysbox containers have Docker-in-Docker capability built in." >&2
        echo "Use the inner Docker daemon instead of mounting the host socket." >&2
        echo "" >&2
        return 1
    fi

    # Resolve image based on agent and optional tag override
    local resolved_image="agent-sandbox:latest"

    # Early docker check
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Resolve workspace
    local workspace_resolved
    workspace_resolved="${workspace:-$PWD}"
    if ! workspace_resolved=$(cd -- "$workspace_resolved" 2>/dev/null && pwd); then
        echo "[ERROR] Workspace path does not exist: ${workspace:-$PWD}" >&2
        return 1
    fi

    # === CONTEXT SELECTION (must happen before container state checks) ===
    # Resolve secure engine context from config (for context override)
    # Note: capture stdout only for context value; let stderr flow to parent stderr
    local config_context_override=""
    if [[ -n "$explicit_config" ]]; then
        # Explicit config: strict mode - fail on parse errors
        if ! config_context_override=$(_containai_resolve_secure_engine_context "$workspace_resolved" "$explicit_config"); then
            echo "[ERROR] Failed to parse config: $explicit_config" >&2
            return 1
        fi
    else
        # Discovered config: suppress errors gracefully
        config_context_override=$(_containai_resolve_secure_engine_context "$workspace_resolved" "" 2>/dev/null) || config_context_override=""
    fi

    # Auto-select Docker context based on isolation availability
    local selected_context debug_mode=""
    if [[ "$debug_flag" == "true" ]]; then
        debug_mode="debug"
    fi
    if ! selected_context=$(_cai_select_context "$config_context_override" "$debug_mode"); then
        if [[ "$force_flag" == "true" ]]; then
            echo "[WARN] No isolation available but --force specified. Proceeding without isolation checks." >&2
            selected_context=""
        else
            _cai_error "No isolation available. Run 'cai doctor' for setup instructions."
            _cai_error "Use --force to bypass (for testing only - not recommended)"
            return 1
        fi
    fi

    # Build docker command prefix based on context
    # Context is always Sysbox mode
    local -a docker_cmd=(docker)
    if [[ -n "$selected_context" ]]; then
        docker_cmd=(docker --context "$selected_context")
    fi

    # Get container name
    if [[ -z "$container_name" ]]; then
        container_name="$(_containai_container_name)"
    fi
    if [[ "$quiet_flag" != "true" ]]; then
        echo "Container: $container_name"
    fi

    # Check container state - guard for set -e safety (non-zero is valid control flow)
    # Use context-aware docker command for container inspection
    local container_state exists_rc
    if "${docker_cmd[@]}" inspect "$container_name" >/dev/null 2>&1; then
        exists_rc=0
    else
        exists_rc=1
    fi

    if [[ $exists_rc -eq 0 ]]; then
        # Use || true for set -e safety (success already confirmed by exists check)
        container_state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || container_state=""
    else
        container_state="none"
    fi

    # Handle --restart flag
    if [[ "$restart_flag" == "true" && "$container_state" != "none" ]]; then
        # Check if container belongs to ContainAI using context-aware inspection (label or image fallback)
        local label_val restart_image_fallback
        label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || label_val=""
        if [[ "$label_val" != "true" ]]; then
            # Fallback: check if image is from our repo (for legacy containers without label)
            restart_image_fallback=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || restart_image_fallback=""
            if [[ "$restart_image_fallback" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                echo "[ERROR] Cannot restart - container '$container_name' was not created by ContainAI" >&2
                echo "Remove the conflicting container manually if needed: docker rm -f '$container_name'" >&2
                return 1
            fi
        fi
        if [[ "$quiet_flag" != "true" ]]; then
            echo "Stopping existing container..."
        fi
        # Stop container, ignoring "not running" errors but surfacing others
        local stop_output
        stop_output="$("${docker_cmd[@]}" stop "$container_name" 2>&1)" || {
            if ! printf '%s' "$stop_output" | grep -qiE "is not running"; then
                echo "$stop_output" >&2
            fi
        }
        # Remove container, ignoring "not found" errors but surfacing others
        local rm_output
        rm_output="$("${docker_cmd[@]}" rm "$container_name" 2>&1)" || {
            if ! printf '%s' "$rm_output" | grep -qiE "no such container|not found"; then
                echo "$rm_output" >&2
                return 1
            fi
        }
        container_state="none"
    fi

    # Handle shell mode with stopped container
    if [[ "$shell_flag" == "true" ]] && [[ "$container_state" == "exited" || "$container_state" == "created" ]]; then
        # Check ownership using context-aware docker command (label or image fallback)
        local shell_label_val shell_image_fallback
        shell_label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || shell_label_val=""
        if [[ "$shell_label_val" != "true" ]]; then
            # Fallback: check if image is from our repo (for legacy containers without label)
            shell_image_fallback=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || shell_image_fallback=""
            if [[ "$shell_image_fallback" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                echo "[ERROR] Container '$container_name' was not created by ContainAI" >&2
                return 1
            fi
        fi
        # Skip preflight checks - context selection already validated isolation
        if [[ "$quiet_flag" != "true" ]]; then
            echo "Recreating container for shell access..."
        fi
        "${docker_cmd[@]}" rm "$container_name" >/dev/null 2>&1
        container_state="none"
    fi

    # Check image exists when creating new container (use selected context)
    if [[ "$container_state" == "none" ]]; then
        if ! _containai_check_image "$resolved_image" "$selected_context"; then
            return 1
        fi
    fi

    case "$container_state" in
        running)
            # Check ownership using context-aware docker command (label or image fallback)
            local running_label_val running_image_val
            running_label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || running_label_val=""
            if [[ "$running_label_val" != "true" ]]; then
                # Fallback: check if image is from our repo (for legacy containers without label)
                running_image_val=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || running_image_val=""
                if [[ "$running_image_val" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    echo "[ERROR] Container '$container_name' was not created by ContainAI" >&2
                    return 1
                fi
            fi
            # Check image match using context-aware docker command
            local running_image
            running_image=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || running_image=""
            if [[ "$running_image" != "$resolved_image" ]]; then
                if [[ "$quiet_flag" != "true" ]]; then
                    echo "[WARN] Container image mismatch:" >&2
                    echo "  Running:   $running_image" >&2
                    echo "  Requested: $resolved_image" >&2
                fi
                echo "[ERROR] Image mismatch prevents attachment. Use --restart to recreate with requested agent." >&2
                return 1
            fi
            # Check volume match using context-aware docker command
            local running_volume
            running_volume=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' "$container_name" 2>/dev/null) || running_volume=""
            if [[ "$running_volume" != "$data_volume" ]]; then
                if [[ "$quiet_flag" != "true" ]]; then
                    echo "[WARN] Data volume mismatch:" >&2
                    echo "  Running:   ${running_volume:-<none>}" >&2
                    echo "  Requested: $data_volume" >&2
                fi
                if [[ "$volume_mismatch_warn" != "true" ]]; then
                    echo "[ERROR] Volume mismatch prevents attachment. Use --restart to recreate." >&2
                    return 1
                fi
            fi
            if [[ "$quiet_flag" != "true" ]]; then
                echo "Attaching to running container..."
            fi
            # Execute agent command (with args if provided) or shell if in shell mode
            if [[ "$shell_flag" == "true" ]]; then
                "${docker_cmd[@]}" exec -it --user agent -w /home/agent/workspace "$container_name" bash
            else
                # Run agent with any provided arguments
                local -a exec_cmd=("$agent")
                if [[ ${#agent_args[@]} -gt 0 ]]; then
                    exec_cmd+=("${agent_args[@]}")
                fi
                "${docker_cmd[@]}" exec -it --user agent -w /home/agent/workspace "$container_name" "${exec_cmd[@]}"
            fi
            ;;
        exited|created)
            # Check ownership using context-aware docker command (label or image fallback)
            local exited_label_val exited_image_fallback
            exited_label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' "$container_name" 2>/dev/null) || exited_label_val=""
            if [[ "$exited_label_val" != "true" ]]; then
                # Fallback: check if image is from our repo (for legacy containers without label)
                exited_image_fallback=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || exited_image_fallback=""
                if [[ "$exited_image_fallback" != "${_CONTAINAI_DEFAULT_REPO}:"* ]]; then
                    echo "[ERROR] Container '$container_name' was not created by ContainAI" >&2
                    return 1
                fi
            fi
            # Check image match using context-aware docker command
            local exited_image
            exited_image=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null) || exited_image=""
            if [[ "$exited_image" != "$resolved_image" ]]; then
                if [[ "$quiet_flag" != "true" ]]; then
                    echo "[WARN] Container image mismatch:" >&2
                    echo "  Running:   $exited_image" >&2
                    echo "  Requested: $resolved_image" >&2
                fi
                echo "[ERROR] Image mismatch prevents start. Use --restart to recreate with requested agent." >&2
                return 1
            fi
            # Check volume match using context-aware docker command
            local exited_volume
            exited_volume=$("${docker_cmd[@]}" inspect --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' "$container_name" 2>/dev/null) || exited_volume=""
            if [[ "$exited_volume" != "$data_volume" ]]; then
                if [[ "$quiet_flag" != "true" ]]; then
                    echo "[WARN] Data volume mismatch:" >&2
                    echo "  Running:   ${exited_volume:-<none>}" >&2
                    echo "  Requested: $data_volume" >&2
                fi
                if [[ "$volume_mismatch_warn" != "true" ]]; then
                    echo "[ERROR] Volume mismatch prevents start. Use --restart to recreate." >&2
                    return 1
                fi
            fi
            # Skip preflight checks - context selection already validated isolation
            # If agent_args provided, start container detached then exec with args
            # docker start -ai doesn't support passing args to the entrypoint
            if [[ ${#agent_args[@]} -gt 0 ]]; then
                if [[ "$quiet_flag" != "true" ]]; then
                    echo "Starting stopped container with arguments..."
                fi
                "${docker_cmd[@]}" start "$container_name" >/dev/null
                # Wait for container to be running (poll with bounded timeout)
                local wait_count=0
                local max_wait=30
                while [[ $wait_count -lt $max_wait ]]; do
                    local state
                    state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || state=""
                    if [[ "$state" == "running" ]]; then
                        break
                    fi
                    sleep 0.5
                    ((wait_count++))
                done
                if [[ $wait_count -ge $max_wait ]]; then
                    echo "[ERROR] Container failed to start within ${max_wait} attempts" >&2
                    return 1
                fi
                # Run agent with arguments
                local -a exec_cmd=("$agent")
                exec_cmd+=("${agent_args[@]}")
                "${docker_cmd[@]}" exec -it --user agent -w /home/agent/workspace "$container_name" "${exec_cmd[@]}"
            else
                if [[ "$quiet_flag" != "true" ]]; then
                    echo "Starting stopped container..."
                fi
                "${docker_cmd[@]}" start -ai "$container_name"
            fi
            ;;
        none)
            # Skip preflight checks - context selection already validated isolation
            if ! _containai_ensure_volumes "$data_volume" "$quiet_flag" "$selected_context"; then
                return 1
            fi

            # Context already selected earlier in the function (stored in docker_cmd and selected_context)

            local -a vol_args=()
            vol_args+=("-v" "$data_volume:/mnt/agent-data")

            # Start container with Sysbox runtime
            if [[ "$quiet_flag" != "true" ]]; then
                if [[ -n "$selected_context" ]]; then
                    echo "Starting new container (Sysbox mode, context: $selected_context)..."
                else
                    echo "Starting new container (Sysbox mode)..."
                fi
            fi

            local -a args=()
            if [[ -n "$selected_context" ]]; then
                args+=(--context "$selected_context")
            fi
            args+=(run)
            args+=(--runtime=sysbox-runc)
            args+=(--name "$container_name")
            args+=(--label "$_CONTAINAI_LABEL")

            # Interactive/TTY flags
            if [[ "$shell_flag" == "true" ]]; then
                args+=(-d)
            elif [[ "$detached_flag" == "true" ]]; then
                args+=(-d)
            else
                args+=(-it)
            fi

            # Remove container on exit (only if not detached)
            if [[ "$detached_flag" != "true" && "$shell_flag" != "true" ]]; then
                args+=(--rm)
            fi

            # Volume mounts
            args+=("${vol_args[@]}")
            args+=(-v "$workspace_resolved:/home/agent/workspace")

            local vol env_var
            for vol in "${extra_volumes[@]}"; do
                args+=(-v "$vol")
            done

            # Environment variables
            for env_var in "${env_vars[@]}"; do
                args+=(-e "$env_var")
            done

            # Working directory
            args+=(-w /home/agent/workspace)

            # Image
            args+=("$resolved_image")

            # Command: agent with any args
            args+=("$agent")
            if [[ ${#agent_args[@]} -gt 0 ]]; then
                args+=("${agent_args[@]}")
            fi

            if [[ "$shell_flag" == "true" ]]; then
                # For shell mode, start container with sleep infinity to keep it running
                # Build args without the agent command
                local -a shell_args=()
                if [[ -n "$selected_context" ]]; then
                    shell_args+=(--context "$selected_context")
                fi
                shell_args+=(run)
                shell_args+=(--runtime=sysbox-runc)
                shell_args+=(--name "$container_name")
                shell_args+=(--label "$_CONTAINAI_LABEL")
                shell_args+=(-d)
                shell_args+=("${vol_args[@]}")
                shell_args+=(-v "$workspace_resolved:/home/agent/workspace")
                for vol in "${extra_volumes[@]}"; do
                    shell_args+=(-v "$vol")
                done
                for env_var in "${env_vars[@]}"; do
                    shell_args+=(-e "$env_var")
                done
                shell_args+=(-w /home/agent/workspace)
                shell_args+=("$resolved_image")
                shell_args+=(sleep infinity)
                if ! docker "${shell_args[@]}" >/dev/null; then
                    echo "[ERROR] Failed to create container" >&2
                    return 1
                fi
                "${docker_cmd[@]}" exec -it --user agent -w /home/agent/workspace "$container_name" bash
            else
                docker "${args[@]}"
            fi
            ;;
        *)
            echo "[ERROR] Unexpected container state: $container_state" >&2
            return 1
            ;;
    esac
}

# ==============================================================================
# Stop all containers
# ==============================================================================

# Helper to list containers from a specific context
# Arguments: $1 = context name (empty for default)
# Outputs: containers in format "name\tstatus\tcontext" (one per line)
_containai_list_containers_for_context() {
    local context="${1:-}"
    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    local labeled ancestor_claude ancestor_gemini line
    # Use || true for set -e safety - empty result is valid
    labeled=$("${docker_cmd[@]}" ps -a --filter "label=$_CONTAINAI_LABEL" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || labeled=""
    ancestor_claude=$("${docker_cmd[@]}" ps -a --filter "ancestor=${_CONTAINAI_DEFAULT_REPO}:claude-code" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || ancestor_claude=""
    ancestor_gemini=$("${docker_cmd[@]}" ps -a --filter "ancestor=${_CONTAINAI_DEFAULT_REPO}:gemini-cli" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || ancestor_gemini=""

    # Combine and dedupe, adding context as third column
    local combined
    combined=$(printf '%s\n%s\n%s' "$labeled" "$ancestor_claude" "$ancestor_gemini" | sed -e '/^$/d' | sort -t$'\t' -k1,1 -u)
    while IFS=$'\t' read -r name status; do
        if [[ -n "$name" ]]; then
            printf '%s\t%s\t%s\n' "$name" "$status" "$context"
        fi
    done <<< "$combined"
}

# Interactive container stop selection
# Finds all ContainAI containers (by label or ancestor image) and prompts user
# Checks both default context and secure engine context (containai-secure)
# Arguments: --all to stop all without prompting (non-interactive mode)
# Returns: 0 on success, 1 on error (non-interactive without --all, or docker unavailable)
_containai_stop_all() {
    local stop_all_flag=false
    local arg

    for arg in "$@"; do
        case "$arg" in
            --all)
                stop_all_flag=true
                ;;
        esac
    done

    # Check docker availability first
    if ! _containai_check_docker; then
        return 1
    fi

    # Collect containers from default context
    local default_containers secure_containers all_containers
    default_containers=$(_containai_list_containers_for_context "")

    # Determine which secure engine contexts to check
    # Check both configured context (if different) and default containai-secure
    local configured_context default_secure_context="containai-secure"
    configured_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || configured_context=""

    secure_containers=""

    # Check default containai-secure context
    if docker context inspect "$default_secure_context" >/dev/null 2>&1; then
        secure_containers=$(_containai_list_containers_for_context "$default_secure_context")
    fi

    # Also check configured context if different from default
    if [[ -n "$configured_context" ]] && [[ "$configured_context" != "$default_secure_context" ]]; then
        if docker context inspect "$configured_context" >/dev/null 2>&1; then
            local config_containers
            config_containers=$(_containai_list_containers_for_context "$configured_context")
            if [[ -n "$config_containers" ]]; then
                secure_containers=$(printf '%s\n%s' "$secure_containers" "$config_containers")
            fi
        fi
    fi

    # Merge results (containers may exist in both contexts with same name - keep both)
    all_containers=$(printf '%s\n%s' "$default_containers" "$secure_containers" | sed -e '/^$/d')

    if [[ -z "$all_containers" ]]; then
        echo "No ContainAI containers found."
        return 0
    fi

    echo "ContainAI containers:"
    echo ""

    local i=0
    local names=()
    local contexts=()
    local name status ctx display_ctx
    while IFS=$'\t' read -r name status ctx; do
        i=$((i + 1))
        names+=("$name")
        contexts+=("$ctx")
        if [[ -n "$ctx" ]]; then
            display_ctx=" [context: $ctx]"
        else
            display_ctx=""
        fi
        printf "  %d) %s (%s)%s\n" "$i" "$name" "$status" "$display_ctx"
    done <<< "$all_containers"

    if [[ "$stop_all_flag" == "true" ]]; then
        echo ""
        echo "Stopping all containers (--all flag)..."
        local idx container_to_stop ctx_to_use
        for idx in "${!names[@]}"; do
            container_to_stop="${names[$idx]}"
            ctx_to_use="${contexts[$idx]}"
            echo "Stopping: $container_to_stop${ctx_to_use:+ [context: $ctx_to_use]}"
            if [[ -n "$ctx_to_use" ]]; then
                docker --context "$ctx_to_use" stop "$container_to_stop" >/dev/null 2>&1 || true
            else
                docker stop "$container_to_stop" >/dev/null 2>&1 || true
            fi
        done
        echo "Done."
        return 0
    fi

    if [[ ! -t 0 ]]; then
        echo "" >&2
        echo "[ERROR] Non-interactive terminal detected." >&2
        echo "Use --all flag to stop all containers without prompting:" >&2
        echo "  cai-stop-all --all" >&2
        return 1
    fi

    echo ""
    echo "Enter numbers to stop (space-separated), 'all', or 'q' to quit:"
    local selection
    # Guard read for set -e safety (EOF returns non-zero)
    if ! read -r selection; then
        echo "Cancelled."
        return 0
    fi

    if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
        echo "Cancelled."
        return 0
    fi

    local -a to_stop_idx=()

    if [[ "$selection" == "all" || "$selection" == "ALL" ]]; then
        local idx
        for idx in "${!names[@]}"; do
            to_stop_idx+=("$idx")
        done
    else
        local num
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#names[@]}" ]]; then
                to_stop_idx+=("$((num - 1))")
            else
                echo "[WARN] Invalid selection: $num" >&2
            fi
        done
    fi

    if [[ ${#to_stop_idx[@]} -eq 0 ]]; then
        echo "No containers selected."
        return 0
    fi

    echo ""
    local idx container_to_stop ctx_to_use
    for idx in "${to_stop_idx[@]}"; do
        container_to_stop="${names[$idx]}"
        ctx_to_use="${contexts[$idx]}"
        echo "Stopping: $container_to_stop${ctx_to_use:+ [context: $ctx_to_use]}"
        if [[ -n "$ctx_to_use" ]]; then
            docker --context "$ctx_to_use" stop "$container_to_stop" >/dev/null 2>&1 || true
        else
            docker stop "$container_to_stop" >/dev/null 2>&1 || true
        fi
    done

    echo "Done."
}

return 0
