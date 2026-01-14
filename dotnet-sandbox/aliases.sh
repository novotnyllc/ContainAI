#!/usr/bin/env bash
# ==============================================================================
# Shell aliases for dotnet-sandbox
# ==============================================================================
# Provides:
#   csd           - Claude Sandbox Dotnet: start/attach to sandbox container
#   csd-stop-all  - Interactive selection to stop sandbox containers
#
# Usage: source aliases.sh
# ==============================================================================
# Note: No strict mode - this file is sourced into interactive shells

# Constants (guarded for safe re-sourcing)
if [[ -z "${_CSD_IMAGE-}" ]]; then
    _CSD_IMAGE="dotnet-sandbox:latest"
    _CSD_LABEL="csd.sandbox=dotnet-sandbox"
    _CSD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # Volumes that csd creates/ensures (per spec)
    _CSD_VOLUMES=(
        "dotnet-sandbox-vscode:/home/agent/.vscode-server"
        "dotnet-sandbox-nuget:/home/agent/.nuget"
        "dotnet-sandbox-gh:/home/agent/.config/gh"
        "docker-claude-plugins:/home/agent/.claude/plugins"
    )
    # Additional volumes to mount (managed elsewhere, not created by csd)
    _CSD_MOUNT_ONLY_VOLUMES=(
        "docker-claude-sandbox-data:/mnt/claude-data"
    )
fi

# Generate sanitized container name from git repo/branch or directory
_csd_container_name() {
    local name

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
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

    printf '%s' "$name"
}

# Check if docker sandbox is available
_csd_check_sandbox() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Check if sandbox command is available by trying to run it
    # docker sandbox ls succeeds (exit 0) if sandbox feature is available
    if docker sandbox ls >/dev/null 2>&1; then
        return 0
    fi

    # Sandbox ls failed - check if it's because the command doesn't exist
    local help_output
    help_output="$(docker sandbox --help 2>&1)" || true

    # Match known error patterns for missing subcommand
    if printf '%s' "$help_output" | grep -qiE "not recognized|unknown command|not a docker command"; then
        echo "ERROR: Docker sandbox is not available" >&2
        echo "" >&2
        echo "Docker sandbox requires Docker Desktop 4.29+ with sandbox feature enabled." >&2
        echo "Please ensure you have:" >&2
        echo "  1. Docker Desktop 4.29 or later installed" >&2
        echo "  2. Docker sandbox feature enabled in Settings > Features in development" >&2
        echo "" >&2
        return 1
    fi

    # Help output looks like valid sandbox help, so the command exists
    # but ls may have failed for another reason (e.g., no sandboxes yet, daemon issues)
    # Per spec: treat as available if help mentions sandbox-specific commands
    if printf '%s' "$help_output" | grep -qE "sandbox.*run|Create.*sandbox|list.*sandbox"; then
        # Help mentions sandbox-specific commands, likely valid
        return 0
    fi

    # Can't confirm sandbox is available - warn but proceed (fail-open per fn-1.11 intent)
    echo "WARNING: Unable to verify Docker sandbox availability" >&2
    echo "docker sandbox ls failed; proceeding anyway." >&2
    return 0
}

# Ensure required volumes exist with correct permissions
_csd_ensure_volumes() {
    local volume_name
    local volumes_to_fix=()

    # Check for mount-only volumes (warn if missing, but don't create)
    for vol_spec in "${_CSD_MOUNT_ONLY_VOLUMES[@]}"; do
        volume_name="${vol_spec%%:*}"
        if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
            echo "WARNING: Volume '$volume_name' not found" >&2
            echo "  Credentials/settings may not work. Run: claude/sync-plugins.sh" >&2
        fi
    done

    # Create csd-managed volumes if missing
    for vol_spec in "${_CSD_VOLUMES[@]}"; do
        volume_name="${vol_spec%%:*}"

        if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
            echo "Creating volume: $volume_name"
            docker volume create "$volume_name" >/dev/null
            volumes_to_fix+=("$volume_name")
        fi
    done

    # Fix permissions on volumes (if image is available)
    # Skip permission fixing if image not built yet (user builds first)
    if ! docker image inspect "$_CSD_IMAGE" >/dev/null 2>&1; then
        if [[ ${#volumes_to_fix[@]} -gt 0 ]]; then
            echo "Note: Skipping permission fix (image not built yet)"
        fi
        return 0
    fi

    # Fix permissions on newly created volumes
    for volume_name in "${volumes_to_fix[@]}"; do
        echo "Setting permissions on: $volume_name"
        docker run --rm -u root -v "${volume_name}:/data" "$_CSD_IMAGE" chown 1000:1000 /data
    done
}

# Claude Sandbox Dotnet - main function
csd() {
    local restart_flag=false
    local container_name

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --restart)
                restart_flag=true
                shift
                ;;
            --help|-h)
                echo "Usage: csd [--restart]"
                echo ""
                echo "Start or attach to a dotnet-sandbox container."
                echo ""
                echo "Options:"
                echo "  --restart  Force recreate container even if running"
                echo "  --help     Show this help"
                echo ""
                echo "Container naming: <repo>-<branch> (sanitized, max 63 chars)"
                echo "Falls back to directory name if not in a git repo."
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use 'csd --help' for usage" >&2
                return 1
                ;;
        esac
    done

    # Check sandbox availability
    if ! _csd_check_sandbox; then
        return 1
    fi

    # Check if image exists (let docker errors surface as-is)
    local inspect_output inspect_rc
    inspect_output="$(docker image inspect "$_CSD_IMAGE" 2>&1)"
    inspect_rc=$?
    if [[ $inspect_rc -ne 0 ]]; then
        # Check if it's "not found" vs other errors (daemon down, etc.)
        if printf '%s' "$inspect_output" | grep -qiE "no such image|not found"; then
            echo "ERROR: Image '$_CSD_IMAGE' not found" >&2
            echo "Please build the image first: ${_CSD_SCRIPT_DIR}/build.sh" >&2
        else
            # Let actual docker error surface
            echo "$inspect_output" >&2
        fi
        return 1
    fi

    # Get container name
    container_name="$(_csd_container_name)"
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
        # Actual error (daemon down, etc.) - surface it
        echo "$container_inspect_output" >&2
        return 1
    fi

    # Handle --restart flag
    if [[ "$restart_flag" == "true" && "$container_state" != "none" ]]; then
        echo "Stopping existing container..."
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        container_state="none"
    fi

    case "$container_state" in
        running)
            echo "Attaching to running container..."
            docker exec -it "$container_name" bash
            ;;
        exited|created)
            echo "Starting stopped container..."
            docker start -ai "$container_name"
            ;;
        none)
            # Ensure volumes exist (only csd-managed volumes)
            _csd_ensure_volumes

            # Build volume arguments (both csd-managed and mount-only volumes)
            local vol_args=()
            for vol_spec in "${_CSD_VOLUMES[@]}"; do
                vol_args+=("-v" "$vol_spec")
            done
            for vol_spec in "${_CSD_MOUNT_ONLY_VOLUMES[@]}"; do
                vol_args+=("-v" "$vol_spec")
            done

            # Check if sandbox supports port publishing
            local port_args=()
            if docker sandbox run --help 2>&1 | grep -qE '(^|[[:space:]])(-p|--publish)([[:space:]]|,|$)'; then
                port_args=("-p" "5000-5010:5000-5010")
            else
                echo "Note: docker sandbox run does not support -p; ports not published"
            fi

            echo "Starting new sandbox container..."
            docker sandbox run \
                --name "$container_name" \
                --label "$_CSD_LABEL" \
                -it \
                "${port_args[@]}" \
                "${vol_args[@]}" \
                "$_CSD_IMAGE" \
                bash
            ;;
        *)
            echo "Unexpected container state: $container_state" >&2
            return 1
            ;;
    esac
}

# Interactive container stop selection
csd-stop-all() {
    local containers

    # Find all dotnet-sandbox related containers (running or stopped)
    # Use label filter for reliable matching across image rebuilds
    containers=$(docker ps -a --filter "label=$_CSD_LABEL" --format "{{.Names}}\t{{.Status}}" 2>/dev/null)

    if [[ -z "$containers" ]]; then
        echo "No dotnet-sandbox containers found."
        return 0
    fi

    echo "Dotnet sandbox containers:"
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

# Return 0 when sourced, exit 1 when executed directly
return 0 2>/dev/null || { echo "This script should be sourced, not executed: source aliases.sh" >&2; exit 1; }
