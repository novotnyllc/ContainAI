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

# Constants
readonly _CSD_IMAGE="dotnet-sandbox:latest"
readonly _CSD_VOLUMES=(
    "dotnet-sandbox-vscode:/home/agent/.vscode-server"
    "dotnet-sandbox-nuget:/home/agent/.nuget"
    "dotnet-sandbox-gh:/home/agent/.config/gh"
    "docker-claude-plugins:/home/agent/.claude/plugins"
)

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

    # Sanitize: lowercase, replace non-alphanumeric with dash
    name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')"

    # Strip leading/trailing dashes
    name="$(echo "$name" | sed 's/^-*//;s/-*$//')"

    # Handle empty or dash-only names
    if [[ -z "$name" || "$name" =~ ^-+$ ]]; then
        name="sandbox-$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/^-*//;s/-*$//')"
    fi

    # Truncate to 63 characters (Docker limit)
    name="${name:0:63}"

    # Final cleanup of trailing dashes from truncation
    name="$(echo "$name" | sed 's/-*$//')"

    echo "$name"
}

# Check if docker sandbox is available
_csd_check_sandbox() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker is not installed or not in PATH" >&2
        return 1
    fi

    # Check if sandbox command is available
    if docker sandbox ls >/dev/null 2>&1; then
        return 0
    elif docker sandbox --help 2>&1 | grep -q "not recognized\|unknown command\|Unknown command"; then
        echo "ERROR: Docker sandbox is not available" >&2
        echo "" >&2
        echo "Docker sandbox requires Docker Desktop 4.29+ with sandbox feature enabled." >&2
        echo "Please ensure you have:" >&2
        echo "  1. Docker Desktop 4.29 or later installed" >&2
        echo "  2. Docker sandbox feature enabled in Settings > Features in development" >&2
        echo "" >&2
        return 1
    else
        # sandbox command exists but failed for another reason (maybe no sandboxes yet)
        return 0
    fi
}

# Ensure required volumes exist with correct permissions
_csd_ensure_volumes() {
    local volume_name mount_point
    local volumes_created=()

    for vol_spec in "${_CSD_VOLUMES[@]}"; do
        volume_name="${vol_spec%%:*}"

        if ! docker volume inspect "$volume_name" >/dev/null 2>&1; then
            echo "Creating volume: $volume_name"
            docker volume create "$volume_name" >/dev/null
            volumes_created+=("$volume_name")
        fi
    done

    # Fix permissions on newly created volumes (if image is available)
    if [[ ${#volumes_created[@]} -gt 0 ]] && docker image inspect "$_CSD_IMAGE" >/dev/null 2>&1; then
        for volume_name in "${volumes_created[@]}"; do
            echo "Setting permissions on: $volume_name"
            docker run --rm -u root -v "${volume_name}:/data" "$_CSD_IMAGE" chown 1000:1000 /data 2>/dev/null || true
        done
    fi
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

    # Check if image exists
    if ! docker image inspect "$_CSD_IMAGE" >/dev/null 2>&1; then
        echo "ERROR: Image '$_CSD_IMAGE' not found" >&2
        echo "Please build the image first: ./dotnet-sandbox/build.sh" >&2
        return 1
    fi

    # Get container name
    container_name="$(_csd_container_name)"
    echo "Container: $container_name"

    # Check container state
    local container_state
    container_state="$(docker inspect --format '{{.State.Status}}' "$container_name" 2>/dev/null || echo "none")"

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
            # Ensure volumes exist
            _csd_ensure_volumes

            # Build volume arguments
            local vol_args=()
            for vol_spec in "${_CSD_VOLUMES[@]}"; do
                vol_args+=("-v" "$vol_spec")
            done

            echo "Starting new sandbox container..."
            docker sandbox run \
                --name "$container_name" \
                -it \
                -p 5000-5010:5000-5010 \
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
    containers=$(docker ps -a --filter "ancestor=$_CSD_IMAGE" --format "{{.Names}}\t{{.Status}}" 2>/dev/null)

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
