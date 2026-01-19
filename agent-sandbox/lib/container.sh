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
#   _containai_stop_all           - Stop all ContainAI containers
#
# Container inspection helpers:
#   _containai_get_container_label      - Get containai.sandbox label value
#   _containai_get_container_image      - Get container image name
#   _containai_get_container_data_volume - Get mounted data volume name
#   _containai_is_our_container         - Check if container belongs to ContainAI
#   _containai_check_container_ownership - Check ownership with error messaging
#   _containai_check_volume_match       - Check if volume matches desired
#
# Constants:
#   _CONTAINAI_IMAGE              - Default image name
#   _CONTAINAI_LABEL              - Container label for ContainAI ownership
#   _CONTAINAI_LEGACY_LABEL       - Legacy label for transition period
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
# Legacy label for transition period (discover containers created with old label)
: "${_CONTAINAI_LEGACY_LABEL:=asb.sandbox=agent-sandbox}"

# ==============================================================================
# Container naming
# ==============================================================================

# Generate sanitized container name from git repo/branch or directory
# Format: <repo>-<branch> (sanitized, no prefix per original _asb_container_name)
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
    # Use sandbox-<dirname> pattern, not generic sandbox-container
    # Apply same sanitization as main path for consistency
    if [[ -z "$name" ]]; then
        local dir_fallback
        dir_fallback="$(basename "$(pwd)")"
        # Sanitize: lowercase, replace non-alphanumeric with dash, collapse dashes
        dir_fallback="$(printf '%s' "$dir_fallback" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-*//;s/-*$//')"
        if [[ -n "$dir_fallback" ]]; then
            name="sandbox-$dir_fallback"
            # Truncate to 63 characters (Docker limit)
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
# Returns: 0=isolated (detected), 1=not isolated (definite), 2=unknown (ambiguous)
_containai_check_isolation() {
    local runtime rootless userns

    # Use docker info --format for reliable structured output (proven approach from aliases.sh)
    runtime=$(docker info --format '{{.DefaultRuntime}}' 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$runtime" ]]; then
        echo "[WARN] Unable to determine isolation status" >&2
        return 2
    fi

    rootless=$(docker info --format '{{.Rootless}}' 2>/dev/null)
    userns=$(docker info --format '{{.SecurityOptions}}' 2>/dev/null)

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
    # Capture both stdout and stderr for proper error analysis
    # Use if ! pattern to handle set -e safely
    local ls_output
    if ls_output="$(docker sandbox ls 2>&1)"; then
        return 0
    fi

    # Sandbox ls failed - analyze the error to provide actionable feedback
    # Check for feature disabled / requirements not met FIRST (before empty list check)
    # Match broad patterns per spec, but exclude "no sandbox" empty list messages
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

    # Check for "no sandboxes exist" case - only treat as success if exit code was 0
    # (handled above) or if message clearly indicates functional sandbox support
    # With non-zero exit, treat as unknown to be safe
    if printf '%s' "$ls_output" | grep -qiE "no sandboxes found|0 sandboxes|sandbox list is empty"; then
        # Non-zero exit with empty list message - treat as unknown, not success
        echo "[WARN] docker sandbox ls returned empty list with error code" >&2
        echo "  Attempting to proceed - sandbox may be functional." >&2
        echo "" >&2
        return 2
    fi

    # Check for command not found / not available errors (definite "no")
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

    # Check for permission denied (separate from daemon not running)
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

    # Check for daemon not running (tighter match, excludes permission denied)
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

    # Unknown error - fail OPEN with warning (per spec: don't block on unknown)
    echo "[WARN] Could not verify Docker sandbox availability" >&2
    echo "" >&2
    echo "  docker sandbox ls output:" >&2
    printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
    echo "" >&2
    echo "  Attempting to proceed - sandbox run may fail if not available." >&2
    echo "  Ensure Docker Desktop 4.50+ is installed with sandbox feature enabled." >&2
    echo "  See: https://docs.docker.com/desktop/features/sandbox/" >&2
    echo "" >&2
    return 2  # Unknown - proceed with warning
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
        # Handle CONTAINAI_REQUIRE_ISOLATION with --force bypass
        if [[ "${CONTAINAI_REQUIRE_ISOLATION:-0}" == "1" ]]; then
            echo "*** WARNING: Bypassing isolation requirement with --force" >&2
            echo "*** Running without verified isolation may expose host system" >&2
        fi
        return 0
    fi

    _containai_check_sandbox
    sandbox_rc=$?
    if [[ $sandbox_rc -eq 1 ]]; then
        return 1  # Definite "no" - block
    fi
    # rc=0 (yes) or rc=2 (unknown) - proceed

    # Best-effort isolation detection
    _containai_check_isolation
    isolation_rc=$?

    # Handle CONTAINAI_REQUIRE_ISOLATION environment variable
    if [[ "${CONTAINAI_REQUIRE_ISOLATION:-0}" == "1" ]]; then
        case $isolation_rc in
            0)
                # Isolated - proceed normally
                ;;
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
# Returns: 0=exists, 1=does not exist or error
_containai_container_exists() {
    local container_name="$1"
    local inspect_output

    inspect_output=$(docker inspect "$container_name" 2>&1)
    if [[ $? -eq 0 ]]; then
        return 0
    fi

    # Check if it's "no such" vs other errors
    if printf '%s' "$inspect_output" | grep -qiE "no such object|not found|error.*no such"; then
        return 1  # Container doesn't exist
    fi

    # Docker error (daemon down, permission, etc.) - treat as "doesn't exist" for safety
    return 1
}

# Get the containai.sandbox label value from a container (empty if not found or error)
# Also checks legacy asb.sandbox label for transition period
_containai_get_container_label() {
    local container_name="$1"
    local label_value

    # First try new label
    label_value=$(docker inspect --format '{{ index .Config.Labels "containai.sandbox" }}' "$container_name" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$label_value" ]] && [[ "$label_value" != "<no value>" ]]; then
        printf '%s' "$label_value"
        return 0
    fi

    # Fall back to legacy label for transition period
    label_value=$(docker inspect --format '{{ index .Config.Labels "asb.sandbox" }}' "$container_name" 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$label_value" ]] && [[ "$label_value" != "<no value>" ]]; then
        printf '%s' "$label_value"
        return 0
    fi

    echo ""
}

# Get the image name of a container (empty if not found or error)
_containai_get_container_image() {
    local container_name="$1"
    local image_name

    image_name=$(docker inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
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

    # Query mount source for /mnt/agent-data destination
    volume_name=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/mnt/agent-data"}}{{.Name}}{{end}}{{end}}' "$container_name" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        printf '%s' "$volume_name"
    else
        echo ""
    fi
}

# Verify container was created by ContainAI (has our label or uses our image)
# Returns: 0=ours (label or image matches), 1=foreign (no match)
# Falls back to image name verification if labels not supported
_containai_is_our_container() {
    local container_name="$1"
    local label_value

    # First check if container exists
    if ! _containai_container_exists "$container_name"; then
        return 1
    fi

    label_value="$(_containai_get_container_label "$container_name")"

    # Primary check: new label match
    if [[ "$label_value" == "containai" ]]; then
        return 0
    fi

    # Check legacy label value for transition period
    if [[ "$label_value" == "agent-sandbox" ]]; then
        return 0
    fi

    # Fallback: if no label, check if container uses our image
    # This handles cases where docker sandbox run doesn't support --label
    # or containers created before label support was added
    if [[ -z "$label_value" || "$label_value" == "<no value>" ]]; then
        local image_name
        image_name="$(_containai_get_container_image "$container_name")"
        if [[ "$image_name" == "$_CONTAINAI_IMAGE" ]]; then
            # Image matches - trust it as ours
            return 0
        fi
    fi

    return 1  # Definitely foreign
}

# Check container ownership with appropriate messaging
# Returns: 0=owned, 1=foreign (with error), 2=does not exist
_containai_check_container_ownership() {
    local container_name="$1"

    # First check if container exists
    if ! _containai_container_exists "$container_name"; then
        return 2  # Container doesn't exist - not an ownership error
    fi

    if _containai_is_our_container "$container_name"; then
        return 0
    fi

    # Foreign container
    local actual_label actual_image
    actual_label="$(_containai_get_container_label "$container_name")"
    actual_image="$(_containai_get_container_image "$container_name")"
    # Normalize empty or "<no value>" to "<not set>"
    if [[ -z "$actual_label" || "$actual_label" == "<no value>" ]]; then
        actual_label="<not set>"
    fi
    echo "[ERROR] Container '$container_name' exists but was not created by ContainAI" >&2
    echo "" >&2
    echo "  Expected label 'containai.sandbox': containai" >&2
    echo "  Actual label 'containai.sandbox':   ${actual_label}" >&2
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

    # If no volume mount found, don't block (might be legacy container)
    if [[ -z "$mounted_volume" ]]; then
        return 0
    fi

    # Check for mismatch
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
# Stop all containers
# ==============================================================================

# Interactive container stop selection
# Finds all ContainAI containers (by label or ancestor image) and prompts user
# Arguments: --all to stop all without prompting (non-interactive mode)
# Returns: 0 always
_containai_stop_all() {
    local stop_all_flag=false
    local arg

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --all)
                stop_all_flag=true
                ;;
        esac
    done

    local containers labeled_containers legacy_labeled_containers ancestor_containers

    # Find containers by new label (preferred)
    labeled_containers=$(docker ps -a --filter "label=$_CONTAINAI_LABEL" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)

    # Find containers by legacy label (transition period)
    legacy_labeled_containers=$(docker ps -a --filter "label=$_CONTAINAI_LEGACY_LABEL" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)

    # Also find by ancestor image (catches pre-label containers)
    ancestor_containers=$(docker ps -a --filter "ancestor=$_CONTAINAI_IMAGE" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)

    # Combine and deduplicate (sort -u on first field)
    containers=$(printf '%s\n%s\n%s' "$labeled_containers" "$legacy_labeled_containers" "$ancestor_containers" | grep -v '^$' | sort -t$'\t' -k1,1 -u)

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

    # Handle non-interactive mode
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

    # Check for interactive terminal
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
    read -r selection

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
