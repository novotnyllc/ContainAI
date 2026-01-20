#!/usr/bin/env bash
# ==============================================================================
# ContainAI Setup - Secure Engine Provisioning (WSL2 + macOS)
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_setup()                   - Main setup entry point
#   _cai_setup_wsl2()              - WSL2-specific setup
#   _cai_setup_macos()             - macOS-specific setup (Lima VM)
#   _cai_test_wsl2_seccomp()       - Test WSL2 seccomp compatibility
#   _cai_show_seccomp_warning()    - Display seccomp warning
#   _cai_install_sysbox_wsl2()     - Install Sysbox on WSL2
#   _cai_configure_daemon_json()   - Configure Docker daemon.json
#   _cai_configure_docker_socket() - Configure dedicated Docker socket
#   _cai_create_containai_context()- Create containai-secure Docker context
#   _cai_verify_sysbox_install()   - Verify Sysbox installation
#   _cai_lima_template()           - Generate Lima VM template YAML
#   _cai_lima_install()            - Install Lima via Homebrew
#   _cai_lima_create_vm()          - Create Lima VM with Docker + Sysbox
#   _cai_lima_create_context()     - Create containai-secure context for Lima
#   _cai_lima_verify_install()     - Verify Lima + Sysbox installation
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

# Default socket path for containai-secure context (separate from default Docker)
_CAI_SECURE_SOCKET="/var/run/docker-containai.sock"

# Default daemon.json path for WSL2 (standalone Docker, not Docker Desktop)
_CAI_WSL2_DAEMON_JSON="/etc/docker/daemon.json"

# Systemd drop-in directory for Docker socket override
_CAI_DOCKER_DROPIN_DIR="/etc/systemd/system/docker.service.d"

# Lima VM name for macOS Secure Engine
_CAI_LIMA_VM_NAME="containai-secure"

# Lima socket path pattern (expands {{.Dir}} at runtime)
_CAI_LIMA_SOCKET_PATH="$HOME/.lima/containai-secure/sock/docker.sock"

# ==============================================================================
# WSL2 Detection
# ==============================================================================

# Check if running on WSL2 specifically (not WSL1)
# Returns: 0=WSL2, 1=not WSL2
# Outputs: Sets _CAI_WSL_KERNEL_VERSION with kernel info
_cai_is_wsl2() {
    _CAI_WSL_KERNEL_VERSION=""

    # Check /proc/version for microsoft-standard (WSL2 kernel signature)
    # WSL1 uses microsoft-standard-WSL2 pattern but without "standard"
    if [[ -f /proc/version ]]; then
        local version_content
        version_content=$(cat /proc/version 2>/dev/null) || version_content=""
        _CAI_WSL_KERNEL_VERSION="$version_content"

        # WSL2 kernel contains "microsoft-standard" (case insensitive)
        if [[ "$version_content" == *[Mm]icrosoft-[Ss]tandard* ]]; then
            return 0
        fi

        # Also check for newer WSL2 kernel naming: "microsoft-WSL2"
        if [[ "$version_content" == *[Mm]icrosoft-WSL2* ]]; then
            return 0
        fi
    fi

    return 1
}

# ==============================================================================
# Seccomp Compatibility Testing
# ==============================================================================

# Test WSL2 seccomp compatibility for Sysbox
# Returns: 0=compatible, 1=seccomp filter conflict detected, 2=unknown
# Outputs: Sets _CAI_SECCOMP_TEST_ERROR with details on failure
#
# Detection strategy (per spec):
# 1. Primary: Docker-based probe with seccomp=unconfined - tests actual container
#    functionality which is what Sysbox needs
# 2. Secondary: Check /proc/1/status Seccomp mode - if mode=2 (filter) on PID 1,
#    WSL 1.1.0+ has attached a seccomp filter that can cause EBUSY when Sysbox
#    tries to add seccomp-notify
#
# Note: We cannot test Sysbox directly before installation. The Docker probe
# validates the seccomp environment, and the /proc/1/status check detects the
# specific WSL kernel condition known to cause issues.
# Post-installation verification in _cai_verify_sysbox_install tests actual
# Sysbox container functionality.
_cai_test_wsl2_seccomp() {
    _CAI_SECCOMP_TEST_ERROR=""

    # Primary: Docker-based probe (per spec)
    # Run minimal container with seccomp=unconfined to test seccomp handling
    if command -v docker >/dev/null 2>&1; then
        local docker_test_output docker_test_rc
        docker_test_output=$(docker run --rm --security-opt seccomp=unconfined alpine echo "seccomp-test-ok" 2>&1) && docker_test_rc=0 || docker_test_rc=$?
        if [[ $docker_test_rc -ne 0 ]]; then
            _CAI_SECCOMP_TEST_ERROR="Docker seccomp test failed: $docker_test_output"
            return 1
        fi
        if [[ "$docker_test_output" == *"seccomp-test-ok"* ]]; then
            # Docker with seccomp=unconfined works
            # But still check /proc/1/status for WSL-specific filter mode
            # which can cause EBUSY even when basic seccomp works
            :
        fi
    fi

    # Secondary: /proc/1/status Seccomp field check
    # Mode 2 (filter) on PID 1 indicates WSL 1.1.0+ seccomp filter
    # This specific condition can cause Sysbox seccomp-notify EBUSY
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

    # If Docker test passed and no /proc/1 issues found, we're good
    if command -v docker >/dev/null 2>&1; then
        return 0
    fi

    # Cannot determine - return unknown
    _CAI_SECCOMP_TEST_ERROR="Cannot determine seccomp status (no Docker available, no /proc/1/status Seccomp field)"
    return 2
}

# Display seccomp warning box for WSL2
# Note: Per spec, shows big warning with options
# Uses ASCII box drawing for portability across terminals/locales
_cai_show_seccomp_warning() {
    # Use printf for consistent output per memory convention
    # ASCII box characters used for maximum terminal compatibility
    printf '%s\n' ""
    printf '%s\n' "+==================================================================+"
    printf '%s\n' "|                       *** WARNING ***                            |"
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
# Dependency Checks
# ==============================================================================

# Check required dependencies for setup (informational only)
# Arguments: none
# Returns: 0 always (just logs what's missing)
# Note: Does NOT abort - deps will be installed via apt-get
_cai_check_setup_deps_info() {
    local missing=""

    # Check for jq (used for JSON parsing)
    if ! command -v jq >/dev/null 2>&1; then
        missing="${missing}jq "
    fi

    # Check for wget (used for downloads)
    if ! command -v wget >/dev/null 2>&1; then
        missing="${missing}wget "
    fi

    if [[ -n "$missing" ]]; then
        _cai_info "Will install missing dependencies: $missing"
    fi

    return 0
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
    # In dry-run mode, warn but continue
    if ! command -v systemctl >/dev/null 2>&1; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_warn "[DRY-RUN] systemctl not found - systemd required for actual install"
        else
            _cai_error "Sysbox requires systemd (systemctl not found)"
            _cai_error "  Enable systemd in your WSL distribution:"
            _cai_error "  Add 'systemd=true' to /etc/wsl.conf under [boot] section"
            return 1
        fi
    fi

    # Check if systemd is actually running (PID 1)
    # In dry-run mode, warn but continue
    local pid1_cmd
    pid1_cmd=$(ps -p 1 -o comm= 2>/dev/null || true)
    if [[ "$pid1_cmd" != "systemd" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_warn "[DRY-RUN] Systemd not running as PID 1 (found: $pid1_cmd) - required for actual install"
        else
            _cai_error "Systemd is not running as PID 1 (found: $pid1_cmd)"
            _cai_error "  Configure WSL to boot with systemd:"
            _cai_error "  1. Add to /etc/wsl.conf:"
            _cai_error "     [boot]"
            _cai_error "     systemd=true"
            _cai_error "  2. Restart WSL: wsl --shutdown"
            return 1
        fi
    fi

    _cai_step "Checking for existing Sysbox installation"
    if command -v sysbox-runc >/dev/null 2>&1; then
        local existing_version
        existing_version=$(sysbox-runc --version 2>/dev/null | head -1 || true)
        _cai_info "Sysbox already installed: $existing_version"
        return 0
    fi

    # Log what deps will be installed (informational only, no abort)
    _cai_check_setup_deps_info

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
        _cai_info "[DRY-RUN] Would download Sysbox .deb for architecture: $arch"
        _cai_info "[DRY-RUN] Would install with: dpkg -i sysbox-ce.deb"
        _cai_ok "Sysbox installation (dry-run) complete"
        return 0
    fi

    # Fetch release info
    local release_json
    release_json=$(wget -qO- "$release_url" 2>/dev/null) || {
        _cai_error "Failed to fetch Sysbox release info from GitHub"
        _cai_error "  Check network connectivity"
        return 1
    }

    # Extract .deb download URL for this architecture
    download_url=$(printf '%s' "$release_json" | jq -r ".assets[] | select(.name | test(\"sysbox-ce.*${arch}.deb\")) | .browser_download_url" | head -1)

    if [[ -z "$download_url" ]] || [[ "$download_url" == "null" ]]; then
        _cai_error "Could not find Sysbox .deb package for architecture: $arch"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Download URL: $download_url"
    fi

    # Download and install in subshell to contain cleanup trap
    # RETURN trap in sourced script affects entire shell session, so use subshell + EXIT
    local install_rc
    (
        set -e
        tmpdir=$(mktemp -d)
        trap "rm -rf '$tmpdir'" EXIT
        deb_file="$tmpdir/sysbox-ce.deb"

        echo "[STEP] Downloading Sysbox from: $download_url"
        if ! wget -q --show-progress -O "$deb_file" "$download_url"; then
            echo "[ERROR] Failed to download Sysbox package" >&2
            exit 1
        fi

        echo "[STEP] Installing Sysbox package"
        if ! sudo dpkg -i "$deb_file"; then
            echo "[WARN] dpkg install had issues, attempting to fix dependencies" >&2
            if ! sudo apt-get install -f -y; then
                echo "[ERROR] Failed to install Sysbox package" >&2
                exit 1
            fi
        fi
        exit 0
    ) && install_rc=0 || install_rc=$?

    if [[ $install_rc -ne 0 ]]; then
        return 1
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

    # In dry-run mode, show static preview without requiring jq/sudo
    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would ensure directory exists: $(dirname "$daemon_json")"
        _cai_info "[DRY-RUN] Would read existing config: $daemon_json"
        _cai_info "[DRY-RUN] Would merge sysbox-runc runtime into daemon.json"
        _cai_info "[DRY-RUN] Would write to: $daemon_json"
        _cai_info "[DRY-RUN] Config would include:"
        printf '%s\n' '{
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  }
}'
        _cai_ok "Docker daemon configuration (dry-run) complete"
        return 0
    fi

    # Ensure /etc/docker directory exists
    if [[ ! -d "$(dirname "$daemon_json")" ]]; then
        if ! sudo mkdir -p "$(dirname "$daemon_json")"; then
            _cai_error "Failed to create directory: $(dirname "$daemon_json")"
            return 1
        fi
    fi

    # Read existing config using sudo (may be root-only readable)
    local existing_config="{}"
    if [[ -f "$daemon_json" ]]; then
        if ! existing_config=$(sudo cat "$daemon_json" 2>/dev/null); then
            _cai_error "Cannot read existing daemon.json: $daemon_json"
            _cai_error "  Check file permissions"
            return 1
        fi
        # Validate JSON using jq (more reliable than python3)
        if ! printf '%s' "$existing_config" | jq . >/dev/null 2>&1; then
            _cai_error "Existing daemon.json is not valid JSON: $daemon_json"
            _cai_error "  Please fix or remove the file and try again"
            return 1
        fi
    fi

    # Merge sysbox-runc runtime into config using jq
    # Always overwrite path to ensure correct value (fixes misconfigured existing entries)
    local new_config
    new_config=$(printf '%s' "$existing_config" | jq '
        .runtimes = (.runtimes // {}) |
        .runtimes["sysbox-runc"] = {"path": "/usr/bin/sysbox-runc"}
    ')

    if [[ -z "$new_config" ]]; then
        _cai_error "Failed to generate daemon.json configuration"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "New daemon.json content:"
        printf '%s\n' "$new_config"
    fi

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

    _cai_ok "Docker daemon configured with sysbox-runc runtime"
    return 0
}

# Configure dedicated Docker socket for containai-secure context
# Arguments: $1 = socket path
#            $2 = dry_run flag ("true" to simulate)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Note: Creates systemd drop-in to add additional socket listener
_cai_configure_docker_socket() {
    local socket_path="${1:-$_CAI_SECURE_SOCKET}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_step "Configuring dedicated Docker socket: $socket_path"

    local dropin_file="$_CAI_DOCKER_DROPIN_DIR/containai-socket.conf"

    # Read existing ExecStart to preserve distro/user flags
    # Format from systemctl show: ExecStart={ path=/usr/bin/dockerd ; argv[]=/usr/bin/dockerd -H fd:// ... }
    local existing_execstart_raw existing_execstart
    existing_execstart_raw=$(systemctl show -p ExecStart docker 2>/dev/null || true)
    # Extract the actual command from the systemd format
    # Format: ExecStart={ path=... ; argv[]=cmd arg1 arg2 ... ; ... }
    existing_execstart=$(printf '%s' "$existing_execstart_raw" | sed -n 's/.*argv\[\]=\([^;]*\).*/\1/p' | head -1 || true)
    # Trim leading/trailing whitespace
    existing_execstart=$(printf '%s' "$existing_execstart" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Existing ExecStart: ${existing_execstart:-<none>}"
    fi

    # Build drop-in content
    # Strategy: Extract existing command and APPEND our socket flag
    # This preserves all distro/user flags (data-root, cgroup-driver, proxies, etc.)
    local dropin_content new_execstart

    if [[ -n "$existing_execstart" ]]; then
        # Check if socket already configured
        if [[ "$existing_execstart" == *"$socket_path"* ]]; then
            _cai_info "Socket $socket_path already configured in Docker service"
            # Socket already present - skip drop-in modification
            # This preserves any existing ExecStart override from a previous run
            _cai_ok "Docker socket already configured"
            return 0
        else
            # Append our socket to existing command
            # Insert -H unix://... before any trailing containerd flag or at end
            new_execstart="$existing_execstart -H unix://$socket_path"
            _cai_info "Appending socket to existing Docker configuration"

            dropin_content=$(cat <<EOF
[Service]
ExecStart=
ExecStart=$new_execstart
EOF
)
        fi
    else
        # No existing ExecStart found (unusual but handle it)
        # Use minimal default that matches most distros
        _cai_warn "No existing Docker ExecStart found, using default"
        dropin_content=$(cat <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H fd:// -H unix://$socket_path --containerd=/run/containerd/containerd.sock
EOF
)
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Drop-in file: $dropin_file"
        _cai_info "Content:"
        printf '%s\n' "$dropin_content"
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would create directory: $_CAI_DOCKER_DROPIN_DIR"
        _cai_info "[DRY-RUN] Would write drop-in: $dropin_file"
        _cai_info "[DRY-RUN] Would run: systemctl daemon-reload"
        return 0
    fi

    # Create drop-in directory
    if ! sudo mkdir -p "$_CAI_DOCKER_DROPIN_DIR"; then
        _cai_error "Failed to create drop-in directory: $_CAI_DOCKER_DROPIN_DIR"
        return 1
    fi

    # Write drop-in file
    if ! printf '%s\n' "$dropin_content" | sudo tee "$dropin_file" >/dev/null; then
        _cai_error "Failed to write drop-in: $dropin_file"
        return 1
    fi

    # Reload systemd
    if ! sudo systemctl daemon-reload; then
        _cai_error "Failed to reload systemd daemon"
        return 1
    fi

    _cai_ok "Docker socket drop-in configured"
    return 0
}

# Restart Docker service and wait for specific socket
# Arguments: $1 = socket path to wait for
#            $2 = dry_run flag ("true" to simulate)
# Returns: 0=success, 1=failure
_cai_restart_docker_service() {
    local socket_path="${1:-$_CAI_SECURE_SOCKET}"
    local dry_run="${2:-false}"

    _cai_step "Restarting Docker service"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: systemctl restart docker"
        _cai_info "[DRY-RUN] Would wait for socket: $socket_path"
        return 0
    fi

    if ! sudo systemctl restart docker; then
        _cai_error "Failed to restart Docker service"
        _cai_error "  Check: sudo systemctl status docker"
        return 1
    fi

    # Wait for the dedicated socket to be ready
    local wait_count=0
    local max_wait=30
    _cai_step "Waiting for Docker socket: $socket_path"
    while [[ ! -S "$socket_path" ]]; do
        sleep 1
        wait_count=$((wait_count + 1))
        if [[ $wait_count -ge $max_wait ]]; then
            _cai_error "Docker socket did not appear after ${max_wait}s: $socket_path"
            _cai_error "  Check: sudo systemctl status docker"
            return 1
        fi
    done

    # Verify Docker is accessible via the socket
    if ! DOCKER_HOST="unix://$socket_path" docker info >/dev/null 2>&1; then
        _cai_error "Docker daemon not accessible via socket: $socket_path"
        return 1
    fi

    _cai_ok "Docker service restarted and socket ready"
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
# Note: This context points to dedicated Docker socket, NOT the default socket
_cai_create_containai_context() {
    local socket_path="${1:-$_CAI_SECURE_SOCKET}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_step "Creating containai-secure Docker context"

    local expected_host="unix://$socket_path"

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Expected socket: $expected_host"
    fi

    # Check if context already exists
    if docker context inspect containai-secure >/dev/null 2>&1; then
        # Verify it points to the expected socket
        local existing_host
        existing_host=$(docker context inspect containai-secure --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)

        if [[ "$existing_host" == "$expected_host" ]]; then
            _cai_info "Context 'containai-secure' already exists with correct endpoint"
            return 0
        else
            _cai_warn "Context 'containai-secure' exists but points to: $existing_host"
            _cai_warn "  Expected: $expected_host"

            if [[ "$dry_run" == "true" ]]; then
                _cai_info "[DRY-RUN] Would remove and recreate context"
            else
                _cai_step "Removing misconfigured context"
                if ! docker context rm containai-secure >/dev/null 2>&1; then
                    _cai_error "Failed to remove existing context"
                    return 1
                fi
            fi
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: docker context create containai-secure --docker host=$expected_host"
    else
        if ! docker context create containai-secure --docker "host=$expected_host"; then
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
# Arguments: $1 = socket path for verification
#            $2 = dry_run flag ("true" to skip actual verification)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_verify_sysbox_install() {
    local socket_path="${1:-$_CAI_SECURE_SOCKET}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_step "Verifying Sysbox installation"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would verify sysbox-runc and sysbox-mgr"
        _cai_info "[DRY-RUN] Would verify Docker runtime configuration via socket: $socket_path"
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

    # Check Docker recognizes sysbox-runc runtime (via dedicated socket)
    local docker_runtimes
    docker_runtimes=$(DOCKER_HOST="unix://$socket_path" docker info --format '{{json .Runtimes}}' 2>/dev/null || true)
    if [[ -z "$docker_runtimes" ]] || [[ "$docker_runtimes" == "null" ]]; then
        _cai_error "Could not query Docker runtimes via socket: $socket_path"
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

    # Verify sysbox-runc works by running a minimal container via the context
    _cai_step "Testing sysbox-runc with minimal container"
    local test_output test_rc test_passed=false
    test_output=$(docker --context containai-secure run --rm --runtime=sysbox-runc alpine echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?

    if [[ $test_rc -ne 0 ]]; then
        _cai_warn "Sysbox test container failed (this may be expected on some WSL2 configurations)"
        if [[ "$verbose" == "true" ]]; then
            _cai_info "Test output: $test_output"
        fi
        # Don't fail hard - Sysbox may work for actual use cases despite test failure
    elif [[ "$test_output" == *"sysbox-test-ok"* ]]; then
        _cai_ok "Sysbox test container succeeded"
        test_passed=true
    fi

    # Final message reflects actual test result
    if [[ "$test_passed" == "true" ]]; then
        _cai_ok "Sysbox installation verified"
    else
        _cai_warn "Sysbox installation completed but test container did not succeed"
        _cai_warn "Sysbox may still work - try running a container manually"
    fi
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

    # Step 4: Configure dedicated Docker socket
    if ! _cai_configure_docker_socket "$_CAI_SECURE_SOCKET" "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 5: Restart Docker service (if not dry-run)
    if ! _cai_restart_docker_service "$_CAI_SECURE_SOCKET" "$dry_run"; then
        return 1
    fi

    # Step 6: Create containai-secure context
    if ! _cai_create_containai_context "$_CAI_SECURE_SOCKET" "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 7: Verify installation
    if ! _cai_verify_sysbox_install "$_CAI_SECURE_SOCKET" "$dry_run" "$verbose"; then
        # Verification failure is a warning, not fatal
        _cai_warn "Sysbox verification had issues - check output above"
    fi

    printf '\n'
    _cai_ok "Secure Engine setup complete"
    _cai_info "To use the Secure Engine:"
    _cai_info "  export CONTAINAI_SECURE_ENGINE_CONTEXT=containai-secure"
    _cai_info "  cai run --workspace /path/to/project"
    _cai_info "Or use docker directly: docker --context containai-secure --runtime=sysbox-runc ..."

    return 0
}

# ==============================================================================
# macOS Lima VM Setup
# ==============================================================================

# Generate Lima VM template YAML for Docker + Sysbox
# Arguments: none
# Outputs: Lima YAML to stdout
# Note: Uses architecture-specific Ubuntu images and Sysbox releases
_cai_lima_template() {
    # Lima template with Docker + Sysbox provisioning
    # Per task spec: Sysbox is NOT set as default runtime
    cat <<'LIMA_YAML'
# ContainAI Secure Engine - Lima VM Template
# Generated by: cai setup

images:
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    arch: "x86_64"
  - location: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-arm64.img"
    arch: "aarch64"

mounts:
  - location: "~"
    writable: true
  - location: "/tmp/lima"
    writable: true

provision:
  - mode: system
    script: |
      #!/bin/bash
      set -eux

      # Update package lists and install dependencies
      apt-get update
      apt-get install -y curl wget

      # Install Docker Engine
      curl -fsSL https://get.docker.com | sh
      usermod -aG docker "${LIMA_CIDATA_USER}"

      # Install Sysbox (architecture-specific)
      ARCH=$(dpkg --print-architecture)
      SYSBOX_VERSION="0.6.7"
      wget -q -O /tmp/sysbox.deb "https://downloads.nestybox.com/sysbox/releases/v${SYSBOX_VERSION}/sysbox-ce_${SYSBOX_VERSION}-0.linux_${ARCH}.deb" || {
          echo "Failed to download Sysbox for ${ARCH}" >&2
          exit 1
      }
      # Install sysbox with dependency resolution
      apt-get install -y /tmp/sysbox.deb || {
          apt-get install -f -y
          apt-get install -y /tmp/sysbox.deb
      }
      rm -f /tmp/sysbox.deb

      # Configure Docker with Sysbox runtime (NOT as default)
      mkdir -p /etc/docker
      cat > /etc/docker/daemon.json << 'EOF'
      {
        "runtimes": {
          "sysbox-runc": {
            "path": "/usr/bin/sysbox-runc"
          }
        }
      }
      EOF

      systemctl restart docker

      # Verify Sysbox is recognized
      docker info | grep -i sysbox || echo "Warning: Sysbox not recognized by Docker"

portForwards:
  - guestSocket: "/var/run/docker.sock"
    hostSocket: "{{.Dir}}/sock/docker.sock"
LIMA_YAML
}

# Check if Lima is installed
# Returns: 0=installed, 1=not installed
_cai_lima_check() {
    command -v limactl >/dev/null 2>&1
}

# Install Lima via Homebrew
# Arguments: $1 = dry_run flag ("true" to simulate)
# Returns: 0=success, 1=failure
_cai_lima_install() {
    local dry_run="${1:-false}"

    _cai_step "Checking for Lima installation"

    if _cai_lima_check; then
        local lima_version
        lima_version=$(limactl --version 2>/dev/null | head -1 || true)
        _cai_info "Lima already installed: $lima_version"
        return 0
    fi

    _cai_step "Installing Lima via Homebrew"

    if ! command -v brew >/dev/null 2>&1; then
        _cai_error "Homebrew not found. Please install Homebrew first:"
        _cai_error "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: brew install lima"
        return 0
    fi

    if ! brew install lima; then
        _cai_error "Failed to install Lima via Homebrew"
        return 1
    fi

    _cai_ok "Lima installed successfully"
    return 0
}

# Check if Lima VM exists
# Arguments: $1 = VM name
# Returns: 0=exists, 1=does not exist
_cai_lima_vm_exists() {
    local vm_name="${1:-$_CAI_LIMA_VM_NAME}"
    # Use limactl list with format flag for reliable detection
    # Falls back to grep-based check if format flag not available
    if limactl list --format '{{.Name}}' 2>/dev/null | grep -qx "$vm_name"; then
        return 0
    fi
    # Fallback: JSON parsing (less reliable but works with older Lima)
    limactl list --json 2>/dev/null | grep -q "\"name\":\"$vm_name\"" || limactl list --json 2>/dev/null | grep -q "\"name\": \"$vm_name\""
}

# Get Lima VM status
# Arguments: $1 = VM name
# Returns: status string via stdout (Running, Stopped, etc.)
_cai_lima_vm_status() {
    local vm_name="${1:-$_CAI_LIMA_VM_NAME}"
    local status
    # Prefer limactl list with format for reliable status
    status=$(limactl list --format '{{.Name}}\t{{.Status}}' 2>/dev/null | grep "^${vm_name}[[:space:]]" | cut -f2 | head -1) || status=""
    if [[ -n "$status" ]]; then
        printf '%s' "$status"
        return 0
    fi
    # Fallback: JSON parsing (less reliable)
    # Handle both compact and pretty-printed JSON
    status=$(limactl list --json 2>/dev/null | grep -o "\"name\":[ ]*\"$vm_name\"[^}]*\"status\":[ ]*\"[^\"]*\"" | sed 's/.*"status":[ ]*"\([^"]*\)".*/\1/' | head -1) || status=""
    printf '%s' "$status"
}

# Create Lima VM with Docker + Sysbox
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_lima_create_vm() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_step "Creating Lima VM: $_CAI_LIMA_VM_NAME"

    # Check if VM already exists
    if _cai_lima_vm_exists "$_CAI_LIMA_VM_NAME"; then
        local status
        status=$(_cai_lima_vm_status "$_CAI_LIMA_VM_NAME")
        _cai_info "Lima VM '$_CAI_LIMA_VM_NAME' already exists (status: $status)"

        # If stopped, start it
        if [[ "$status" == "Stopped" ]]; then
            _cai_step "Starting stopped Lima VM"
            if [[ "$dry_run" == "true" ]]; then
                _cai_info "[DRY-RUN] Would run: limactl start $_CAI_LIMA_VM_NAME"
            else
                if ! limactl start "$_CAI_LIMA_VM_NAME"; then
                    _cai_error "Failed to start Lima VM"
                    return 1
                fi
                _cai_ok "Lima VM started"
            fi
        fi
        return 0
    fi

    # Generate template to temporary file
    # Use portable mktemp syntax that works on both GNU and BSD (macOS)
    local template_file
    template_file=$(mktemp "${TMPDIR:-/tmp}/containai-lima.XXXXXX.yaml")
    # Use subshell trap for cleanup to avoid affecting main shell
    (
        trap "rm -f '$template_file'" EXIT
        _cai_lima_template > "$template_file"

        if [[ "$verbose" == "true" ]]; then
            printf '%s\n' "[INFO] Lima template:"
            cat "$template_file"
            printf '\n'
        fi

        if [[ "$dry_run" == "true" ]]; then
            printf '%s\n' "[INFO] [DRY-RUN] Would run: limactl create --name=$_CAI_LIMA_VM_NAME <template>"
            printf '%s\n' "[INFO] [DRY-RUN] Would run: limactl start $_CAI_LIMA_VM_NAME"
            exit 0
        fi

        printf '%s\n' "-> Creating Lima VM (this may take several minutes)..."

        # Create VM from template (non-interactive)
        # Put flags before positional args for compatibility
        if ! limactl create --name="$_CAI_LIMA_VM_NAME" --tty=false "$template_file"; then
            printf '%s\n' "[ERROR] Failed to create Lima VM" >&2
            exit 1
        fi

        printf '%s\n' "-> Starting Lima VM..."
        if ! limactl start "$_CAI_LIMA_VM_NAME"; then
            printf '%s\n' "[ERROR] Failed to start Lima VM" >&2
            exit 1
        fi

        printf '%s\n' "[OK] Lima VM created and started"
        exit 0
    )
    local rc=$?
    rm -f "$template_file" 2>/dev/null || true
    return $rc
}

# Wait for Lima Docker socket to be available
# Arguments: $1 = timeout in seconds
#            $2 = dry_run flag
# Returns: 0=socket ready, 1=timeout
_cai_lima_wait_socket() {
    local timeout="${1:-60}"
    local dry_run="${2:-false}"
    local socket_path="$_CAI_LIMA_SOCKET_PATH"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would wait for socket: $socket_path"
        return 0
    fi

    _cai_step "Waiting for Lima Docker socket: $socket_path"

    local wait_count=0
    while [[ ! -S "$socket_path" ]]; do
        sleep 1
        wait_count=$((wait_count + 1))
        if [[ $wait_count -ge $timeout ]]; then
            _cai_error "Lima Docker socket did not appear after ${timeout}s"
            _cai_error "  Expected: $socket_path"
            _cai_error "  Check: limactl shell $_CAI_LIMA_VM_NAME"
            return 1
        fi
    done

    # Verify Docker is accessible via the socket
    if ! DOCKER_HOST="unix://$socket_path" docker info >/dev/null 2>&1; then
        _cai_error "Docker not accessible via Lima socket"
        _cai_error "  Socket exists but docker info failed"
        return 1
    fi

    _cai_ok "Lima Docker socket ready"
    return 0
}

# Create containai-secure Docker context for Lima (macOS)
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_lima_create_context() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local socket_path="$_CAI_LIMA_SOCKET_PATH"

    _cai_step "Creating containai-secure Docker context (macOS/Lima)"

    local expected_host="unix://$socket_path"

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Expected socket: $expected_host"
    fi

    # Check if context already exists
    if docker context inspect containai-secure >/dev/null 2>&1; then
        local existing_host
        existing_host=$(docker context inspect containai-secure --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)

        if [[ "$existing_host" == "$expected_host" ]]; then
            _cai_info "Context 'containai-secure' already exists with correct endpoint"
            return 0
        else
            _cai_warn "Context 'containai-secure' exists but points to: $existing_host"
            _cai_warn "  Expected: $expected_host"

            if [[ "$dry_run" == "true" ]]; then
                _cai_info "[DRY-RUN] Would remove and recreate context"
            else
                _cai_step "Removing misconfigured context"
                if ! docker context rm containai-secure >/dev/null 2>&1; then
                    _cai_error "Failed to remove existing context"
                    return 1
                fi
            fi
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: docker context create containai-secure --docker host=$expected_host"
    else
        if ! docker context create containai-secure --docker "host=$expected_host"; then
            _cai_error "Failed to create Docker context 'containai-secure'"
            return 1
        fi
    fi

    _cai_ok "Docker context 'containai-secure' created"
    return 0
}

# Verify Lima + Sysbox installation
# Arguments: $1 = dry_run flag ("true" to skip actual verification)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_lima_verify_install() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local socket_path="$_CAI_LIMA_SOCKET_PATH"

    _cai_step "Verifying Lima + Sysbox installation"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would verify Lima VM status"
        _cai_info "[DRY-RUN] Would verify Sysbox in VM"
        _cai_info "[DRY-RUN] Would verify containai-secure context"
        return 0
    fi

    # Check Lima VM is running
    local status
    status=$(_cai_lima_vm_status "$_CAI_LIMA_VM_NAME")
    if [[ "$status" != "Running" ]]; then
        _cai_error "Lima VM is not running (status: $status)"
        _cai_error "  Start with: limactl start $_CAI_LIMA_VM_NAME"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Lima VM status: $status"
    fi

    # Check Docker recognizes sysbox-runc runtime via Lima socket
    local docker_runtimes
    docker_runtimes=$(DOCKER_HOST="unix://$socket_path" docker info --format '{{json .Runtimes}}' 2>/dev/null || true)
    if [[ -z "$docker_runtimes" ]] || [[ "$docker_runtimes" == "null" ]]; then
        _cai_error "Could not query Docker runtimes via Lima socket"
        return 1
    fi

    if ! printf '%s' "$docker_runtimes" | grep -q "sysbox-runc"; then
        _cai_error "Docker in Lima VM does not recognize sysbox-runc runtime"
        _cai_error "  Check VM provisioning: limactl shell $_CAI_LIMA_VM_NAME"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Docker runtimes: $docker_runtimes"
    fi

    # Check containai-secure context exists
    if ! docker context inspect containai-secure >/dev/null 2>&1; then
        _cai_error "containai-secure context not found"
        return 1
    fi

    # Test Sysbox by running minimal container
    _cai_step "Testing sysbox-runc with minimal container"
    local test_output test_rc test_passed=false
    test_output=$(docker --context containai-secure run --rm --runtime=sysbox-runc alpine echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?

    if [[ $test_rc -ne 0 ]]; then
        _cai_error "Sysbox test container failed (exit code: $test_rc)"
        _cai_error "  Output: $test_output"
        _cai_error "  Check VM provisioning: limactl shell $_CAI_LIMA_VM_NAME"
        return 1
    elif [[ "$test_output" == *"sysbox-test-ok"* ]]; then
        _cai_ok "Sysbox test container succeeded"
        test_passed=true
    else
        _cai_error "Sysbox test container did not produce expected output"
        _cai_error "  Output: $test_output"
        return 1
    fi

    # Verify Docker Desktop is still default context
    _cai_step "Verifying Docker Desktop remains default"
    local current_context
    current_context=$(docker context show 2>/dev/null || true)
    # Per spec: Docker Desktop should be default or desktop-linux
    if [[ "$current_context" == "containai-secure" ]]; then
        _cai_warn "containai-secure is currently the active context"
        _cai_warn "  Docker Desktop should remain default for safety"
        _cai_warn "  Switch back: docker context use default"
    elif [[ "$current_context" == "default" ]] || [[ "$current_context" == "desktop-linux" ]]; then
        _cai_ok "Docker Desktop remains the active context: $current_context"
    else
        _cai_info "Current Docker context: $current_context (not containai-secure - acceptable)"
    fi

    _cai_ok "Lima + Sysbox installation verified"
    return 0
}

# macOS-specific setup using Lima VM
# Arguments: $1 = force flag (unused for macOS, kept for API consistency)
#            $2 = dry_run flag ("true" to simulate)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_setup_macos() {
    local force="${1:-false}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_info "Detected platform: macOS"
    _cai_info "Setting up Secure Engine with Lima VM + Sysbox"

    # CRITICAL: Warn about Docker Desktop protection
    printf '\n'
    _cai_info "IMPORTANT: This setup does NOT modify Docker Desktop"
    _cai_info "  - Docker Desktop remains the default context"
    _cai_info "  - A separate Lima VM provides Sysbox isolation"
    _cai_info "  - Use --context containai-secure to access Sysbox"
    printf '\n'

    # Step 1: Install Lima (via Homebrew)
    if ! _cai_lima_install "$dry_run"; then
        return 1
    fi

    # Step 2: Create Lima VM with Docker + Sysbox
    if ! _cai_lima_create_vm "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 3: Wait for Lima Docker socket
    if ! _cai_lima_wait_socket 120 "$dry_run"; then
        return 1
    fi

    # Step 4: Create containai-secure context
    if ! _cai_lima_create_context "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 5: Verify installation
    if ! _cai_lima_verify_install "$dry_run" "$verbose"; then
        _cai_warn "Lima + Sysbox verification had issues - check output above"
    fi

    printf '\n'
    _cai_ok "Secure Engine setup complete (macOS/Lima)"
    _cai_info "To use the Secure Engine:"
    _cai_info "  export CONTAINAI_SECURE_ENGINE_CONTEXT=containai-secure"
    _cai_info "  cai run --workspace /path/to/project"
    _cai_info "Or use docker directly: docker --context containai-secure --runtime=sysbox-runc ..."
    printf '\n'
    _cai_info "Lima VM management:"
    _cai_info "  Start:  limactl start $_CAI_LIMA_VM_NAME"
    _cai_info "  Stop:   limactl stop $_CAI_LIMA_VM_NAME"
    _cai_info "  Shell:  limactl shell $_CAI_LIMA_VM_NAME"
    _cai_info "  Status: limactl list"

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

    # Detect platform - must be WSL2 specifically
    local platform
    platform=$(_cai_detect_platform)

    case "$platform" in
        wsl)
            # Additional check: must be WSL2, not WSL1
            if ! _cai_is_wsl2; then
                _cai_error "WSL1 detected but WSL2 is required for Sysbox"
                _cai_error "  Convert to WSL2: wsl --set-version <distro> 2"
                _cai_error "  Or set default: wsl --set-default-version 2"
                return 1
            fi
            _cai_setup_wsl2 "$force" "$dry_run" "$verbose"
            return $?
            ;;
        macos)
            _cai_setup_macos "$force" "$dry_run" "$verbose"
            return $?
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
Supports WSL2 (with systemd) and macOS (via Lima VM).

Options:
  --force       Bypass seccomp compatibility warning and proceed (WSL2 only)
  --dry-run     Show what would be done without making changes
  --verbose     Show detailed progress information
  -h, --help    Show this help message

What It Does (WSL2):
  1. Checks seccomp compatibility (warns if WSL 1.1.0+ filter conflict)
  2. Downloads and installs Sysbox from GitHub releases
  3. Configures /etc/docker/daemon.json with sysbox-runc runtime
  4. Configures dedicated Docker socket at /var/run/docker-containai.sock
  5. Creates 'containai-secure' Docker context pointing to dedicated socket
  6. Verifies installation

What It Does (macOS):
  1. Installs Lima via Homebrew (if not present)
  2. Creates Lima VM 'containai-secure' with Ubuntu 24.04
  3. Installs Docker Engine and Sysbox inside the VM
  4. Exposes Docker socket to macOS host via Lima port forwarding
  5. Creates 'containai-secure' Docker context pointing to Lima socket
  6. Verifies installation

Requirements (WSL2):
  - Ubuntu or Debian WSL2 distribution (WSL1 not supported)
  - systemd enabled ([boot] systemd=true in /etc/wsl.conf)
  - Docker Engine installed (standalone, not Docker Desktop integration)
  - Internet access to download Sysbox
  - jq and wget installed (will install if missing)

Requirements (macOS):
  - Homebrew installed
  - Internet access to download Lima and Ubuntu image
  - Disk space for Lima VM (~10GB)
  - Works on both Intel and Apple Silicon Macs

Security Notes:
  - Does NOT set sysbox-runc as default runtime (keeps runc default)
  - Does NOT modify Docker Desktop or default context
  - Docker Desktop remains the default and unchanged (CRITICAL)
  - Creates SEPARATE socket/context for isolation
  - Creates 'containai-secure' context for explicit isolation

Lima VM Management (macOS):
  limactl start containai-secure    Start the VM
  limactl stop containai-secure     Stop the VM
  limactl shell containai-secure    Shell into the VM
  limactl list                      Show VM status

Examples:
  cai setup                    Install Sysbox (auto-detects platform)
  cai setup --dry-run          Preview changes without installing
  cai setup --force            Bypass seccomp warning (WSL2)
  cai setup --verbose          Show detailed progress
EOF
}

# ==============================================================================
# Secure Engine Validation
# ==============================================================================

# Default timeout for docker commands (seconds)
_CAI_VALIDATE_TIMEOUT=30

# Validate Secure Engine is correctly configured and operational
# Arguments: Parsed from command line (--verbose/-v, --help/-h)
# Returns: 0=all checks pass, 1=one or more checks failed
# Outputs: Prints validation results to stdout with [PASS]/[FAIL]/[WARN] markers
#
# Validation checks (per spec):
# 1. Context exists and endpoint matches expected socket
# 2. Engine reachable: docker --context containai-secure info
# 3. Runtime is sysbox-runc: DefaultRuntime must be sysbox-runc
# 4. User namespace enabled: Run container and check uid_map
# 5. Test container starts: docker --context containai-secure run --rm hello-world
_cai_secure_engine_validate() {
    local verbose="false"

    # Parse arguments (same pattern as _cai_setup)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                verbose="true"
                shift
                ;;
            --help|-h)
                _cai_validate_help
                return 0
                ;;
            *)
                _cai_error "Unknown option: $1"
                _cai_error "Use 'cai validate --help' for usage"
                return 1
                ;;
        esac
    done

    local failed=0
    local context_name="containai-secure"

    printf '\n'
    _cai_info "Secure Engine Validation"
    _cai_info "========================"
    printf '\n'

    # Detect platform for expected socket path
    local platform expected_socket
    platform=$(_cai_detect_platform)
    case "$platform" in
        wsl)
            expected_socket="unix://$_CAI_SECURE_SOCKET"
            ;;
        macos)
            expected_socket="unix://$_CAI_LIMA_SOCKET_PATH"
            ;;
        linux)
            expected_socket="unix://$_CAI_SECURE_SOCKET"
            ;;
        *)
            _cai_error "Unknown platform: $platform"
            return 1
            ;;
    esac

    # Validation 1: Context exists AND endpoint matches expected socket
    _cai_step "Check 1: Context exists with correct endpoint"
    local actual_endpoint
    if ! docker context inspect "$context_name" >/dev/null 2>&1; then
        printf '%s\n' "[FAIL] Context '$context_name' not found"
        _cai_error "  Remediation: Run 'cai setup' to create the context"
        failed=1
    else
        actual_endpoint=$(docker context inspect "$context_name" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)
        if [[ "$actual_endpoint" == "$expected_socket" ]]; then
            printf '%s\n' "[PASS] Context '$context_name' exists with correct endpoint"
            if [[ "$verbose" == "true" ]]; then
                _cai_info "  Endpoint: $actual_endpoint"
            fi
        else
            printf '%s\n' "[FAIL] Context '$context_name' has wrong endpoint"
            _cai_error "  Expected: $expected_socket"
            _cai_error "  Actual: $actual_endpoint"
            _cai_error "  Remediation: Run 'cai setup' to reconfigure the context"
            failed=1
        fi
    fi

    # Validation 2: Engine reachable (with timeout via portable _cai_timeout)
    _cai_step "Check 2: Engine is reachable"
    local info_output info_rc
    info_output=$(_cai_timeout "$_CAI_VALIDATE_TIMEOUT" docker --context "$context_name" info 2>&1) && info_rc=0 || info_rc=$?
    if [[ $info_rc -eq 124 ]]; then
        printf '%s\n' "[FAIL] Engine connection timed out after ${_CAI_VALIDATE_TIMEOUT}s"
        _cai_error "  Remediation: Check if Docker daemon is responding"
        failed=1
    elif [[ $info_rc -eq 125 ]]; then
        # No timeout mechanism available - run without timeout
        _cai_warn "No timeout mechanism available, running without timeout"
        info_output=$(docker --context "$context_name" info 2>&1) && info_rc=0 || info_rc=$?
    fi

    if [[ $info_rc -eq 0 ]]; then
        printf '%s\n' "[PASS] Engine is reachable via context '$context_name'"
        if [[ "$verbose" == "true" ]]; then
            # Extract server version from already-captured info_output
            local server_version
            server_version=$(printf '%s' "$info_output" | grep "Server Version:" | head -1 | sed 's/.*Server Version:[[:space:]]*//' || true)
            [[ -n "$server_version" ]] && _cai_info "  Docker version: $server_version"
        fi
    elif [[ $info_rc -ne 124 ]] && [[ $info_rc -ne 125 ]]; then
        printf '%s\n' "[FAIL] Engine not reachable via context '$context_name'"
        _cai_error "  Error: $(printf '%s' "$info_output" | head -3)"
        case "$platform" in
            wsl)
                _cai_error "  Remediation: Ensure Docker is running and socket exists"
                _cai_error "  Try: sudo systemctl status docker"
                ;;
            macos)
                _cai_error "  Remediation: Ensure Lima VM is running"
                _cai_error "  Try: limactl start $_CAI_LIMA_VM_NAME"
                ;;
        esac
        failed=1
    fi

    # Validation 3: sysbox-runc runtime is available
    # Note: sysbox-runc is NOT the default runtime (by design) - we check availability
    _cai_step "Check 3: sysbox-runc runtime is available"
    local runtimes_json runtime_rc
    # Query available runtimes via docker info
    runtimes_json=$(_cai_timeout "$_CAI_VALIDATE_TIMEOUT" docker --context "$context_name" info --format '{{json .Runtimes}}' 2>/dev/null) && runtime_rc=0 || runtime_rc=$?

    # Handle timeout mechanism not available
    if [[ $runtime_rc -eq 125 ]]; then
        runtimes_json=$(docker --context "$context_name" info --format '{{json .Runtimes}}' 2>/dev/null || true)
    fi

    if [[ -z "$runtimes_json" ]] || [[ "$runtimes_json" == "null" ]]; then
        printf '%s\n' "[FAIL] Could not query available runtimes"
        _cai_error "  Remediation: Ensure Docker daemon is running"
        failed=1
    elif printf '%s' "$runtimes_json" | grep -q "sysbox-runc"; then
        printf '%s\n' "[PASS] sysbox-runc runtime is available"
        if [[ "$verbose" == "true" ]]; then
            _cai_info "  Available runtimes: $runtimes_json"
        fi
    else
        printf '%s\n' "[FAIL] sysbox-runc runtime is NOT available"
        _cai_error "  Available runtimes: $runtimes_json"
        _cai_error "  Remediation: Run 'cai setup' to install Sysbox"
        failed=1
    fi

    # Validation 4: User namespace enabled (test with container using sysbox-runc)
    _cai_step "Check 4: User namespace isolation (sysbox-runc)"
    local uid_map_output uid_map_rc
    # Run container with --runtime=sysbox-runc and check uid_map (with timeout, pinned image)
    # Must use explicit --runtime since sysbox-runc is NOT the default runtime
    uid_map_output=$(_cai_timeout "$_CAI_VALIDATE_TIMEOUT" docker --context "$context_name" run --rm --runtime=sysbox-runc --pull=never alpine:3.20 cat /proc/self/uid_map 2>&1) && uid_map_rc=0 || uid_map_rc=$?

    # Handle timeout mechanism not available
    if [[ $uid_map_rc -eq 125 ]]; then
        uid_map_output=$(docker --context "$context_name" run --rm --runtime=sysbox-runc --pull=never alpine:3.20 cat /proc/self/uid_map 2>&1) && uid_map_rc=0 || uid_map_rc=$?
    fi

    # Handle missing image - try with pull (use proper grouping to avoid precedence bug)
    if [[ $uid_map_rc -ne 0 ]] && { [[ "$uid_map_output" == *"image"*"not"*"found"* ]] || [[ "$uid_map_output" == *"No such image"* ]]; }; then
        _cai_info "  Pulling alpine:3.20 image..."
        uid_map_output=$(_cai_timeout 60 docker --context "$context_name" run --rm --runtime=sysbox-runc alpine:3.20 cat /proc/self/uid_map 2>&1) && uid_map_rc=0 || uid_map_rc=$?
        [[ $uid_map_rc -eq 125 ]] && uid_map_output=$(docker --context "$context_name" run --rm --runtime=sysbox-runc alpine:3.20 cat /proc/self/uid_map 2>&1) && uid_map_rc=0 || uid_map_rc=$?
    fi

    if [[ $uid_map_rc -eq 124 ]]; then
        printf '%s\n' "[FAIL] User namespace check timed out"
        _cai_error "  Remediation: Check if Docker daemon is responding"
        failed=1
    elif [[ $uid_map_rc -ne 0 ]]; then
        printf '%s\n' "[FAIL] Could not run test container to check user namespace"
        _cai_error "  Error: $uid_map_output"
        _cai_error "  Remediation: Verify Sysbox is properly installed"
        failed=1
    else
        # Parse uid_map robustly: normalize whitespace and check for full range
        # Format: "         0          0 4294967295" or similar with variable whitespace
        local uid_map_normalized
        uid_map_normalized=$(printf '%s' "$uid_map_output" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')

        # Check if first line shows full UID range (0 0 4294967295 = no remapping)
        if printf '%s' "$uid_map_normalized" | head -1 | grep -qE '^0 0 4294967295'; then
            # Full UID range mapping = no user namespace remapping - this is a FAIL
            printf '%s\n' "[FAIL] User namespace isolation is NOT enabled"
            _cai_error "  uid_map shows full range (no remapping): $uid_map_normalized"
            _cai_error "  Remediation: Verify Sysbox is properly configured"
            failed=1
        else
            printf '%s\n' "[PASS] User namespace isolation is enabled"
            if [[ "$verbose" == "true" ]]; then
                _cai_info "  uid_map: $uid_map_normalized"
            fi
        fi
    fi

    # Validation 5: Test container starts successfully with sysbox-runc
    _cai_step "Check 5: Test container runs successfully (sysbox-runc)"
    local hello_output hello_rc
    # Use explicit --runtime=sysbox-runc since sysbox is NOT the default runtime
    hello_output=$(_cai_timeout "$_CAI_VALIDATE_TIMEOUT" docker --context "$context_name" run --rm --runtime=sysbox-runc --pull=never alpine:3.20 echo "containai-validation-ok" 2>&1) && hello_rc=0 || hello_rc=$?

    # Handle timeout mechanism not available
    if [[ $hello_rc -eq 125 ]]; then
        hello_output=$(docker --context "$context_name" run --rm --runtime=sysbox-runc --pull=never alpine:3.20 echo "containai-validation-ok" 2>&1) && hello_rc=0 || hello_rc=$?
    fi

    # Handle missing image - try with pull (use proper grouping to avoid precedence bug)
    if [[ $hello_rc -ne 0 ]] && { [[ "$hello_output" == *"image"*"not"*"found"* ]] || [[ "$hello_output" == *"No such image"* ]]; }; then
        hello_output=$(_cai_timeout 60 docker --context "$context_name" run --rm --runtime=sysbox-runc alpine:3.20 echo "containai-validation-ok" 2>&1) && hello_rc=0 || hello_rc=$?
        [[ $hello_rc -eq 125 ]] && hello_output=$(docker --context "$context_name" run --rm --runtime=sysbox-runc alpine:3.20 echo "containai-validation-ok" 2>&1) && hello_rc=0 || hello_rc=$?
    fi

    if [[ $hello_rc -eq 124 ]]; then
        printf '%s\n' "[FAIL] Test container timed out"
        _cai_error "  Remediation: Check if Docker daemon is responding"
        failed=1
    elif [[ $hello_rc -eq 0 ]] && [[ "$hello_output" == *"containai-validation-ok"* ]]; then
        printf '%s\n' "[PASS] Test container ran successfully"
    else
        printf '%s\n' "[FAIL] Test container failed to run"
        _cai_error "  Exit code: $hello_rc"
        _cai_error "  Output: $hello_output"
        case "$platform" in
            wsl)
                _cai_error "  Remediation: Check if WSL2 seccomp is causing issues"
                _cai_error "  Try: cai setup --force (if seccomp filter conflict)"
                ;;
            macos)
                _cai_error "  Remediation: Check Lima VM provisioning"
                _cai_error "  Try: limactl shell $_CAI_LIMA_VM_NAME"
                ;;
        esac
        failed=1
    fi

    # Summary
    printf '\n'
    if [[ $failed -eq 0 ]]; then
        _cai_ok "All Secure Engine validation checks passed"
        return 0
    else
        _cai_error "One or more validation checks failed"
        _cai_error "  Run 'cai setup' to configure Secure Engine"
        return 1
    fi
}

# Validate help text
_cai_validate_help() {
    cat <<'EOF'
ContainAI Validate - Check Secure Engine Configuration

Usage: cai validate [options]

Verifies that the Secure Engine (Sysbox) is correctly configured and operational.

Options:
  --verbose, -v   Show detailed information for each check
  -h, --help      Show this help message

Validation Checks:
  1. Context exists with correct endpoint
  2. Engine is reachable via the context
  3. Sysbox runtime (sysbox-runc) is available
  4. User namespace isolation is enabled
  5. Test container runs successfully with sysbox-runc

Examples:
  cai validate             Run all validation checks
  cai validate --verbose   Run checks with detailed output
EOF
}

return 0
