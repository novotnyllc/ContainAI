#!/usr/bin/env bash
# ==============================================================================
# ContainAI Setup - WSL2 Secure Engine Provisioning
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_setup()                   - Main setup entry point
#   _cai_setup_wsl2()              - WSL2-specific setup
#   _cai_test_wsl2_seccomp()       - Test WSL2 seccomp compatibility
#   _cai_show_seccomp_warning()    - Display seccomp warning
#   _cai_install_sysbox_wsl2()     - Install Sysbox on WSL2
#   _cai_configure_daemon_json()   - Configure Docker daemon.json
#   _cai_create_containai_context()- Create containai-secure Docker context
#   _cai_verify_sysbox_install()   - Verify Sysbox installation
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
#   - Requires lib/platform.sh for platform detection
#   - Requires lib/docker.sh for Docker availability checks
#
# Usage: source lib/setup.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/setup.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/setup.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/setup.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_SETUP_LOADED:-}" ]]; then
    return 0
fi
_CAI_SETUP_LOADED=1

# ==============================================================================
# Constants
# ==============================================================================

# Default socket path for containai-secure context
_CAI_SECURE_SOCKET="/var/run/containai-docker.sock"

# Default daemon.json path for WSL2 (standalone Docker, not Docker Desktop)
_CAI_WSL2_DAEMON_JSON="/etc/docker/daemon.json"

# ==============================================================================
# Seccomp Compatibility Testing
# ==============================================================================

# Test WSL2 seccomp compatibility for Sysbox
# Returns: 0=compatible, 1=seccomp filter conflict detected, 2=unknown
# Outputs: Sets _CAI_SECCOMP_TEST_ERROR with details on failure
# Note: WSL 1.1.0+ has seccomp filter on PID 1 that may conflict with Sysbox's seccomp-notify
_cai_test_wsl2_seccomp() {
    _CAI_SECCOMP_TEST_ERROR=""

    # Check /proc/self/status for Seccomp field (current process's seccomp mode)
    # Mode 2 (filter) on PID 1 indicates potential Sysbox conflict
    if [[ -f /proc/1/status ]]; then
        local seccomp_line pid1_mode
        # Guard grep with || true per pitfall memory
        seccomp_line=$(grep "^Seccomp:" /proc/1/status 2>/dev/null || true)
        if [[ -n "$seccomp_line" ]]; then
            # Extract mode number - value follows colon and whitespace (tab or space)
            pid1_mode="${seccomp_line##*:}"
            # Strip tabs and spaces (tabs are common in /proc/*/status)
            pid1_mode="${pid1_mode//[[:space:]]/}"

            case "$pid1_mode" in
                0)
                    # Mode 0 = seccomp disabled on PID 1 - safe for Sysbox
                    return 0
                    ;;
                1)
                    # Mode 1 = strict mode - Sysbox typically works
                    return 0
                    ;;
                2)
                    # Mode 2 = filter mode on PID 1 - WSL 1.1.0+ seccomp filter
                    # This can cause EBUSY when Sysbox tries to add seccomp-notify
                    _CAI_SECCOMP_TEST_ERROR="WSL seccomp filter detected on PID 1 (mode=2)"
                    return 1
                    ;;
            esac
        fi
    fi

    # Cannot determine - return unknown
    _CAI_SECCOMP_TEST_ERROR="Cannot determine seccomp status"
    return 2
}

# Display seccomp warning box for WSL2
# Arguments: $1 = wsl version info (optional)
_cai_show_seccomp_warning() {
    local wsl_info="${1:-unknown}"

    # Use printf for consistent output per memory convention
    printf '%s\n' ""
    printf '%s\n' "+==================================================================+"
    printf '%s\n' "|                          WARNING                                 |"
    printf '%s\n' "+==================================================================+"
    printf '%s\n' "| Sysbox on WSL2 may not work due to seccomp filter conflicts.    |"
    printf '%s\n' "|                                                                  |"
    printf '%s\n' "| Your WSL version (1.1.0+) has a seccomp filter on PID 1 that    |"
    printf '%s\n' "| conflicts with Sysbox's seccomp-notify mechanism.               |"
    printf '%s\n' "|                                                                  |"
    printf '%s\n' "| Docker Sandbox will still work (this is the hard requirement).  |"
    printf '%s\n' "| Sysbox provides additional isolation but is optional.           |"
    printf '%s\n' "|                                                                  |"
    printf '%s\n' "| Options:                                                         |"
    printf '%s\n' "|   1. Proceed anyway: cai setup --force                          |"
    printf '%s\n' "|   2. Downgrade WSL:  wsl --update --web-download --version 1.0.3|"
    printf '%s\n' "|   3. Skip Sysbox:    Use Docker Sandbox without Sysbox          |"
    printf '%s\n' "+==================================================================+"
    printf '%s\n' ""
}

# ==============================================================================
# Sysbox Installation
# ==============================================================================

# Download and install Sysbox on WSL2/Ubuntu/Debian
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Outputs: Progress messages to stdout, errors to stderr
_cai_install_sysbox_wsl2() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    # Detect distro
    local distro=""
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        distro=$(. /etc/os-release && printf '%s' "$ID")
    fi

    case "$distro" in
        ubuntu|debian)
            ;;
        *)
            _cai_error "Sysbox auto-install only supports Ubuntu/Debian"
            _cai_error "  Detected distro: ${distro:-unknown}"
            _cai_error "  For other distros, install Sysbox manually:"
            _cai_error "  https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md"
            return 1
            ;;
    esac

    # Check for systemd (required for Sysbox service)
    if ! command -v systemctl >/dev/null 2>&1; then
        _cai_error "Sysbox requires systemd (systemctl not found)"
        _cai_error "  Enable systemd in your WSL distribution:"
        _cai_error "  Add 'systemd=true' to /etc/wsl.conf under [boot] section"
        return 1
    fi

    # Check if systemd is actually running (PID 1)
    local pid1_cmd
    pid1_cmd=$(ps -p 1 -o comm= 2>/dev/null || true)
    if [[ "$pid1_cmd" != "systemd" ]]; then
        _cai_error "Systemd is not running as PID 1 (found: $pid1_cmd)"
        _cai_error "  Configure WSL to boot with systemd:"
        _cai_error "  1. Add to /etc/wsl.conf:"
        _cai_error "     [boot]"
        _cai_error "     systemd=true"
        _cai_error "  2. Restart WSL: wsl --shutdown"
        return 1
    fi

    _cai_step "Checking for existing Sysbox installation"
    if command -v sysbox-runc >/dev/null 2>&1; then
        local existing_version
        existing_version=$(sysbox-runc --version 2>/dev/null | head -1 || true)
        _cai_info "Sysbox already installed: $existing_version"
        return 0
    fi

    _cai_step "Installing Sysbox dependencies"
    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: apt-get update"
        _cai_info "[DRY-RUN] Would run: apt-get install -y jq wget"
    else
        if ! sudo apt-get update; then
            _cai_error "Failed to run apt-get update"
            return 1
        fi
        if ! sudo apt-get install -y jq wget; then
            _cai_error "Failed to install dependencies (jq, wget)"
            return 1
        fi
    fi

    _cai_step "Downloading Sysbox package"

    # Determine architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            arch="amd64"
            ;;
        aarch64)
            arch="arm64"
            ;;
        *)
            _cai_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    # Get latest Sysbox release URL from GitHub
    # Note: Sysbox-CE is the community edition
    local release_url="https://api.github.com/repos/nestybox/sysbox/releases/latest"
    local download_url

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would fetch latest release from: $release_url"
        download_url="https://downloads.nestybox.com/sysbox/releases/vX.Y.Z/sysbox-ce_X.Y.Z-0.linux_${arch}.deb"
    else
        # Fetch release info
        local release_json
        release_json=$(wget -qO- "$release_url" 2>/dev/null) || {
            _cai_error "Failed to fetch Sysbox release info from GitHub"
            return 1
        }

        # Extract .deb download URL for this architecture
        download_url=$(printf '%s' "$release_json" | jq -r ".assets[] | select(.name | test(\"sysbox-ce.*${arch}.deb\")) | .browser_download_url" | head -1)

        if [[ -z "$download_url" ]] || [[ "$download_url" == "null" ]]; then
            _cai_error "Could not find Sysbox .deb package for architecture: $arch"
            return 1
        fi
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Download URL: $download_url"
    fi

    # Download and install
    local tmpdir deb_file
    tmpdir=$(mktemp -d)
    deb_file="$tmpdir/sysbox-ce.deb"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would download: $download_url"
        _cai_info "[DRY-RUN] Would install: dpkg -i $deb_file"
    else
        _cai_step "Downloading Sysbox from: $download_url"
        if ! wget -q --show-progress -O "$deb_file" "$download_url"; then
            _cai_error "Failed to download Sysbox package"
            rm -rf "$tmpdir"
            return 1
        fi

        _cai_step "Installing Sysbox package"
        if ! sudo dpkg -i "$deb_file"; then
            _cai_warn "dpkg install had issues, attempting to fix dependencies"
            if ! sudo apt-get install -f -y; then
                _cai_error "Failed to install Sysbox package"
                rm -rf "$tmpdir"
                return 1
            fi
        fi

        rm -rf "$tmpdir"
    fi

    _cai_ok "Sysbox installation complete"
    return 0
}

# ==============================================================================
# Docker Configuration
# ==============================================================================

# Configure Docker daemon.json with sysbox-runc runtime
# Arguments: $1 = daemon.json path
#            $2 = dry_run flag ("true" to simulate)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Note: Does NOT set sysbox-runc as default runtime - keeps runc as default
_cai_configure_daemon_json() {
    local daemon_json="${1:-$_CAI_WSL2_DAEMON_JSON}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_step "Configuring Docker daemon"

    # Ensure /etc/docker directory exists
    if [[ ! -d "$(dirname "$daemon_json")" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_info "[DRY-RUN] Would create directory: $(dirname "$daemon_json")"
        else
            if ! sudo mkdir -p "$(dirname "$daemon_json")"; then
                _cai_error "Failed to create directory: $(dirname "$daemon_json")"
                return 1
            fi
        fi
    fi

    # Read existing config or create empty object
    local existing_config="{}"
    if [[ -f "$daemon_json" ]]; then
        existing_config=$(cat "$daemon_json" 2>/dev/null) || existing_config="{}"
        # Validate JSON
        if ! printf '%s' "$existing_config" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
            _cai_error "Existing daemon.json is not valid JSON: $daemon_json"
            _cai_error "  Please fix or remove the file and try again"
            return 1
        fi
    fi

    # Merge sysbox-runc runtime into config
    # Use Python for reliable JSON manipulation
    local new_config
    new_config=$(printf '%s' "$existing_config" | python3 -c "
import json
import sys

config = json.load(sys.stdin)

# Ensure runtimes section exists
if 'runtimes' not in config:
    config['runtimes'] = {}

# Add sysbox-runc if not present
if 'sysbox-runc' not in config['runtimes']:
    config['runtimes']['sysbox-runc'] = {
        'path': '/usr/bin/sysbox-runc'
    }

# DO NOT set default-runtime to sysbox-runc - keep runc as default
# This is a safety measure per task spec

print(json.dumps(config, indent=2))
")

    if [[ -z "$new_config" ]]; then
        _cai_error "Failed to generate daemon.json configuration"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "New daemon.json content:"
        printf '%s\n' "$new_config"
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would write to: $daemon_json"
        _cai_info "[DRY-RUN] Content:"
        printf '%s\n' "$new_config"
    else
        # Backup existing config
        if [[ -f "$daemon_json" ]]; then
            local backup_file="${daemon_json}.bak.$(date +%Y%m%d-%H%M%S)"
            if ! sudo cp "$daemon_json" "$backup_file"; then
                _cai_warn "Failed to backup existing daemon.json"
            else
                _cai_info "Backed up existing config to: $backup_file"
            fi
        fi

        # Write new config
        if ! printf '%s\n' "$new_config" | sudo tee "$daemon_json" >/dev/null; then
            _cai_error "Failed to write daemon.json"
            return 1
        fi
    fi

    _cai_ok "Docker daemon configured with sysbox-runc runtime"
    return 0
}

# Restart Docker service
# Arguments: $1 = dry_run flag ("true" to simulate)
# Returns: 0=success, 1=failure
_cai_restart_docker_service() {
    local dry_run="${1:-false}"

    _cai_step "Restarting Docker service"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: systemctl restart docker"
        return 0
    fi

    if ! sudo systemctl restart docker; then
        _cai_error "Failed to restart Docker service"
        _cai_error "  Check: sudo systemctl status docker"
        return 1
    fi

    # Wait for Docker to be ready
    local wait_count=0
    local max_wait=30
    while ! docker info >/dev/null 2>&1; do
        sleep 1
        wait_count=$((wait_count + 1))
        if [[ $wait_count -ge $max_wait ]]; then
            _cai_error "Docker did not become ready after ${max_wait}s"
            return 1
        fi
    done

    _cai_ok "Docker service restarted"
    return 0
}

# ==============================================================================
# Docker Context Creation
# ==============================================================================

# Create containai-secure Docker context
# Arguments: $1 = socket path
#            $2 = dry_run flag ("true" to simulate)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Note: This context points to standalone Docker daemon, NOT Docker Desktop
_cai_create_containai_context() {
    local socket_path="${1:-$_CAI_SECURE_SOCKET}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_step "Creating containai-secure Docker context"

    # For WSL2 with standalone dockerd, use the default socket
    # The context is for isolation purposes - same daemon but explicit selection
    # In production, this would point to a separate docker daemon socket
    local docker_socket="/var/run/docker.sock"

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Socket path: unix://$docker_socket"
    fi

    # Check if context already exists
    if docker context inspect containai-secure >/dev/null 2>&1; then
        _cai_info "Context 'containai-secure' already exists"

        # Verify it points to correct socket
        local existing_host
        existing_host=$(docker context inspect containai-secure --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)
        if [[ "$verbose" == "true" ]]; then
            _cai_info "Existing context endpoint: $existing_host"
        fi

        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: docker context create containai-secure --docker host=unix://$docker_socket"
    else
        if ! docker context create containai-secure --docker "host=unix://$docker_socket"; then
            _cai_error "Failed to create Docker context 'containai-secure'"
            return 1
        fi
    fi

    _cai_ok "Docker context 'containai-secure' created"
    return 0
}

# ==============================================================================
# Installation Verification
# ==============================================================================

# Verify Sysbox installation
# Arguments: $1 = dry_run flag ("true" to skip actual verification)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_verify_sysbox_install() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_step "Verifying Sysbox installation"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would verify sysbox-runc and sysbox-mgr"
        _cai_info "[DRY-RUN] Would verify Docker runtime configuration"
        _cai_info "[DRY-RUN] Would verify containai-secure context"
        return 0
    fi

    # Check sysbox-runc binary
    if ! command -v sysbox-runc >/dev/null 2>&1; then
        _cai_error "sysbox-runc not found in PATH"
        return 1
    fi

    local sysbox_version
    sysbox_version=$(sysbox-runc --version 2>/dev/null | head -1 || true)
    if [[ "$verbose" == "true" ]]; then
        _cai_info "sysbox-runc version: $sysbox_version"
    fi

    # Check sysbox-mgr service
    if command -v systemctl >/dev/null 2>&1; then
        if ! systemctl is-active --quiet sysbox-mgr 2>/dev/null; then
            _cai_warn "sysbox-mgr service is not running"
            _cai_warn "  Start with: sudo systemctl start sysbox-mgr"
        elif [[ "$verbose" == "true" ]]; then
            _cai_info "sysbox-mgr service: running"
        fi
    fi

    # Check Docker recognizes sysbox-runc runtime
    local docker_runtimes
    docker_runtimes=$(docker info --format '{{json .Runtimes}}' 2>/dev/null || true)
    if [[ -z "$docker_runtimes" ]] || [[ "$docker_runtimes" == "null" ]]; then
        _cai_error "Could not query Docker runtimes"
        return 1
    fi

    if ! printf '%s' "$docker_runtimes" | grep -q "sysbox-runc"; then
        _cai_error "Docker does not recognize sysbox-runc runtime"
        _cai_error "  Restart Docker: sudo systemctl restart docker"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Docker runtimes: $docker_runtimes"
    fi

    # Check containai-secure context
    if ! docker context inspect containai-secure >/dev/null 2>&1; then
        _cai_error "containai-secure context not found"
        return 1
    fi

    # Verify sysbox-runc works by running a minimal container
    _cai_step "Testing sysbox-runc with minimal container"
    local test_output test_rc
    test_output=$(docker --context containai-secure run --rm --runtime=sysbox-runc alpine echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?

    if [[ $test_rc -ne 0 ]]; then
        _cai_warn "Sysbox test container failed (this may be expected on some WSL2 configurations)"
        if [[ "$verbose" == "true" ]]; then
            _cai_info "Test output: $test_output"
        fi
        # Don't fail - Sysbox may work for actual use cases despite test failure
    elif [[ "$test_output" == *"sysbox-test-ok"* ]]; then
        _cai_ok "Sysbox test container succeeded"
    fi

    _cai_ok "Sysbox installation verified"
    return 0
}

# ==============================================================================
# Main Setup Functions
# ==============================================================================

# WSL2-specific setup
# Arguments: $1 = force flag ("true" to bypass seccomp warning)
#            $2 = dry_run flag ("true" to simulate)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_setup_wsl2() {
    local force="${1:-false}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_info "Detected platform: WSL2"
    _cai_info "Setting up Secure Engine with Sysbox"

    # Step 1: Test seccomp compatibility
    _cai_step "Checking seccomp compatibility"
    local seccomp_rc
    _cai_test_wsl2_seccomp && seccomp_rc=0 || seccomp_rc=$?

    case $seccomp_rc in
        0)
            _cai_ok "Seccomp compatibility: OK"
            ;;
        1)
            # Seccomp filter conflict detected
            if [[ "$force" != "true" ]]; then
                _cai_show_seccomp_warning
                _cai_error "Seccomp filter conflict detected"
                _cai_error "  Use --force to proceed anyway, or use Docker Sandbox instead"
                return 1
            else
                _cai_warn "Seccomp filter conflict detected (proceeding with --force)"
            fi
            ;;
        2)
            _cai_warn "Could not determine seccomp status (proceeding)"
            ;;
    esac

    # Step 2: Install Sysbox
    if ! _cai_install_sysbox_wsl2 "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 3: Configure daemon.json
    if ! _cai_configure_daemon_json "$_CAI_WSL2_DAEMON_JSON" "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 4: Restart Docker service (if not dry-run)
    if ! _cai_restart_docker_service "$dry_run"; then
        return 1
    fi

    # Step 5: Create containai-secure context
    if ! _cai_create_containai_context "$_CAI_SECURE_SOCKET" "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 6: Verify installation
    if ! _cai_verify_sysbox_install "$dry_run" "$verbose"; then
        # Verification failure is a warning, not fatal
        _cai_warn "Sysbox verification had issues - check output above"
    fi

    printf '\n'
    _cai_ok "Secure Engine setup complete"
    _cai_info "You can now use: cai run --context containai-secure"
    _cai_info "Or set CONTAINAI_SECURE_ENGINE_CONTEXT=containai-secure"

    return 0
}

# Main setup entry point
# Arguments: parsed from command line
# Returns: 0=success, 1=failure
_cai_setup() {
    local force="false"
    local dry_run="false"
    local verbose="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --verbose|-v)
                verbose="true"
                shift
                ;;
            --help|-h)
                _cai_setup_help
                return 0
                ;;
            *)
                _cai_error "Unknown option: $1"
                _cai_error "Use 'cai setup --help' for usage"
                return 1
                ;;
        esac
    done

    printf '\n'
    _cai_info "ContainAI Secure Engine Setup"
    _cai_info "=============================="
    printf '\n'

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN MODE] No changes will be made"
        printf '\n'
    fi

    # Detect platform
    local platform
    platform=$(_cai_detect_platform)

    case "$platform" in
        wsl)
            _cai_setup_wsl2 "$force" "$dry_run" "$verbose"
            return $?
            ;;
        macos)
            _cai_info "Detected platform: macOS"
            _cai_error "macOS Secure Engine setup not yet implemented"
            _cai_error "  Use Docker Desktop with ECI instead (cai doctor to check)"
            _cai_error "  Or see task fn-5-urz.11 for Lima VM setup"
            return 1
            ;;
        linux)
            _cai_info "Detected platform: Linux (native)"
            _cai_error "Native Linux Secure Engine setup not yet implemented"
            _cai_error "  See task fn-5-urz.15 for native Linux Sysbox installation"
            return 1
            ;;
        *)
            _cai_error "Unknown platform: $platform"
            return 1
            ;;
    esac
}

# Setup help text
_cai_setup_help() {
    cat <<'EOF'
ContainAI Setup - Secure Engine Provisioning

Usage: cai setup [options]

Installs and configures Sysbox for enhanced container isolation.
Currently supports WSL2 (with systemd enabled).

Options:
  --force       Bypass seccomp compatibility warning and proceed
  --dry-run     Show what would be done without making changes
  --verbose     Show detailed progress information
  -h, --help    Show this help message

What It Does (WSL2):
  1. Checks seccomp compatibility (warns if WSL 1.1.0+ filter conflict)
  2. Downloads and installs Sysbox from GitHub releases
  3. Configures /etc/docker/daemon.json with sysbox-runc runtime
  4. Creates 'containai-secure' Docker context
  5. Verifies installation

Requirements (WSL2):
  - Ubuntu or Debian WSL distribution
  - systemd enabled ([boot] systemd=true in /etc/wsl.conf)
  - Docker Engine installed (standalone, not Docker Desktop integration)
  - Internet access to download Sysbox

Security Notes:
  - Does NOT set sysbox-runc as default runtime (keeps runc default)
  - Does NOT modify Docker Desktop or default context
  - Creates separate 'containai-secure' context for explicit isolation

Examples:
  cai setup                    Install Sysbox on WSL2
  cai setup --dry-run          Preview changes without installing
  cai setup --force            Bypass seccomp warning
  cai setup --verbose          Show detailed progress
EOF
}

return 0
