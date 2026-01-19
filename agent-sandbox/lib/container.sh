#!/usr/bin/env bash
# ==============================================================================
# ContainAI Container Operations
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _containai_container_name     - Generate sanitized container name
#   _containai_check_isolation    - Detect container isolation status
#   _containai_check_sandbox      - Check if docker sandbox is available
#   _containai_preflight_checks   - Run preflight checks before container ops
#   _containai_ensure_volumes     - Ensure a volume exists (takes volume name param)
#   _containai_start_container    - Start or attach to container
#   _containai_stop_all           - Stop all ContainAI containers
#
# Container inspection helpers:
#   _containai_container_exists         - Check if container exists
#   _containai_get_container_labels     - Get both new and legacy label values
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
: "${_CONTAINAI_IMAGE:=agent-sandbox:latest}"
: "${_CONTAINAI_LABEL:=containai.sandbox=containai}"

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
_containai_check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Quick liveness check
    if ! docker info >/dev/null 2>&1; then
        echo "[ERROR] Docker daemon is not accessible" >&2
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
# Requires: Docker must be available (call _containai_check_docker first or _containai_check_sandbox)
# Returns: 0=isolated (detected), 1=not isolated (definite), 2=unknown (ambiguous)
_containai_check_isolation() {
    local runtime rootless userns

    # Guard: check docker availability
    if ! command -v docker >/dev/null 2>&1; then
        echo "[WARN] Unable to determine isolation status (docker not found)" >&2
        return 2
    fi

    # Use docker info --format for reliable structured output
    # Use if ! pattern for set -e safety
    if ! runtime=$(docker info --format '{{.DefaultRuntime}}' 2>/dev/null); then
        echo "[WARN] Unable to determine isolation status" >&2
        return 2
    fi
    if [[ -z "$runtime" ]]; then
        echo "[WARN] Unable to determine isolation status" >&2
        return 2
    fi

    # These can fail without blocking (we only use them if available)
    rootless=$(docker info --format '{{.Rootless}}' 2>/dev/null) || rootless=""
    userns=$(docker info --format '{{.SecurityOptions}}' 2>/dev/null) || userns=""

    # ECI enabled - sysbox-runc runtime
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
# Sandbox availability check
# ==============================================================================

# Check if docker sandbox is available
# Returns: 0=yes, 1=no (definite), 2=unknown (fail-open with warning)
_containai_check_sandbox() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Check if sandbox command is available by trying to run it
    local ls_output
    if ls_output="$(docker sandbox ls 2>&1)"; then
        return 0
    fi

    # Sandbox ls failed - analyze the error to provide actionable feedback
    if printf '%s' "$ls_output" | grep -qiE "feature.*disabled|not enabled|requirements.*not met|sandbox.*unavailable" && \
       ! printf '%s' "$ls_output" | grep -qiE "no sandboxes"; then
        echo "[ERROR] Docker sandbox feature is not enabled" >&2
        echo "" >&2
        echo "  docker sandbox ls output:" >&2
        printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
        echo "" >&2
        echo "Please enable sandbox in Docker Desktop:" >&2
        echo "  Settings > Features in development > Docker sandbox" >&2
        echo "  See: https://docs.docker.com/desktop/features/sandbox/" >&2
        echo "" >&2
        return 1
    fi

    if printf '%s' "$ls_output" | grep -qiE "no sandboxes found|0 sandboxes|sandbox list is empty"; then
        echo "[WARN] docker sandbox ls returned empty list with error code" >&2
        echo "  Attempting to proceed - sandbox may be functional." >&2
        echo "" >&2
        return 2
    fi

    if printf '%s' "$ls_output" | grep -qiE "not recognized|unknown command|not a docker command|command not found"; then
        echo "[ERROR] Docker sandbox is not available" >&2
        echo "" >&2
        echo "  docker sandbox ls output:" >&2
        printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
        echo "" >&2
        echo "Docker sandbox requires Docker Desktop 4.50+ with sandbox feature enabled." >&2
        echo "Please ensure you have:" >&2
        echo "  1. Docker Desktop 4.50 or later installed" >&2
        echo "  2. Docker sandbox feature enabled in Settings > Features in development" >&2
        echo "  See: https://docs.docker.com/desktop/features/sandbox/" >&2
        echo "" >&2
        return 1
    fi

    if printf '%s' "$ls_output" | grep -qiE "permission denied"; then
        echo "[ERROR] Permission denied accessing Docker" >&2
        echo "" >&2
        echo "  docker sandbox ls output:" >&2
        printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
        echo "" >&2
        echo "Please ensure Docker is accessible:" >&2
        echo "  Docker Desktop (macOS/Windows): Ensure Docker Desktop is running and try restarting it" >&2
        echo "  Linux: Add your user to the 'docker' group: sudo usermod -aG docker \$USER" >&2
        echo "         Then log out and back in, or run: newgrp docker" >&2
        echo "" >&2
        return 1
    fi

    if printf '%s' "$ls_output" | grep -qiE "daemon.*not running|connection refused|Is the docker daemon running"; then
        echo "[ERROR] Docker daemon is not running" >&2
        echo "" >&2
        echo "  docker sandbox ls output:" >&2
        printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
        echo "" >&2
        echo "Please start Docker Desktop and try again." >&2
        echo "" >&2
        return 1
    fi

    # Unknown error - fail OPEN with warning
    echo "[WARN] Could not verify Docker sandbox availability" >&2
    echo "" >&2
    echo "  docker sandbox ls output:" >&2
    printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
    echo "" >&2
    echo "  Attempting to proceed - sandbox run may fail if not available." >&2
    echo "  Ensure Docker Desktop 4.50+ is installed with sandbox feature enabled." >&2
    echo "  See: https://docs.docker.com/desktop/features/sandbox/" >&2
    echo "" >&2
    return 2
}

# ==============================================================================
# Preflight checks
# ==============================================================================

# Preflight checks for sandbox/isolation before container start
# Arguments: $1 = force flag ("true" to skip checks)
# Returns: 0=proceed, 1=block
_containai_preflight_checks() {
    local force_flag="$1"
    local sandbox_rc isolation_rc

    if [[ "$force_flag" == "true" ]]; then
        echo "[WARN] Skipping sandbox availability check (--force)" >&2
        if [[ "${CONTAINAI_REQUIRE_ISOLATION:-0}" == "1" ]]; then
            echo "*** WARNING: Bypassing isolation requirement with --force" >&2
            echo "*** Running without verified isolation may expose host system" >&2
        fi
        return 0
    fi

    # Guard calls for set -e safety (non-zero is valid control flow)
    if _containai_check_sandbox; then
        sandbox_rc=0
    else
        sandbox_rc=$?
    fi
    if [[ $sandbox_rc -eq 1 ]]; then
        return 1
    fi

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
# Arguments: $1 = volume name, $2 = quiet flag (optional, default false)
# Returns: 0 on success, 1 on failure
_containai_ensure_volumes() {
    local volume_name="$1"
    local quiet="${2:-false}"

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

    if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
        if [[ "$quiet" != "true" ]]; then
            echo "Creating volume: $volume_name"
        fi
        if ! docker volume create "$volume_name" >/dev/null; then
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
    if ! label_value=$(docker inspect --format '{{ index .Config.Labels "containai.sandbox" }}' "$container_name" 2>/dev/null); then
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
    if [[ "$label_value" == "containai" ]]; then
        return 0
    fi

    # Fallback: check image (for containers without label)
    if [[ -z "$label_value" ]]; then
        image_name="$(_containai_get_container_image "$container_name")"
        if [[ "$image_name" == "$_CONTAINAI_IMAGE" ]]; then
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
    echo "  Expected label 'containai.sandbox': containai" >&2
    echo "  Actual label 'containai.sandbox':   ${label_value:-<not set>}" >&2
    echo "  Expected image:                     $_CONTAINAI_IMAGE" >&2
    echo "  Actual image:                       ${actual_image:-<unknown>}" >&2
    echo "" >&2
    echo "This is a name collision with a container not managed by ContainAI." >&2
    echo "To recreate as a ContainAI-managed sandbox container, run: cai --restart" >&2
    echo "" >&2
    return 1
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

    # Safety check for --mount-docker-socket
    if [[ "$mount_docker_socket" == "true" && "$please_root_my_host" != "true" ]]; then
        echo "" >&2
        echo "[ERROR] --mount-docker-socket requires --please-root-my-host acknowledgement" >&2
        echo "" >&2
        echo "Mounting the Docker socket grants FULL ROOT ACCESS to your host system." >&2
        echo "This COMPLETELY DEFEATS the purpose of running in a sandbox." >&2
        echo "" >&2
        return 1
    fi

    # Early docker check
    if ! command -v docker >/dev/null 2>&1; then
        echo "[ERROR] Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Resolve workspace
    local workspace_resolved
    workspace_resolved="${workspace:-$PWD}"
    if ! workspace_resolved=$(cd "$workspace_resolved" 2>/dev/null && pwd); then
        echo "[ERROR] Workspace path does not exist: ${workspace:-$PWD}" >&2
        return 1
    fi

    # Get container name
    if [[ -z "$container_name" ]]; then
        container_name="$(_containai_container_name)"
    fi
    if [[ "$quiet_flag" != "true" ]]; then
        echo "Container: $container_name"
    fi

    # Check container state - guard for set -e safety (non-zero is valid control flow)
    local container_state exists_rc sandbox_rc
    if _containai_container_exists "$container_name"; then
        exists_rc=0
    else
        exists_rc=$?
    fi

    if [[ $exists_rc -eq 0 ]]; then
        # Use || true for set -e safety (success already confirmed by exists check)
        container_state=$(docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null) || container_state=""
    elif [[ $exists_rc -eq 1 ]]; then
        container_state="none"
    else
        # Docker error - run sandbox check for actionable messaging
        # Guard for set -e safety (non-zero is valid control flow)
        if _containai_check_sandbox; then
            sandbox_rc=0
        else
            sandbox_rc=$?
        fi
        if [[ $sandbox_rc -eq 1 ]]; then
            return 1
        fi
        echo "[ERROR] Docker error checking container state" >&2
        return 1
    fi

    # Handle --restart flag
    if [[ "$restart_flag" == "true" && "$container_state" != "none" ]]; then
        local is_ours_rc
        # Guard for set -e safety (non-zero is valid control flow)
        if _containai_is_our_container "$container_name"; then
            is_ours_rc=0
        else
            is_ours_rc=$?
        fi
        if [[ $is_ours_rc -ne 0 ]]; then
            echo "[ERROR] Cannot restart - container '$container_name' was not created by ContainAI" >&2
            echo "Remove the conflicting container manually if needed: docker rm -f '$container_name'" >&2
            return 1
        fi
        if [[ "$quiet_flag" != "true" ]]; then
            echo "Stopping existing container..."
        fi
        # Stop container, ignoring "not running" errors but surfacing others
        local stop_output
        stop_output="$(docker stop "$container_name" 2>&1)" || {
            if ! printf '%s' "$stop_output" | grep -qiE "is not running"; then
                echo "$stop_output" >&2
            fi
        }
        # Remove container, ignoring "not found" errors but surfacing others
        local rm_output
        rm_output="$(docker rm "$container_name" 2>&1)" || {
            if ! printf '%s' "$rm_output" | grep -qiE "no such container|not found"; then
                echo "$rm_output" >&2
                return 1
            fi
        }
        container_state="none"
    fi

    # Handle shell mode with stopped container
    if [[ "$shell_flag" == "true" ]] && [[ "$container_state" == "exited" || "$container_state" == "created" ]]; then
        if ! _containai_check_container_ownership "$container_name"; then
            return 1
        fi
        if ! _containai_preflight_checks "$force_flag"; then
            return 1
        fi
        if [[ "$quiet_flag" != "true" ]]; then
            echo "Recreating container for shell access..."
        fi
        docker rm "$container_name" >/dev/null 2>&1
        container_state="none"
    fi

    # Check image exists when creating new container
    if [[ "$container_state" == "none" ]]; then
        local image_inspect
        # Use if ! pattern for set -e safety
        if ! image_inspect=$(docker image inspect "$_CONTAINAI_IMAGE" 2>&1); then
            if printf '%s' "$image_inspect" | grep -qiE "no such image|not found"; then
                echo "[ERROR] Image '$_CONTAINAI_IMAGE' not found" >&2
                echo "Please build the image first: agent-sandbox/build.sh" >&2
            else
                echo "$image_inspect" >&2
            fi
            return 1
        fi
    fi

    case "$container_state" in
        running)
            if ! _containai_check_container_ownership "$container_name"; then
                return 1
            fi
            if ! _containai_check_volume_match "$container_name" "$data_volume" "$quiet_flag"; then
                # Volume mismatch: block unless caller opted for warn-only
                if [[ "$volume_mismatch_warn" != "true" ]]; then
                    echo "[ERROR] Volume mismatch prevents attachment. Use --restart to recreate." >&2
                    return 1
                fi
                # Warn mode: message already printed by check, proceed
            fi
            if [[ "$quiet_flag" != "true" ]]; then
                echo "Attaching to running container..."
            fi
            docker exec -it --user agent -w /home/agent/workspace "$container_name" bash
            ;;
        exited|created)
            if ! _containai_check_container_ownership "$container_name"; then
                return 1
            fi
            if ! _containai_check_volume_match "$container_name" "$data_volume" "$quiet_flag"; then
                # Volume mismatch: block unless caller opted for warn-only
                if [[ "$volume_mismatch_warn" != "true" ]]; then
                    echo "[ERROR] Volume mismatch prevents start. Use --restart to recreate." >&2
                    return 1
                fi
                # Warn mode: message already printed by check, proceed
            fi
            if ! _containai_preflight_checks "$force_flag"; then
                return 1
            fi
            if [[ "$quiet_flag" != "true" ]]; then
                echo "Starting stopped container..."
            fi
            docker start -ai "$container_name"
            ;;
        none)
            if ! _containai_preflight_checks "$force_flag"; then
                return 1
            fi
            if ! _containai_ensure_volumes "$data_volume" "$quiet_flag"; then
                return 1
            fi

            local -a vol_args=()
            vol_args+=("-v" "$data_volume:/mnt/agent-data")

            # Check sandbox run help for supported flags - use if ! pattern for set -e safety
            local sandbox_help
            if ! sandbox_help=$(docker sandbox run --help 2>&1); then
                echo "[ERROR] docker sandbox run is not available" >&2
                return 1
            fi

            if [[ "$quiet_flag" != "true" ]]; then
                echo "Starting new sandbox container..."
            fi

            local -a args=()
            args+=(--name "$container_name")

            # Add label if supported - ALWAYS use new label for creation
            if printf '%s' "$sandbox_help" | grep -q -- '--label'; then
                args+=(--label "$_CONTAINAI_LABEL")
            fi

            args+=("${vol_args[@]}")

            local vol env_var
            for vol in "${extra_volumes[@]}"; do
                args+=(-v "$vol")
            done
            for env_var in "${env_vars[@]}"; do
                args+=(-e "$env_var")
            done

            if [[ "$shell_flag" == "true" ]]; then
                args+=(--detached --quiet)
            else
                if [[ "$detached_flag" == "true" ]]; then
                    args+=(--detached)
                fi
                if [[ "$quiet_flag" == "true" ]]; then
                    args+=(--quiet)
                fi
            fi
            if [[ "$debug_flag" == "true" ]]; then
                args+=(--debug)
            fi
            if [[ "$mount_docker_socket" == "true" ]]; then
                args+=(--mount-docker-socket)
            fi

            args+=(--workspace "$workspace_resolved")
            args+=(--template "$_CONTAINAI_IMAGE")
            args+=(--credentials none)
            args+=(claude)

            if [[ ${#agent_args[@]} -gt 0 ]]; then
                args+=("${agent_args[@]}")
            fi

            if [[ "$shell_flag" == "true" ]]; then
                docker sandbox run "${args[@]}" >/dev/null
                docker exec -it --user agent -w /home/agent/workspace "$container_name" bash
            else
                docker sandbox run "${args[@]}"
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

# Interactive container stop selection
# Finds all ContainAI containers (by label or ancestor image) and prompts user
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

    local containers labeled_containers ancestor_containers

    # Use || true for set -e safety - empty result is valid
    labeled_containers=$(docker ps -a --filter "label=$_CONTAINAI_LABEL" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || labeled_containers=""
    ancestor_containers=$(docker ps -a --filter "ancestor=$_CONTAINAI_IMAGE" --format "{{.Names}}\t{{.Status}}" 2>/dev/null) || ancestor_containers=""

    # Use sed instead of grep -v for set -e safety (grep returns 1 on no match)
    containers=$(printf '%s\n%s' "$labeled_containers" "$ancestor_containers" | sed -e '/^$/d' | sort -t$'\t' -k1,1 -u)

    if [[ -z "$containers" ]]; then
        echo "No ContainAI containers found."
        return 0
    fi

    echo "ContainAI containers:"
    echo ""

    local i=0
    local names=()
    local name status
    while IFS=$'\t' read -r name status; do
        i=$((i + 1))
        names+=("$name")
        printf "  %d) %s (%s)\n" "$i" "$name" "$status"
    done <<< "$containers"

    if [[ "$stop_all_flag" == "true" ]]; then
        echo ""
        echo "Stopping all containers (--all flag)..."
        local container_to_stop
        for container_to_stop in "${names[@]}"; do
            echo "Stopping: $container_to_stop"
            docker stop "$container_to_stop" >/dev/null 2>&1 || true
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

    local to_stop=()

    if [[ "$selection" == "all" || "$selection" == "ALL" ]]; then
        to_stop=("${names[@]}")
    else
        local num
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#names[@]}" ]]; then
                to_stop+=("${names[$((num - 1))]}")
            else
                echo "[WARN] Invalid selection: $num" >&2
            fi
        done
    fi

    if [[ ${#to_stop[@]} -eq 0 ]]; then
        echo "No containers selected."
        return 0
    fi

    echo ""
    local container_to_stop
    for container_to_stop in "${to_stop[@]}"; do
        echo "Stopping: $container_to_stop"
        docker stop "$container_to_stop" >/dev/null 2>&1 || true
    done

    echo "Done."
}

return 0
