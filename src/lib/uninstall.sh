#!/usr/bin/env bash
# ==============================================================================
# ContainAI Uninstall - Clean removal of system-level components
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_uninstall()                  - Main uninstall entry point
#   _cai_uninstall_systemd_service()  - Stop/disable/remove systemd unit
#   _cai_uninstall_docker_context()   - Remove Docker context
#   _cai_uninstall_containers()       - Remove containai containers
#   _cai_uninstall_volumes()          - Remove container volumes
#
# What gets removed (system-level installation):
#   - containai-docker.service - systemd unit file
#   - Docker context: containai-docker, containai-secure (legacy)
#   - With --containers: containers with containai.managed=true label
#   - With --volumes: associated container volumes
#
# What is NEVER removed (user config/data):
#   - ~/.config/containai/ - SSH keys, config.toml
#   - ~/.ssh/containai.d/ - SSH host configs
#   - /etc/containai/docker/ - daemon.json
#   - /var/lib/containai-docker/ - Docker data
#   - Sysbox packages - apt packages remain
#   - Lima VM (macOS) - contains user data
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
#   - Requires lib/docker.sh for Docker availability checks
#   - Requires lib/container.sh for container listing
#
# Usage: source lib/uninstall.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/uninstall.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/uninstall.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/uninstall.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_UNINSTALL_LOADED:-}" ]]; then
    return 0
fi
_CAI_UNINSTALL_LOADED=1

# ==============================================================================
# Constants
# ==============================================================================

# Systemd service name for containai-docker
_CAI_UNINSTALL_SERVICE="containai-docker"
_CAI_UNINSTALL_SERVICE_FILE="/etc/systemd/system/containai-docker.service"

# Docker contexts that may be created by ContainAI
# Uses $_CAI_CONTAINAI_DOCKER_CONTEXT from docker.sh (sourced before this file)
# Legacy contexts are kept for cleanup of older installations
_CAI_UNINSTALL_CONTEXTS=("$_CAI_CONTAINAI_DOCKER_CONTEXT" "containai-secure" "docker-containai")

# ==============================================================================
# Systemd Service Removal
# ==============================================================================

# Remove containai-docker systemd service
# Arguments: $1 = dry_run ("true" to simulate)
# Returns: 0=success or nothing to do, 1=failure
# Note: Follows best practices - stop, disable, remove file, daemon-reload
_cai_uninstall_systemd_service() {
    local dry_run="${1:-false}"
    local service_exists=false
    local service_running=false

    # Check if systemctl is available
    if ! command -v systemctl >/dev/null 2>&1; then
        _cai_debug "systemctl not found - skipping systemd service removal"
        return 0
    fi

    # Check if service unit file exists
    if [[ -f "$_CAI_UNINSTALL_SERVICE_FILE" ]]; then
        service_exists=true
    fi

    # Check if service is known to systemd (even without file, could be loaded)
    # Use systemctl cat which fails if unit doesn't exist (unlike list-unit-files)
    if systemctl cat "${_CAI_UNINSTALL_SERVICE}.service" >/dev/null 2>&1; then
        service_exists=true
    fi

    if [[ "$service_exists" != "true" ]]; then
        _cai_debug "Service ${_CAI_UNINSTALL_SERVICE} not found - nothing to remove"
        return 0
    fi

    # Check if running
    if systemctl is-active --quiet "${_CAI_UNINSTALL_SERVICE}" 2>/dev/null; then
        service_running=true
    fi

    _cai_step "Removing systemd service: ${_CAI_UNINSTALL_SERVICE}"

    if [[ "$dry_run" == "true" ]]; then
        if [[ "$service_running" == "true" ]]; then
            _cai_dryrun "Would stop service: ${_CAI_UNINSTALL_SERVICE}"
        fi
        _cai_dryrun "Would disable service: ${_CAI_UNINSTALL_SERVICE}"
        if [[ -f "$_CAI_UNINSTALL_SERVICE_FILE" ]]; then
            _cai_dryrun "Would remove: $_CAI_UNINSTALL_SERVICE_FILE"
        fi
        _cai_dryrun "Would run: systemctl daemon-reload"
        return 0
    fi

    # Step 1: Stop service (if running)
    if [[ "$service_running" == "true" ]]; then
        _cai_info "Stopping ${_CAI_UNINSTALL_SERVICE}..."
        if ! sudo systemctl stop "${_CAI_UNINSTALL_SERVICE}"; then
            _cai_warn "Failed to stop ${_CAI_UNINSTALL_SERVICE} (may already be stopped)"
        fi
    fi

    # Step 2: Disable service (removes symlinks)
    _cai_info "Disabling ${_CAI_UNINSTALL_SERVICE}..."
    # Disable can fail if service was never enabled - that's OK
    sudo systemctl disable "${_CAI_UNINSTALL_SERVICE}" 2>/dev/null || true

    # Step 3: Remove unit file
    if [[ -f "$_CAI_UNINSTALL_SERVICE_FILE" ]]; then
        _cai_info "Removing $_CAI_UNINSTALL_SERVICE_FILE..."
        if ! sudo rm -f "$_CAI_UNINSTALL_SERVICE_FILE"; then
            _cai_error "Failed to remove $_CAI_UNINSTALL_SERVICE_FILE"
            return 1
        fi
    fi

    # Step 4: Reload systemd daemon
    _cai_info "Reloading systemd daemon..."
    if ! sudo systemctl daemon-reload; then
        _cai_error "Failed to reload systemd daemon"
        return 1
    fi

    _cai_ok "Systemd service removed"
    return 0
}

# ==============================================================================
# Docker Context Removal
# ==============================================================================

# Remove Docker contexts created by ContainAI
# Arguments: $1 = dry_run ("true" to simulate)
# Returns: 0=success or nothing to do, 1=failure
_cai_uninstall_docker_context() {
    local dry_run="${1:-false}"
    local removed_any=false
    local failed_any=false

    # Check if docker is available
    if ! command -v docker >/dev/null 2>&1; then
        _cai_debug "Docker not found - skipping context removal"
        return 0
    fi

    for ctx in "${_CAI_UNINSTALL_CONTEXTS[@]}"; do
        # Check if context exists
        if ! docker context inspect "$ctx" >/dev/null 2>&1; then
            _cai_debug "Context '$ctx' not found - skipping"
            continue
        fi

        _cai_step "Removing Docker context: $ctx"

        if [[ "$dry_run" == "true" ]]; then
            _cai_dryrun "Would remove Docker context: $ctx"
            removed_any=true
            continue
        fi

        # Check if this is the current context
        local current_ctx
        current_ctx=$(docker context show 2>/dev/null || true)
        if [[ "$current_ctx" == "$ctx" ]]; then
            _cai_info "Switching from '$ctx' to 'default' context..."
            if ! docker context use default 2>/dev/null; then
                _cai_warn "Could not switch to default context"
            fi
        fi

        # Remove the context (use -f to avoid prompts)
        if docker context rm -f "$ctx" 2>/dev/null; then
            _cai_ok "Removed Docker context: $ctx"
            removed_any=true
        else
            _cai_warn "Failed to remove Docker context: $ctx"
            failed_any=true
        fi
    done

    if [[ "$removed_any" != "true" ]]; then
        _cai_debug "No Docker contexts to remove"
    fi

    if [[ "$failed_any" == "true" ]]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# Container Removal
# ==============================================================================

# Remove containers with containai.managed=true label
# Arguments: $1 = dry_run ("true" to simulate)
#            $2 = remove_volumes ("true" to also remove volumes)
# Returns: 0=success or nothing to do, 1=failure
_cai_uninstall_containers() {
    local dry_run="${1:-false}"
    local remove_volumes="${2:-false}"

    # Check if docker is available
    if ! command -v docker >/dev/null 2>&1; then
        _cai_debug "Docker not found - skipping container removal"
        return 0
    fi

    local -a all_containers=()
    local -a all_volumes=()
    local ctx container_id container_name

    # Collect containers from default context
    _cai_step "Finding ContainAI containers..."

    # Check default context
    while IFS= read -r container_id; do
        if [[ -n "$container_id" ]]; then
            container_name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null || true)
            container_name="${container_name#/}"
            all_containers+=("$container_id:$container_name:")

            # Collect volumes if requested
            if [[ "$remove_volumes" == "true" ]]; then
                local vol
                while IFS= read -r vol; do
                    if [[ -n "$vol" && "$vol" != "<no value>" ]]; then
                        all_volumes+=("$vol:")
                    fi
                done < <(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' "$container_id" 2>/dev/null || true)
            fi
        fi
    done < <(docker ps -aq --filter "label=containai.managed=true" 2>/dev/null || true)

    # Check all ContainAI-related contexts for containers
    for ctx in "${_CAI_UNINSTALL_CONTEXTS[@]}"; do
        if docker context inspect "$ctx" >/dev/null 2>&1; then
            while IFS= read -r container_id; do
                if [[ -n "$container_id" ]]; then
                    container_name=$(docker --context "$ctx" inspect --format '{{.Name}}' "$container_id" 2>/dev/null || true)
                    container_name="${container_name#/}"
                    all_containers+=("$container_id:$container_name:$ctx")

                    # Collect volumes if requested
                    if [[ "$remove_volumes" == "true" ]]; then
                        local vol
                        while IFS= read -r vol; do
                            if [[ -n "$vol" && "$vol" != "<no value>" ]]; then
                                all_volumes+=("$vol:$ctx")
                            fi
                        done < <(docker --context "$ctx" inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' "$container_id" 2>/dev/null || true)
                    fi
                fi
            done < <(docker --context "$ctx" ps -aq --filter "label=containai.managed=true" 2>/dev/null || true)
        fi
    done

    if [[ ${#all_containers[@]} -eq 0 ]]; then
        _cai_info "No ContainAI containers found"
        return 0
    fi

    # Check for running containers and warn
    local running_count=0
    local entry cid cname cctx
    for entry in "${all_containers[@]}"; do
        IFS=':' read -r cid cname cctx <<<"$entry"
        local state
        if [[ -n "$cctx" ]]; then
            state=$(docker --context "$cctx" inspect --format '{{.State.Running}}' "$cid" 2>/dev/null || true)
        else
            state=$(docker inspect --format '{{.State.Running}}' "$cid" 2>/dev/null || true)
        fi
        if [[ "$state" == "true" ]]; then
            running_count=$((running_count + 1))
        fi
    done

    _cai_info "Found ${#all_containers[@]} container(s) to remove"
    if [[ $running_count -gt 0 ]]; then
        _cai_warn "$running_count container(s) are currently running - will be force stopped"
    fi

    if [[ "$dry_run" == "true" ]]; then
        local entry
        for entry in "${all_containers[@]}"; do
            local cid cname cctx
            IFS=':' read -r cid cname cctx <<<"$entry"
            if [[ -n "$cctx" ]]; then
                _cai_dryrun "Would remove container: $cname ($cid) [context: $cctx]"
            else
                _cai_dryrun "Would remove container: $cname ($cid)"
            fi
        done
        if [[ "$remove_volumes" == "true" && ${#all_volumes[@]} -gt 0 ]]; then
            _cai_dryrun "Would remove ${#all_volumes[@]} volume(s)"
        fi
        return 0
    fi

    # Remove containers
    local entry removed=0 failed=0
    for entry in "${all_containers[@]}"; do
        local cid cname cctx
        IFS=':' read -r cid cname cctx <<<"$entry"

        local display_name="${cname:-$cid}"
        if [[ -n "$cctx" ]]; then
            display_name="$display_name [context: $cctx]"
        fi

        _cai_info "Removing container: $display_name"

        local rm_success=false
        if [[ -n "$cctx" ]]; then
            if docker --context "$cctx" rm -f "$cid" >/dev/null 2>&1; then
                rm_success=true
            fi
        else
            if docker rm -f "$cid" >/dev/null 2>&1; then
                rm_success=true
            fi
        fi

        if [[ "$rm_success" == "true" ]]; then
            removed=$((removed + 1))
            # NOTE: We do NOT remove SSH configs here per spec requirement
            # ~/.ssh/containai.d/ is preserved always
        else
            _cai_warn "Failed to remove container: $display_name"
            failed=$((failed + 1))
        fi
    done

    _cai_ok "Removed $removed container(s)${failed:+ ($failed failed)}"

    # Remove volumes if requested
    if [[ "$remove_volumes" == "true" && ${#all_volumes[@]} -gt 0 ]]; then
        if ! _cai_uninstall_volumes_from_array all_volumes; then
            failed=$((failed + 1))
        fi
    fi

    if [[ $failed -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Remove specified volumes from array
# Arguments: $1 = array name containing "volume:context" entries
# Returns: 0=success, 1=partial failure
_cai_uninstall_volumes_from_array() {
    local array_name=$1
    local -n volumes_ref=$array_name
    local removed=0 failed=0

    _cai_step "Removing volumes..."

    # Deduplicate volumes
    local -A seen_volumes
    local entry vol ctx
    for entry in "${volumes_ref[@]}"; do
        IFS=':' read -r vol ctx <<<"$entry"
        if [[ -n "$vol" ]]; then
            seen_volumes["$vol:$ctx"]=1
        fi
    done

    for key in "${!seen_volumes[@]}"; do
        IFS=':' read -r vol ctx <<<"$key"

        local display_name="$vol"
        if [[ -n "$ctx" ]]; then
            display_name="$vol [context: $ctx]"
        fi

        _cai_info "Removing volume: $display_name"

        local rm_success=false
        if [[ -n "$ctx" ]]; then
            if docker --context "$ctx" volume rm "$vol" >/dev/null 2>&1; then
                rm_success=true
            fi
        else
            if docker volume rm "$vol" >/dev/null 2>&1; then
                rm_success=true
            fi
        fi

        if [[ "$rm_success" == "true" ]]; then
            removed=$((removed + 1))
        else
            _cai_warn "Failed to remove volume: $display_name"
            failed=$((failed + 1))
        fi
    done

    _cai_ok "Removed $removed volume(s)${failed:+ ($failed failed)}"

    if [[ $failed -gt 0 ]]; then
        return 1
    fi
    return 0
}

# ==============================================================================
# Main Uninstall Function
# ==============================================================================

# Main uninstall entry point
# Arguments: parsed from command line
# Returns: 0=success, 1=failure
_cai_uninstall() {
    local dry_run="false"
    local remove_containers="false"
    local remove_volumes="false"
    local force="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --containers)
                remove_containers="true"
                shift
                ;;
            --volumes)
                remove_volumes="true"
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            --verbose)
                _cai_set_verbose
                shift
                ;;
            --help | -h)
                _cai_uninstall_help
                return 0
                ;;
            *)
                _cai_error "Unknown option: $1"
                _cai_error "Use 'cai uninstall --help' for usage"
                return 1
                ;;
        esac
    done

    # --volumes requires --containers
    if [[ "$remove_volumes" == "true" && "$remove_containers" != "true" ]]; then
        _cai_error "--volumes requires --containers flag"
        return 1
    fi

    # Show what will be done
    printf '%s\n' ""
    printf '%s\n' "ContainAI Uninstall"
    printf '%s\n' "==================="
    printf '%s\n' ""
    printf '%s\n' "The following will be REMOVED:"
    printf '%s\n' "  - containai-docker.service (systemd unit)"
    printf '%s\n' "  - Docker contexts: containai-docker, containai-secure, docker-containai (legacy)"
    if [[ "$remove_containers" == "true" ]]; then
        printf '%s\n' "  - All ContainAI containers (--containers)"
        if [[ "$remove_volumes" == "true" ]]; then
            printf '%s\n' "  - Container volumes (--volumes)"
        fi
    fi
    printf '%s\n' ""
    printf '%s\n' "The following will be PRESERVED (user data):"
    printf '%s\n' "  - ~/.config/containai/ (SSH keys, config)"
    printf '%s\n' "  - ~/.ssh/containai.d/ (SSH host configs)"
    printf '%s\n' "  - /etc/containai/docker/ (daemon.json)"
    printf '%s\n' "  - /var/lib/containai-docker/ (Docker data)"
    printf '%s\n' "  - Sysbox packages (apt packages)"
    printf '%s\n' "  - Lima VM (macOS)"
    printf '%s\n' ""

    if [[ "$dry_run" == "true" ]]; then
        printf '%s\n' "[DRY-RUN MODE - no changes will be made]"
        printf '%s\n' ""
    fi

    # Confirm unless --force or --dry-run
    if [[ "$force" != "true" && "$dry_run" != "true" ]]; then
        # Check if interactive
        if [[ ! -t 0 ]]; then
            _cai_error "Non-interactive terminal detected."
            _cai_error "Use --force to skip confirmation or --dry-run to preview."
            return 1
        fi

        printf '%s' "Proceed with uninstall? [y/N] "
        local response
        if ! read -r response; then
            printf '%s\n' "Cancelled."
            return 0
        fi
        case "$response" in
            [yY] | [yY][eE][sS]) ;;
            *)
                printf '%s\n' "Cancelled."
                return 0
                ;;
        esac
    fi

    printf '%s\n' ""

    # Execute removal in correct order:
    # 1. Containers (if --containers) - must happen before context removal
    # 2. Volumes (if --volumes)
    # 3. Docker context - before service removal
    # 4. Systemd service

    local overall_status=0

    # Step 1: Remove containers (if requested)
    if [[ "$remove_containers" == "true" ]]; then
        if ! _cai_uninstall_containers "$dry_run" "$remove_volumes"; then
            overall_status=1
        fi
    fi

    # Step 2: Remove Docker context
    if ! _cai_uninstall_docker_context "$dry_run"; then
        overall_status=1
    fi

    # Step 3: Remove systemd service
    if ! _cai_uninstall_systemd_service "$dry_run"; then
        overall_status=1
    fi

    # Summary
    printf '%s\n' ""
    if [[ "$dry_run" == "true" ]]; then
        _cai_ok "Dry-run complete - no changes were made"
    elif [[ $overall_status -eq 0 ]]; then
        _cai_ok "Uninstall complete"
        printf '%s\n' ""
        printf '%s\n' "To reinstall, run: cai setup"
    else
        _cai_warn "Uninstall completed with some failures"
        printf '%s\n' "Check the output above for details."
    fi

    return $overall_status
}

# Help text for uninstall command
_cai_uninstall_help() {
    cat <<'EOF'
ContainAI Uninstall - Clean removal of system-level components

Usage: cai uninstall [options]

Removes ContainAI's system-level installation components while preserving
user configuration and data. This allows for clean reinstallation.

Options:
  --dry-run       Show what would be removed without removing
  --containers    Stop and remove all ContainAI containers
  --volumes       Also remove container volumes (requires --containers)
  --force         Skip confirmation prompts
  --verbose       Enable verbose output
  -h, --help      Show this help message

What Gets Removed:
  - containai-docker.service (systemd unit)
  - Docker contexts: containai-docker, containai-secure, docker-containai (legacy)

What Gets Removed with --containers:
  - All containers with containai.managed=true label

What Gets Removed with --volumes:
  - Container data volumes

What is PRESERVED (user data):
  - ~/.config/containai/ - SSH keys, config.toml
  - ~/.ssh/containai.d/ - SSH host configs
  - /etc/containai/docker/ - daemon.json
  - /var/lib/containai-docker/ - Docker data, images
  - Sysbox packages - apt packages remain
  - Lima VM (macOS) - VM and data preserved

Examples:
  cai uninstall                      Remove system components only
  cai uninstall --dry-run            Preview what would be removed
  cai uninstall --containers         Also remove containers
  cai uninstall --containers --volumes  Remove containers and volumes
  cai uninstall --force              Skip confirmation prompt

After uninstalling, you can reinstall with: cai setup
EOF
}

return 0
