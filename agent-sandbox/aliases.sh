#!/usr/bin/env bash
# ==============================================================================
# Shell aliases for agent-sandbox
# ==============================================================================
# Provides:
#   asb           - Agent Sandbox: start/attach to sandbox container
#   asbd          - Agent Sandbox: start detached sandbox container
#   asb-stop-all  - Interactive selection to stop sandbox containers
#
# Usage: source aliases.sh
# ==============================================================================
# Note: No strict mode - this file is sourced into interactive shells

# Constants

_ASB_IMAGE="agent-sandbox:latest"
_ASB_LABEL="asb.sandbox=agent-sandbox"
_ASB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Volumes that asb creates/ensures (per spec)
_ASB_VOLUMES=(
        "sandbox-agent-data:/mnt/agent-data"
)


# Generate sanitized container name from git repo/branch or directory
_asb_container_name() {
    local name

    # Guard git usage to avoid "command not found" noise in minimal environments
    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        local repo_name branch_name
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

# Container isolation detection (conservative - prefer return 2 over false positive/negative)
# Returns: 0=isolated (detected), 1=not isolated (definite), 2=unknown (ambiguous)
_asb_check_isolation() {
    local runtime rootless info_output

    info_output=$(docker info --format '{{.DefaultRuntime}}\t{{.Rootless}}' 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$info_output" ]]; then
        echo "[WARN] Unable to determine isolation status" >&2
        return 2
    fi

    IFS=$'\t' read -r runtime rootless <<< "$info_output"

    if [[ "$runtime" == "sysbox-runc" ]]; then
        echo "[OK] Isolation: sysbox-runc" >&2
        return 0
    fi
    if [[ "$rootless" == "true" ]]; then
        echo "[OK] Isolation: rootless mode" >&2
        return 0
    fi

    if [[ "$runtime" == "runc" ]] && [[ "$rootless" == "false" ]]; then
        echo "[WARN] No isolation detected (default runtime)" >&2
        return 1
    fi

    echo "[WARN] Unable to determine isolation status" >&2
    return 2
}

# Check if docker sandbox is available
# Returns: 0=yes, 1=no (definite), 2=unknown (fail-open with warning)
_asb_check_sandbox() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Check if sandbox command is available by trying to run it
    # Capture both stdout and stderr for proper error analysis
    local ls_output ls_rc
    ls_output="$(docker sandbox ls 2>&1)"
    ls_rc=$?

    if [[ $ls_rc -eq 0 ]]; then
        return 0
    fi

    # Sandbox ls failed - analyze the error to provide actionable feedback
    # Check for feature disabled / requirements not met FIRST (before empty list check)
    # Match broad patterns per spec, but exclude "no sandbox" empty list messages
    if printf '%s' "$ls_output" | grep -qiE "feature.*disabled|not enabled|requirements.*not met|sandbox.*unavailable" && \
       ! printf '%s' "$ls_output" | grep -qiE "no sandboxes"; then
        echo "ERROR: Docker sandbox feature is not enabled" >&2
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
        echo "WARNING: docker sandbox ls returned empty list with error code" >&2
        echo "  Attempting to proceed - sandbox may be functional." >&2
        echo "" >&2
        return 2
    fi

    # Check for command not found / not available errors (definite "no")
    if printf '%s' "$ls_output" | grep -qiE "not recognized|unknown command|not a docker command|command not found"; then
        echo "ERROR: Docker sandbox is not available" >&2
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
        echo "ERROR: Permission denied accessing Docker" >&2
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
        echo "ERROR: Docker daemon is not running" >&2
        echo "" >&2
        echo "  docker sandbox ls output:" >&2
        printf '%s\n' "$ls_output" | sed 's/^/    /' >&2
        echo "" >&2
        echo "Please start Docker Desktop and try again." >&2
        echo "" >&2
        return 1
    fi

    # Unknown error - fail OPEN with warning (per spec: don't block on unknown)
    echo "WARNING: Could not verify Docker sandbox availability" >&2
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

# Preflight checks for sandbox/isolation before container start
# Returns: 0=proceed, 1=block
_asb_preflight_checks() {
    local force_flag="$1"
    local sandbox_rc isolation_rc

    if [[ "$force_flag" == "true" ]]; then
        echo "WARNING: Skipping sandbox availability check (--force)" >&2
        # Handle ASB_REQUIRE_ISOLATION with --force bypass
        if [[ "${ASB_REQUIRE_ISOLATION:-0}" == "1" ]]; then
            echo "*** WARNING: Bypassing isolation requirement with --force" >&2
            echo "*** Running without verified isolation may expose host system" >&2
        fi
        return 0
    fi

    _asb_check_sandbox
    sandbox_rc=$?
    if [[ $sandbox_rc -eq 1 ]]; then
        return 1  # Definite "no" - block
    fi
    # rc=0 (yes) or rc=2 (unknown) - proceed

    # Best-effort isolation detection
    _asb_check_isolation
    isolation_rc=$?

    # Handle ASB_REQUIRE_ISOLATION environment variable
    if [[ "${ASB_REQUIRE_ISOLATION:-0}" == "1" ]]; then
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

# Get the asb.sandbox label value from a container (empty if not found)
_asb_get_container_label() {
    local container_name="$1"
    docker inspect --format '{{ index .Config.Labels "asb.sandbox" }}' "$container_name" 2>/dev/null || echo ""
}

# Get the image name of a container
_asb_get_container_image() {
    local container_name="$1"
    docker inspect --format '{{.Config.Image}}' "$container_name" 2>/dev/null || echo ""
}

# Verify container was created by asb (has our label or uses our image)
# Returns: 0=confirmed (label matches), 1=foreign (no match), 2=ambiguous (image matches but no label)
# Falls back to image name verification if labels not supported
_asb_is_our_container() {
    local container_name="$1"
    local label_value
    label_value="$(_asb_get_container_label "$container_name")"

    # Primary check: label match
    if [[ "$label_value" == "agent-sandbox" ]]; then
        return 0
    fi

    # Fallback: if no label, check if container uses our image
    # This handles cases where docker sandbox run doesn't support --label
    # Returns 2 to indicate "probable match" requiring user confirmation via --restart
    if [[ -z "$label_value" || "$label_value" == "<no value>" ]]; then
        local image_name
        image_name="$(_asb_get_container_image "$container_name")"
        if [[ "$image_name" == "$_ASB_IMAGE" ]]; then
            # Image matches but no label - could be ours (pre-label) or foreign
            return 2  # Ambiguous - caller should warn
        fi
    fi

    return 1  # Definitely foreign
}

# Check container ownership with appropriate messaging
# Returns: 0=owned, 1=foreign (with error), 2=ambiguous (with warning)
_asb_check_container_ownership() {
    local container_name="$1"
    local ownership_rc

    _asb_is_our_container "$container_name"
    ownership_rc=$?

    if [[ $ownership_rc -eq 0 ]]; then
        return 0  # Confirmed ours
    elif [[ $ownership_rc -eq 2 ]]; then
        # Ambiguous - image matches but no label
        echo "WARNING: Container '$container_name' uses our image but lacks asb label" >&2
        echo "  This may be a container created before label support or a manual container." >&2
        echo "  Proceeding, but use 'asb --restart' to take ownership if needed." >&2
        echo "" >&2
        return 0  # Proceed with warning
    else
        # Foreign container
        local actual_label actual_image
        actual_label="$(_asb_get_container_label "$container_name")"
        actual_image="$(_asb_get_container_image "$container_name")"
        # Normalize empty or "<no value>" to "<not set>"
        if [[ -z "$actual_label" || "$actual_label" == "<no value>" ]]; then
            actual_label="<not set>"
        fi
        echo "ERROR: Container '$container_name' exists but was not created by asb" >&2
        echo "" >&2
        echo "  Expected label 'asb.sandbox': agent-sandbox" >&2
        echo "  Actual label 'asb.sandbox':   ${actual_label:-<not set>}" >&2
        echo "  Expected image:               $_ASB_IMAGE" >&2
        echo "  Actual image:                 ${actual_image:-<unknown>}" >&2
        echo "" >&2
        echo "This is a name collision with a container not managed by asb." >&2
        echo "To recreate as a asb-managed sandbox container, run: asb --restart" >&2
        echo "" >&2
        return 1
    fi
}

# Ensure required volumes exist with correct permissions
# Returns non-zero on failure
_asb_ensure_volumes() {
    local volume_name vol_spec



    # Create asb-managed volumes if missing
    for vol_spec in "${_ASB_VOLUMES[@]}"; do
        volume_name="${vol_spec%%:*}"

        if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
            echo "Creating volume: $volume_name"
            if ! docker volume create "$volume_name" >/dev/null; then
                echo "ERROR: Failed to create volume $volume_name" >&2
                return 1
            fi
        fi
    done


}

# Agent Sandbox - main function
asb() {
    local restart_flag=false
    local force_flag=false
    local container_name
    local detached_flag=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --help|-h)
                echo "Usage: asb [--restart] [--force] [--detached]"
                echo ""
                echo "Start or attach to a agent-sandbox container."
                echo ""
                echo "Options:"
                echo "  --detached Start as detached container"
                echo "  --restart  Force recreate container even if running"
                echo "  --force    Skip sandbox availability check (not recommended)"
                echo "  --help     Show this help"
                echo ""
                echo "Container naming: <repo>-<branch> (sanitized, max 63 chars)"
                echo "Falls back to directory name if not in a git repo."
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use 'asb --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Early prereq check: is docker available?
    # This ensures docker errors get routed through our messaging
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Get container name first (we need it to check container state)
    container_name="$(_asb_container_name)"
    echo "Container: $container_name"

    # Check container state (distinguish not-found from actual errors)
    local container_state container_inspect_output container_inspect_rc
    container_inspect_output="$(docker inspect --format '{{.State.Status}}' "$container_name" 2>&1)"
    container_inspect_rc=$?
    if [[ $container_inspect_rc -eq 0 ]]; then
        container_state="$container_inspect_output"
    elif printf '%s' "$container_inspect_output" | grep -qiE "no such object|not found|error.*no such"; then
        container_state="none"
    else
        # Docker error - route through sandbox check for actionable messaging
        # This handles daemon down, permission denied, etc.
        _asb_check_sandbox || return 1
        # If sandbox check passed but inspect still failed, surface the error
        echo "$container_inspect_output" >&2
        return 1
    fi

    # Handle --restart flag
    if [[ "$restart_flag" == "true" && "$container_state" != "none" ]]; then
        # Check ownership before removing - prevent accidentally deleting foreign containers
        _asb_is_our_container "$container_name"
        local ownership_rc=$?
        if [[ $ownership_rc -eq 1 ]]; then
            # Definitely foreign - block unless user explicitly confirms
            local actual_label actual_image
            actual_label="$(_asb_get_container_label "$container_name")"
            actual_image="$(_asb_get_container_image "$container_name")"
            if [[ -z "$actual_label" || "$actual_label" == "<no value>" ]]; then
                actual_label="<not set>"
            fi
            echo "ERROR: Cannot restart - container '$container_name' was not created by asb" >&2
            echo "" >&2
            echo "  Expected label 'asb.sandbox': agent-sandbox" >&2
            echo "  Actual label 'asb.sandbox':   $actual_label" >&2
            echo "  Expected image:               $_ASB_IMAGE" >&2
            echo "  Actual image:                 ${actual_image:-<unknown>}" >&2
            echo "" >&2
            echo "To avoid data loss, asb will not delete containers it didn't create." >&2
            echo "Remove the conflicting container manually if needed:" >&2
            echo "  docker rm -f '$container_name'" >&2
            echo "" >&2
            return 1
        elif [[ $ownership_rc -eq 2 ]]; then
            # Ambiguous - warn but proceed since --restart is explicit
            echo "WARNING: Container '$container_name' uses our image but lacks our label" >&2
            echo "  Proceeding with --restart as requested." >&2
            echo "" >&2
        fi

        echo "Stopping existing container..."
        # Let errors surface for stop (only ignore "not running")
        local stop_output
        stop_output="$(docker stop "$container_name" 2>&1)" || {
            if ! printf '%s' "$stop_output" | grep -qiE "is not running"; then
                echo "$stop_output" >&2
            fi
        }
        # Let errors surface for rm (only ignore "not found")
        local rm_output
        rm_output="$(docker rm "$container_name" 2>&1)" || {
            if ! printf '%s' "$rm_output" | grep -qiE "no such container|not found"; then
                echo "$rm_output" >&2
                return 1
            fi
        }
        container_state="none"
    fi

    # Check if image exists only when we need to create a new container
    if [[ "$container_state" == "none" ]]; then
        local inspect_output inspect_rc
        inspect_output="$(docker image inspect "$_ASB_IMAGE" 2>&1)"
        inspect_rc=$?
        if [[ $inspect_rc -ne 0 ]]; then
            # Check if it's "not found" vs other errors (daemon down, etc.)
            if printf '%s' "$inspect_output" | grep -qiE "no such image|not found"; then
                echo "ERROR: Image '$_ASB_IMAGE' not found" >&2
                echo "Please build the image first: ${_ASB_SCRIPT_DIR}/build.sh" >&2
            else
                # Let actual docker error surface
                echo "$inspect_output" >&2
            fi
            return 1
        fi
    fi

    case "$container_state" in
        running)
            # Verify this container was created by asb (has our label or image)
            if ! _asb_check_container_ownership "$container_name"; then
                return 1
            fi
            # Warn if sandbox unavailable (non-blocking for running containers)
            if ! _asb_check_sandbox; then
                if [[ "$force_flag" != "true" ]]; then
                    echo "WARNING: Sandbox unavailable but attaching to existing container" >&2
                    echo "  Use --force to suppress this warning, or --restart to recreate as sandbox" >&2
                    echo "" >&2
                fi
            fi
            echo "Attaching to running container..."
            # NOTE: Using docker exec (not docker sandbox exec) is intentional.
            # Docker Desktop sandboxes are regular containers accessible via standard docker commands.
            # The sandbox provides isolation at creation time; exec/start work normally.
            docker exec -it --user agent -w /home/agent/workspace "$container_name" bash
            ;;
        exited|created)
            # Verify this container was created by asb (has our label or image)
            if ! _asb_check_container_ownership "$container_name"; then
                return 1
            fi
            # Check sandbox availability before starting
            if ! _asb_preflight_checks "$force_flag"; then
                return 1
            fi
            echo "Starting stopped container..."
            docker start -ai "$container_name"
            ;;
        none)
            # Check sandbox availability before creating new container
            if ! _asb_preflight_checks "$force_flag"; then
                return 1
            fi

            # Ensure volumes exist (asb-managed)
            if ! _asb_ensure_volumes; then
                echo "ERROR: Volume setup failed. Cannot start container." >&2
                return 1
            fi

            # Build volume arguments (asb-managed volumes)
            local vol_args=()
            for vol_spec in "${_ASB_VOLUMES[@]}"; do
                vol_args+=("-v" "$vol_spec")
            done

            # Get sandbox run help to check supported flags
            local sandbox_help sandbox_help_rc
            sandbox_help="$(docker sandbox run --help 2>&1)"
            sandbox_help_rc=$?

            # Check if sandbox run help failed (indicates sandbox unavailable)
            if [[ $sandbox_help_rc -ne 0 ]]; then
                echo "ERROR: docker sandbox run is not available" >&2
                echo "" >&2
                echo "  docker sandbox run --help output:" >&2
                printf '%s\n' "$sandbox_help" | sed 's/^/    /' >&2
                echo "" >&2
                echo "Please ensure Docker Desktop 4.50+ with sandbox feature is enabled." >&2
                return 1
            fi

            local detached_args=()
            if [[ "$detached_flag" == "true" ]]; then
                detached_args=(--detached)
            fi

            echo "Starting new sandbox container..."

            # Check if docker sandbox supports --label
            local args=()
            if docker sandbox run --help 2>&1 | grep -q '\-\-label'; then
                args=(
                    --name "$container_name"
                    --label "$_ASB_LABEL"
                    "${vol_args[@]}"
                    "${detached_args[@]}"
                    --template "$_ASB_IMAGE"
                    claude
                )
            else
                args=(
                    --name "$container_name"
                    "${vol_args[@]}"
                    "${detached_args[@]}"
                    --template "$_ASB_IMAGE"
                    claude
                )
            fi

            #printf 'Running command: docker sandbox run'
            #printf ' %q' "${args[@]}"
            #sprintf '\n'

            docker sandbox run "${args[@]}"

            ;;
        *)
            echo "Unexpected container state: $container_state" >&2
            return 1
            ;;
    esac
}

# Interactive container stop selection
asb-stop-all() {
    local containers labeled_containers ancestor_containers

    # Find containers by label (preferred, works across rebuilds)
    labeled_containers=$(docker ps -a --filter "label=$_ASB_LABEL" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)

    # Also find by ancestor image (catches pre-label containers)
    ancestor_containers=$(docker ps -a --filter "ancestor=$_ASB_IMAGE" --format "{{.Names}}\t{{.Status}}" 2>/dev/null || true)

    # Combine and deduplicate (sort -u on first field)
    containers=$(printf '%s\n%s' "$labeled_containers" "$ancestor_containers" | grep -v '^$' | sort -t$'\t' -k1,1 -u)

    if [[ -z "$containers" ]]; then
        echo "No agent-sandbox containers found."
        return 0
    fi

    echo "Agent Sandbox containers:"
    echo ""

    local i=0
    local names=()
    while IFS=$'\t' read -r name status; do
        i=$((i + 1))
        names+=("$name")
        printf "  %d) %s (%s)\n" "$i" "$name" "$status"
    done <<< "$containers"

    echo ""
    echo "Enter numbers to stop (space-separated), 'all', or 'q' to quit:"
    read -r selection

    if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
        echo "Cancelled."
        return 0
    fi

    local to_stop=()

    if [[ "$selection" == "all" || "$selection" == "ALL" ]]; then
        to_stop=("${names[@]}")
    else
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [[ "$num" -ge 1 ]] && [[ "$num" -le "${#names[@]}" ]]; then
                to_stop+=("${names[$((num - 1))]}")
            else
                echo "Invalid selection: $num" >&2
            fi
        done
    fi

    if [[ ${#to_stop[@]} -eq 0 ]]; then
        echo "No containers selected."
        return 0
    fi

    echo ""
    for name in "${to_stop[@]}"; do
        echo "Stopping: $name"
        docker stop "$name" >/dev/null 2>&1 || true
    done

    echo "Done."
}

alias asbd='asb --detached'

# Return 0 when sourced, exit 1 when executed directly
return 0 2>/dev/null || { echo "This script should be sourced, not executed: source aliases.sh" >&2; exit 1; }
