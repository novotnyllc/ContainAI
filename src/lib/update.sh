#!/usr/bin/env bash
# ==============================================================================
# ContainAI Update - Update existing installations
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_update()                     - Main update entry point
#   _cai_update_help()                - Show update command help
#   _cai_update_linux_wsl2()          - Update Linux/WSL2 installation
#   _cai_update_macos()               - Update macOS Lima installation
#   _cai_update_systemd_unit()        - Update systemd unit if template changed
#   _cai_update_docker_context()      - Update Docker context if socket changed
#
# Purpose:
#   Ensures existing installation is in required state and updates dependencies
#   to their latest versions. Safe to run multiple times (idempotent).
#
# What it does:
#   Linux/WSL2:
#     - Update systemd unit if changed
#     - Restart service after unit update
#     - Verify Docker context
#     - Clean up legacy paths
#     - Verify final state
#   macOS Lima:
#     - Delete and recreate VM with latest template
#     - Recreate Docker context
#     - Verify installation
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
#   - Requires lib/platform.sh for platform detection
#   - Requires lib/docker.sh for Docker constants and checks
#   - Requires lib/setup.sh for setup helper functions
#
# Usage: source lib/update.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/update.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/update.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/update.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_UPDATE_LOADED:-}" ]]; then
    return 0
fi
_CAI_UPDATE_LOADED=1

# ==============================================================================
# Help
# ==============================================================================

_cai_update_help() {
    cat <<'EOF'
ContainAI Update - Update existing installation

Usage: cai update [options]

Ensures existing installation is in required state and updates dependencies
to their latest versions. Safe to run multiple times (idempotent).

Options:
  --dry-run         Show what would be done without making changes
  --force           Skip confirmation prompts (e.g., VM recreation on macOS)
  --lima-recreate   Force Lima VM recreation (macOS only; currently always recreates)
  --verbose, -v     Show verbose output
  -h, --help        Show this help message

What Gets Updated:

  Linux/WSL2:
    - Systemd unit file (if template changed)
    - Docker service restart
    - Docker context verification
    - Legacy path cleanup

  macOS Lima:
    - Lima VM deletion and recreation with latest template
    - Docker context recreation
    - Installation verification

Notes:
  - Lima VM recreation will stop all running containers in the VM
  - User is warned before destructive VM operations (unless --force)
  - Use 'cai doctor' after update to verify installation

Examples:
  cai update                    Update installation
  cai update --dry-run          Preview what would be updated
  cai update --force            Update without confirmation prompts
  cai update --lima-recreate    Force VM recreation (macOS)
EOF
}

# ==============================================================================
# Systemd Unit Comparison
# ==============================================================================

# Generate expected systemd unit content
# Returns: unit content via stdout
# Note: Delegates to _cai_dockerd_unit_content() in docker.sh for single source of truth
_cai_update_expected_unit_content() {
    _cai_dockerd_unit_content
}

# Check if systemd unit needs update
# Returns: 0=needs update, 1=up to date, 2=unit doesn't exist
_cai_update_unit_needs_update() {
    local unit_file="$_CAI_CONTAINAI_DOCKER_UNIT"

    if [[ ! -f "$unit_file" ]]; then
        return 2
    fi

    local expected current
    expected=$(_cai_update_expected_unit_content)
    current=$(cat "$unit_file" 2>/dev/null) || current=""

    if [[ "$expected" == "$current" ]]; then
        return 1  # Up to date
    fi
    return 0  # Needs update
}

# Update systemd unit file if template changed
# Arguments: $1 = dry_run ("true" to simulate)
#            $2 = verbose ("true" for verbose output)
# Returns: 0=updated or no change needed, 1=failed
_cai_update_systemd_unit() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_step "Checking systemd unit file"

    # Check if systemd is running (required for service management)
    # /run/systemd/system exists only when systemd is PID 1
    if [[ ! -d /run/systemd/system ]]; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_warn "[DRY-RUN] systemd is not running (required for actual update)"
            _cai_info "[DRY-RUN] Would require systemd to be running"
        else
            _cai_error "systemd is not running (or not the init system)"
            _cai_error "  ContainAI requires systemd on Linux/WSL2"
            _cai_error "  On WSL2, enable systemd in /etc/wsl.conf:"
            _cai_error "    [boot]"
            _cai_error "    systemd=true"
            return 1
        fi
    fi

    local unit_status
    if _cai_update_unit_needs_update; then
        unit_status=0  # needs update
    else
        unit_status=$?
    fi

    case $unit_status in
        0)
            # Needs update
            _cai_info "Systemd unit file needs update"

            if [[ "$dry_run" == "true" ]]; then
                _cai_info "[DRY-RUN] Would update: $_CAI_CONTAINAI_DOCKER_UNIT"
                _cai_info "[DRY-RUN] Would run: systemctl daemon-reload"
                _cai_info "[DRY-RUN] Would restart: $_CAI_CONTAINAI_DOCKER_SERVICE"
                return 0
            fi

            # Write updated unit file
            local unit_content
            unit_content=$(_cai_update_expected_unit_content)

            if ! printf '%s\n' "$unit_content" | sudo tee "$_CAI_CONTAINAI_DOCKER_UNIT" >/dev/null; then
                _cai_error "Failed to update systemd unit file"
                return 1
            fi

            _cai_ok "Systemd unit file updated"

            # Reload systemd
            _cai_step "Reloading systemd daemon"
            if ! sudo systemctl daemon-reload; then
                _cai_error "Failed to reload systemd daemon"
                return 1
            fi

            # Restart service
            _cai_step "Restarting $_CAI_CONTAINAI_DOCKER_SERVICE"
            if ! sudo systemctl restart "$_CAI_CONTAINAI_DOCKER_SERVICE"; then
                _cai_error "Failed to restart service"
                _cai_error "  Check: sudo systemctl status $_CAI_CONTAINAI_DOCKER_SERVICE"
                return 1
            fi

            # Wait for socket
            local wait_count=0
            local max_wait=30
            _cai_step "Waiting for socket: $_CAI_CONTAINAI_DOCKER_SOCKET"
            while [[ ! -S "$_CAI_CONTAINAI_DOCKER_SOCKET" ]]; do
                sleep 1
                wait_count=$((wait_count + 1))
                if [[ $wait_count -ge $max_wait ]]; then
                    _cai_error "Socket did not appear after ${max_wait}s"
                    return 1
                fi
            done

            _cai_ok "Service restarted and socket ready"
            return 0
            ;;
        1)
            # Up to date
            _cai_info "Systemd unit file is current"
            return 0
            ;;
        2)
            # Doesn't exist
            _cai_warn "Systemd unit file not found: $_CAI_CONTAINAI_DOCKER_UNIT"
            _cai_info "Run 'cai setup' to install ContainAI"
            return 1
            ;;
    esac
}

# Update Docker context if needed
# Arguments: $1 = dry_run ("true" to simulate)
# Returns: 0=success, 1=failed
_cai_update_docker_context() {
    local dry_run="${1:-false}"

    _cai_step "Checking Docker context"

    # Check if Docker CLI is available
    if ! command -v docker >/dev/null 2>&1; then
        _cai_error "Docker CLI not found"
        _cai_error "  Install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi

    local context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"

    # Determine expected socket based on platform
    local expected_host
    if _cai_is_macos; then
        expected_host="unix://$HOME/.lima/$_CAI_LIMA_VM_NAME/sock/docker.sock"
    else
        expected_host="unix://$_CAI_CONTAINAI_DOCKER_SOCKET"
    fi

    # Check if context exists
    if ! docker context inspect "$context_name" >/dev/null 2>&1; then
        _cai_info "Context '$context_name' not found - will create"

        if [[ "$dry_run" == "true" ]]; then
            _cai_info "[DRY-RUN] Would create context: $context_name"
            _cai_info "[DRY-RUN] Would set endpoint: $expected_host"
            return 0
        fi

        if ! docker context create "$context_name" --docker "host=$expected_host"; then
            _cai_error "Failed to create Docker context"
            return 1
        fi

        _cai_ok "Docker context created"
        return 0
    fi

    # Check if context has correct endpoint
    local actual_host
    actual_host=$(docker context inspect "$context_name" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)

    if [[ "$actual_host" == "$expected_host" ]]; then
        _cai_info "Docker context is current"
        return 0
    fi

    # Context exists but with wrong endpoint
    _cai_warn "Context '$context_name' has wrong endpoint"
    _cai_info "  Current: $actual_host"
    _cai_info "  Expected: $expected_host"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would remove and recreate context"
        return 0
    fi

    # Switch away if this context is active
    local current_context
    current_context=$(docker context show 2>/dev/null || true)
    if [[ "$current_context" == "$context_name" ]]; then
        docker context use default >/dev/null 2>&1 || true
    fi

    # Remove and recreate
    if ! docker context rm -f "$context_name" >/dev/null 2>&1; then
        _cai_error "Failed to remove existing context"
        return 1
    fi

    if ! docker context create "$context_name" --docker "host=$expected_host"; then
        _cai_error "Failed to create Docker context"
        return 1
    fi

    _cai_ok "Docker context updated"
    return 0
}

# ==============================================================================
# Linux/WSL2 Update
# ==============================================================================

# Update Linux/WSL2 installation
# Arguments: $1 = dry_run ("true" to simulate)
#            $2 = verbose ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_update_linux_wsl2() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local overall_status=0

    _cai_info "Updating Linux/WSL2 installation"

    # Step 1: Clean up legacy paths
    if ! _cai_cleanup_legacy_paths "$dry_run" "$verbose"; then
        _cai_warn "Legacy cleanup had issues (continuing anyway)"
    fi

    # Step 2: Check/update systemd unit
    if ! _cai_update_systemd_unit "$dry_run" "$verbose"; then
        overall_status=1
    fi

    # Step 3: Check/update Docker context
    if ! _cai_update_docker_context "$dry_run"; then
        overall_status=1
    fi

    # Step 4: Verify installation
    if [[ "$dry_run" != "true" ]]; then
        _cai_step "Verifying installation"
        if ! _cai_verify_isolated_docker "false" "$verbose"; then
            _cai_warn "Verification had issues - check output above"
            overall_status=1
        fi
    else
        _cai_info "[DRY-RUN] Would verify installation"
    fi

    return $overall_status
}

# ==============================================================================
# macOS Lima Update
# ==============================================================================

# Update macOS Lima installation
# Arguments: $1 = dry_run ("true" to simulate)
#            $2 = verbose ("true" for verbose output)
#            $3 = force ("true" to skip confirmation)
# Returns: 0=success, 1=failure, 130=cancelled by user
_cai_update_macos() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local force="${3:-false}"
    local overall_status=0

    _cai_info "Updating macOS Lima installation"

    # Check if Lima is installed
    if ! command -v limactl >/dev/null 2>&1; then
        _cai_error "Lima not found. Run 'cai setup' first."
        return 1
    fi

    # Check if VM exists
    if ! _cai_lima_vm_exists "$_CAI_LIMA_VM_NAME"; then
        _cai_error "Lima VM '$_CAI_LIMA_VM_NAME' not found. Run 'cai setup' first."
        return 1
    fi

    # Step 1: Clean up legacy paths (sockets, contexts, drop-ins)
    # NOTE: VM cleanup happens AFTER verification (Step 6) to preserve fallback
    if ! _cai_cleanup_legacy_paths "$dry_run" "$verbose"; then
        _cai_warn "Legacy cleanup had issues (continuing anyway)"
    fi

    # Step 2: Handle VM recreation
    # Per spec: macOS update deletes and recreates VM with latest config by default
    # --lima-recreate forces recreation even if we add "currentness" checks later
    _cai_step "Recreating Lima VM with latest template"

    # Warn about container loss
    if [[ "$dry_run" != "true" ]]; then
        printf '\n'
        _cai_warn "This will DELETE the Lima VM and recreate it."
        _cai_warn "All running containers in the VM will be LOST."
        printf '\n'

        if [[ "$force" != "true" ]]; then
            printf '%s' "Continue with VM recreation? [y/N] "
            local response
            if ! read -r response; then
                printf '%s\n' "Cancelled."
                return 130  # Signal cancellation
            fi
            case "$response" in
                [yY] | [yY][eE][sS]) ;;
                *)
                    printf '%s\n' "Cancelled."
                    return 130  # Signal cancellation
                    ;;
            esac
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would stop Lima VM: $_CAI_LIMA_VM_NAME"
        _cai_info "[DRY-RUN] Would delete Lima VM: $_CAI_LIMA_VM_NAME"
        _cai_info "[DRY-RUN] Would recreate Lima VM with latest template"
    else
        # Stop VM if running
        local status
        status=$(_cai_lima_vm_status "$_CAI_LIMA_VM_NAME")
        if [[ "$status" == "Running" ]]; then
            _cai_step "Stopping Lima VM"
            if ! limactl stop "$_CAI_LIMA_VM_NAME"; then
                _cai_error "Failed to stop Lima VM"
                return 1
            fi
        fi

        # Delete VM
        _cai_step "Deleting Lima VM"
        if ! limactl delete "$_CAI_LIMA_VM_NAME" --force; then
            _cai_error "Failed to delete Lima VM"
            return 1
        fi

        # Recreate VM
        if ! _cai_lima_create_vm "false" "$verbose"; then
            _cai_error "Failed to recreate Lima VM"
            return 1
        fi

        # Wait for socket
        if ! _cai_lima_wait_socket 120 "false"; then
            _cai_error "Lima socket did not become available"
            return 1
        fi

        _cai_ok "Lima VM recreated"
    fi

    # Step 3: Check/update Docker context
    if ! _cai_update_docker_context "$dry_run"; then
        overall_status=1
    fi

    # Step 4: Verify installation BEFORE legacy cleanup
    # This ensures we don't remove fallback VM before confirming new VM works
    if [[ "$dry_run" != "true" ]]; then
        _cai_step "Verifying installation"
        if ! _cai_lima_verify_install "false" "$verbose"; then
            _cai_warn "Verification had issues - check output above"
            overall_status=1
        fi
    else
        _cai_info "[DRY-RUN] Would verify installation"
    fi

    # Step 5: Clean up legacy Lima VM (only if verification passed)
    if [[ "$dry_run" != "true" ]] && [[ $overall_status -eq 0 ]]; then
        _cai_cleanup_legacy_lima_vm "false" "$verbose" "$force"
    fi

    return $overall_status
}

# ==============================================================================
# Main Update Function
# ==============================================================================

# Main update entry point
# Arguments: parsed from command line
# Returns: 0=success, 1=failure, 130=cancelled
_cai_update() {
    local dry_run="false"
    local force="false"
    local lima_recreate="false"
    local verbose="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            --lima-recreate)
                # Currently a no-op since we always recreate the VM
                # Reserved for future "currentness" check implementation
                lima_recreate="true"
                shift
                ;;
            --verbose | -v)
                verbose="true"
                shift
                ;;
            --help | -h)
                _cai_update_help
                return 0
                ;;
            *)
                _cai_error "Unknown option: $1"
                _cai_error "Use 'cai update --help' for usage"
                return 1
                ;;
        esac
    done

    # Suppress shellcheck warning for reserved variable
    # shellcheck disable=SC2034
    : "${lima_recreate}"  # Reserved for future use

    # Header
    printf '%s\n' ""
    printf '%s\n' "ContainAI Update"
    printf '%s\n' "================"
    printf '%s\n' ""

    if [[ "$dry_run" == "true" ]]; then
        printf '%s\n' "[DRY-RUN MODE - no changes will be made]"
        printf '%s\n' ""
    fi

    # Dispatch based on platform
    local overall_status=0

    if _cai_is_macos; then
        _cai_update_macos "$dry_run" "$verbose" "$force"
        overall_status=$?
    else
        # Linux or WSL2
        _cai_update_linux_wsl2 "$dry_run" "$verbose"
        overall_status=$?
    fi

    # Summary
    printf '%s\n' ""
    if [[ $overall_status -eq 130 ]]; then
        # User cancelled
        _cai_info "Update cancelled by user"
        return 130
    elif [[ "$dry_run" == "true" ]]; then
        _cai_ok "Dry-run complete - no changes were made"
    elif [[ $overall_status -eq 0 ]]; then
        _cai_ok "Update complete"
        printf '%s\n' ""
        printf '%s\n' "Run 'cai doctor' to verify installation."
    else
        _cai_warn "Update completed with some issues"
        printf '%s\n' ""
        printf '%s\n' "Check the output above for details."
        printf '%s\n' "Run 'cai doctor' to diagnose issues."
    fi

    return $overall_status
}

return 0
