#!/usr/bin/env bash
# ==============================================================================
# ContainAI Setup - Secure Engine Provisioning (Linux, WSL2, macOS)
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_setup()                       - Main setup entry point
#   _cai_setup_linux()                 - Native Linux setup (isolated Docker)
#   _cai_setup_wsl2()                  - WSL2-specific setup (isolated Docker)
#   _cai_setup_macos()                 - macOS-specific setup (Lima VM)
#   _cai_test_wsl2_seccomp()           - Test WSL2 seccomp compatibility
#   _cai_show_seccomp_warning()        - Display seccomp warning
#   _cai_install_sysbox_wsl2()         - Install Sysbox on WSL2
#   _cai_install_dockerd_bundle()      - Install ContainAI-managed dockerd bundle
#   _cai_configure_daemon_json()       - Configure Docker daemon.json (legacy)
#   _cai_configure_docker_socket()     - Configure dedicated Docker socket (legacy)
#   _cai_create_containai_context()    - Create containai-docker context (legacy)
#   _cai_verify_sysbox_install()       - Verify Sysbox installation (legacy)
#   _cai_cleanup_legacy_paths()        - Clean up legacy ContainAI paths
#   _cai_cleanup_legacy_lima_vm()      - Clean up legacy Lima VM (after new VM verified)
#   _cai_ensure_isolated_bridge()      - Ensure isolated bridge (cai0) exists
#   _cai_create_isolated_daemon_json() - Create isolated daemon.json
#   _cai_create_isolated_docker_service() - Create isolated systemd service
#   _cai_create_isolated_docker_dirs() - Create isolated Docker directories
#   _cai_start_isolated_docker_service() - Start isolated Docker service
#   _cai_create_isolated_docker_context() - Create containai-docker context
#   _cai_verify_isolated_docker()      - Verify isolated Docker installation
#   _cai_lima_template()               - Generate Lima VM template YAML
#   _cai_lima_install()                - Install Lima via Homebrew
#   _cai_lima_create_vm()              - Create Lima VM with Docker + Sysbox
#   _cai_lima_create_context()         - Create containai-docker context for Lima
#   _cai_lima_verify_install()         - Verify Lima + Sysbox installation
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
#   - Requires lib/platform.sh for platform detection
#   - Requires lib/docker.sh for Docker availability checks
#   - Requires lib/doctor.sh for _cai_check_kernel_for_sysbox
#   - Requires lib/ssh.sh for SSH key setup
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

# NOTE: Docker path constants are defined in lib/docker.sh (single source of truth)
# Use: $_CAI_CONTAINAI_DOCKER_SOCKET, $_CAI_CONTAINAI_DOCKER_CONFIG, etc.

# Systemd drop-in directory for Docker socket override (legacy, for cleanup)
_CAI_DOCKER_DROPIN_DIR="/etc/systemd/system/docker.service.d"

# Legacy paths (for cleanup during upgrade)
_CAI_LEGACY_SOCKET="/var/run/docker-containai.sock"
_CAI_LEGACY_CONTEXT="containai-secure"
_CAI_LEGACY_DROPIN="/etc/systemd/system/docker.service.d/containai-socket.conf"

# Lima VM name for macOS Secure Engine (uses same name as Linux/WSL2 context)
# NOTE: Uses $_CAI_CONTAINAI_DOCKER_CONTEXT from lib/docker.sh with defensive fallback
_CAI_LIMA_VM_NAME="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"

# Lima socket path (uses VM name from above)
_CAI_LIMA_SOCKET_PATH="$HOME/.lima/$_CAI_LIMA_VM_NAME/sock/docker.sock"

# Legacy Lima VM name (for migration from old installs)
_CAI_LEGACY_LIMA_VM_NAME="containai-secure"

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
# WSL2 Mirrored Networking Mode Detection
# ==============================================================================

# Detect if WSL2 is running in mirrored networking mode
# Returns: 0=mirrored mode detected (BLOCKS SETUP), 1=not mirrored (OK), 2=cannot detect (unknown)
# Note: Mirrored networking mode is incompatible with ContainAI's isolated Docker setup.
#       WSL2's init process (PID 1) installs its own restrictive seccomp filters during
#       boot to support mirrored networking. This behavior is tracked in
#       https://github.com/microsoft/WSL/issues/9548 - the pre-existing filters can
#       prevent nested container runtimes from installing their own interceptors,
#       resulting in an EBUSY error code.
_cai_detect_wsl2_mirrored_mode() {
    # Get Windows user profile path via cmd.exe
    local win_userprofile
    win_userprofile=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r') || win_userprofile=""
    [[ -z "$win_userprofile" ]] && return 2  # Can't detect

    # Convert Windows path to WSL path
    local wsl_userprofile
    wsl_userprofile=$(wslpath "$win_userprofile" 2>/dev/null) || wsl_userprofile=""
    [[ -z "$wsl_userprofile" ]] && return 2  # Can't convert

    local wslconfig="${wsl_userprofile}/.wslconfig"
    [[ ! -f "$wslconfig" ]] && return 1  # No config file, default is NAT (OK)

    # Parse for networkingMode=mirrored ONLY under [wsl2] section
    # Must handle variations: networkingMode=mirrored, networkingMode = mirrored, etc.
    # Use awk state machine to only check within [wsl2] section
    # Use IGNORECASE=1 for case-insensitivity (POSIX awk doesn't support /regex/i)
    local in_wsl2_section awk_rc
    in_wsl2_section=$(awk '
        BEGIN { IGNORECASE = 1; in_section = 0 }
        /^\[wsl2\]/ { in_section = 1; next }
        /^\[/ { in_section = 0 }
        in_section && /^[[:space:]]*networkingMode[[:space:]]*=[[:space:]]*mirrored/ { print "yes"; exit }
    ' "$wslconfig" 2>/dev/null) && awk_rc=0 || awk_rc=$?

    # If awk failed, return unknown (2)
    if [[ $awk_rc -ne 0 ]]; then
        return 2  # Cannot parse config
    fi

    if [[ "$in_wsl2_section" == "yes" ]]; then
        return 0  # Mirrored mode detected in [wsl2] section
    fi
    return 1  # Not mirrored
}

# Display mirrored networking mode warning and offer to fix
# Arguments: $1 = dry_run flag ("true" to simulate)
# Returns: 1=user declined or error, 75=WSL restart required (user accepted fix)
# Note: Never returns 0 - always blocks setup when mirrored mode detected
_cai_handle_wsl2_mirrored_mode() {
    local dry_run="${1:-false}"

    # Display clear error message
    printf '%s\n' ""
    printf '%s\n' "+==================================================================+"
    printf '%s\n' "|                       *** ERROR ***                              |"
    printf '%s\n' "+==================================================================+"
    printf '%s\n' "| WSL2 mirrored networking mode detected.                          |"
    printf '%s\n' "|                                                                  |"
    printf '%s\n' "| This is INCOMPATIBLE with ContainAI's isolated Docker setup.     |"
    printf '%s\n' "|                                                                  |"
    printf '%s\n' "| WSL2's mirrored networking mode installs restrictive seccomp     |"
    printf '%s\n' "| filters on PID 1 that prevent Sysbox from installing its own     |"
    printf '%s\n' "| interceptors, causing EBUSY errors.                              |"
    printf '%s\n' "|                                                                  |"
    printf '%s\n' "| Upstream issue: https://github.com/microsoft/WSL/issues/9548     |"
    printf '%s\n' "+==================================================================+"
    printf '%s\n' ""

    # In dry-run mode, just show what would happen
    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would prompt to disable mirrored networking"
        _cai_info "[DRY-RUN] Would modify .wslconfig to set networkingMode=nat"
        _cai_info "[DRY-RUN] Would run: wsl.exe --shutdown"
        return 75
    fi

    # Prompt user for action (use shared helper with CAI_YES support)
    # Default to Y since mirrored mode is a hard blocker and this is the remediation path
    if ! _cai_prompt_confirm "Would you like to disable mirrored networking? This requires WSL to restart." "true"; then
        # User declined or cannot prompt
        _cai_error "Cannot continue setup with mirrored networking mode."
        _cai_error "Please manually edit your .wslconfig file:"
        _cai_error "  1. Open %USERPROFILE%\\.wslconfig in a text editor"
        _cai_error "  2. Change networkingMode=mirrored to networkingMode=nat"
        _cai_error "  3. Run: wsl.exe --shutdown"
        _cai_error "  4. Restart your terminal and re-run: cai setup"
        return 1
    fi

    # User agreed - modify .wslconfig
    # Re-acquire paths with guards (same pattern as detection function)
    local win_userprofile wsl_userprofile wslconfig
    win_userprofile=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r') || win_userprofile=""
    if [[ -z "$win_userprofile" ]]; then
        _cai_error "Failed to get Windows user profile path"
        _cai_error "Please manually edit your .wslconfig file"
        return 1
    fi
    wsl_userprofile=$(wslpath "$win_userprofile" 2>/dev/null) || wsl_userprofile=""
    if [[ -z "$wsl_userprofile" ]]; then
        _cai_error "Failed to convert Windows path to WSL path"
        _cai_error "Please manually edit your .wslconfig file"
        return 1
    fi
    wslconfig="${wsl_userprofile}/.wslconfig"

    if [[ ! -f "$wslconfig" ]]; then
        _cai_error "Cannot find .wslconfig at: $wslconfig"
        return 1
    fi

    _cai_info "Modifying $wslconfig to disable mirrored networking..."

    # Create backup
    cp "$wslconfig" "${wslconfig}.bak" || {
        _cai_error "Failed to create backup of .wslconfig"
        return 1
    }
    _cai_info "Backup created: ${wslconfig}.bak"

    # Modify the file - change networkingMode=mirrored to networkingMode=nat
    # Use sed with case-insensitive matching and whitespace variations
    if sed -i 's/^\([[:space:]]*networkingMode[[:space:]]*=[[:space:]]*\)mirrored/\1nat/i' "$wslconfig" 2>/dev/null; then
        _cai_ok "Updated .wslconfig to use NAT networking"
    else
        _cai_error "Failed to modify .wslconfig"
        _cai_error "Please manually change networkingMode=mirrored to networkingMode=nat"
        return 1
    fi

    _cai_info "Shutting down WSL..."
    wsl.exe --shutdown || {
        _cai_warn "wsl.exe --shutdown may have failed - please restart WSL manually"
    }

    printf '%s\n' ""
    _cai_ok "WSL has been shut down."
    _cai_info "Please restart your terminal and re-run: cai setup"
    printf '%s\n' ""

    # Return special exit code indicating WSL restart required
    return 75
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
    printf '%s\n' "| Sysbox on WSL2 may not work due to seccomp filter conflicts with |"
    printf '%s\n' "| networking set to mirrored mode. Set to nat to avoid conflicts.  |"
    printf '%s\n' "|                                                                  |"
    printf '%s\n' "| Your WSL version (1.1.0+) has a seccomp filter on PID 1 that     |"
    printf '%s\n' "| conflicts with Sysbox's seccomp-notify mechanism.                |"
    printf '%s\n' "|                                                                  |"
    printf '%s\n' "| Docker Sandbox will still work (this is the hard requirement).   |"
    printf '%s\n' "| Sysbox provides additional isolation but is optional.            |"
    printf '%s\n' "|                                                                  |"
    printf '%s\n' "| Options:                                                         |"
    printf '%s\n' "|   1. Proceed anyway: cai setup --force                           |"
    printf '%s\n' "|   2. Downgrade WSL:  wsl --update --web-download --version 1.0.3 |"
    printf '%s\n' "|   3. Skip Sysbox:    Use Docker Sandbox without Sysbox           |"
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

    # Check for ripgrep (rg) used for reliable line matching
    if ! command -v rg >/dev/null 2>&1; then
        missing="${missing}ripgrep "
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

# Ensure jq and ripgrep are available on macOS hosts via Homebrew
# Arguments: $1 = dry_run flag ("true" to simulate)
# Returns: 0=success, 1=failure
_cai_macos_ensure_host_tools() {
    local dry_run="${1:-false}"
    local -a missing_pkgs=()

    if ! command -v jq >/dev/null 2>&1; then
        missing_pkgs+=(jq)
    fi
    if ! command -v rg >/dev/null 2>&1; then
        missing_pkgs+=(ripgrep)
    fi

    if ((${#missing_pkgs[@]} == 0)); then
        _cai_ok "Required host tools available (jq, rg)"
        return 0
    fi

    if ! command -v brew >/dev/null 2>&1; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_warn "[DRY-RUN] Homebrew not found; cannot install: ${missing_pkgs[*]}"
            return 0
        fi
        _cai_error "Homebrew is required to install missing tools: ${missing_pkgs[*]}"
        _cai_error "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would install via brew: ${missing_pkgs[*]}"
        return 0
    fi

    _cai_info "Installing missing host tools: ${missing_pkgs[*]}"
    if ! brew install "${missing_pkgs[@]}"; then
        _cai_error "Failed to install host tools via Homebrew: ${missing_pkgs[*]}"
        return 1
    fi

    _cai_ok "Host tools installed: ${missing_pkgs[*]}"
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
        ubuntu | debian) ;;
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

    # Always check and install required tools (jq needed for daemon.json config)
    # Do this BEFORE checking for Sysbox to ensure jq is available for configure step
    _cai_step "Ensuring required tools are installed"
    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would ensure jq, ripgrep, and wget are installed"
    else
        local missing_pkgs=()
        if ! command -v jq >/dev/null 2>&1; then
            missing_pkgs+=("jq")
        fi
        if ! command -v rg >/dev/null 2>&1; then
            missing_pkgs+=("ripgrep")
        fi
        if ! command -v wget >/dev/null 2>&1; then
            missing_pkgs+=("wget")
        fi
        if [[ ${#missing_pkgs[@]} -gt 0 ]]; then
            _cai_info "Installing required tools: ${missing_pkgs[*]}"
            if ! sudo apt-get update -qq; then
                _cai_error "Failed to run apt-get update"
                return 1
            fi
            if ! sudo apt-get install -y "${missing_pkgs[@]}"; then
                _cai_error "Failed to install required tools: ${missing_pkgs[*]}"
                return 1
            fi
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
        _cai_info "[DRY-RUN] Would run: apt-get install -y jq ripgrep wget"
    else
        if ! sudo apt-get update; then
            _cai_error "Failed to run apt-get update"
            return 1
        fi
        if ! sudo apt-get install -y jq ripgrep wget; then
            _cai_error "Failed to install dependencies (jq, ripgrep, wget)"
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
        trap 'rm -rf "$tmpdir"' EXIT
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
# Docker Bundle Installation
# ==============================================================================

# Install ContainAI-managed dockerd bundle (Linux/WSL2 only)
# Downloads Docker static binaries and installs to /opt/containai/docker/<version>/
# with symlinks from /opt/containai/bin/ for atomic updates.
#
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Note: Docker does NOT provide checksums - trusting HTTPS only
_cai_install_dockerd_bundle() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    # Skip on macOS - uses Lima VM instead
    if _cai_is_macos; then
        if [[ "$verbose" == "true" ]]; then
            _cai_info "Skipping dockerd bundle on macOS (uses Lima VM)"
        fi
        return 0
    fi

    _cai_step "Installing ContainAI-managed Docker bundle"

    # Preflight: Check required tools (wget may not be installed if Sysbox was pre-installed)
    local missing_tools=""
    if ! command -v wget >/dev/null 2>&1; then
        missing_tools="$missing_tools wget"
    fi
    if ! command -v tar >/dev/null 2>&1; then
        missing_tools="$missing_tools tar"
    fi

    if [[ -n "$missing_tools" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_warn "[DRY-RUN] Missing required tools:$missing_tools"
            _cai_info "[DRY-RUN] Would install with: sudo apt-get install -y$missing_tools"
        else
            _cai_info "Installing required tools:$missing_tools"
            if ! sudo apt-get update -qq; then
                _cai_error "Failed to update package list"
                return 1
            fi
            # shellcheck disable=SC2086
            if ! sudo apt-get install -y$missing_tools; then
                _cai_error "Failed to install required tools:$missing_tools"
                _cai_error "  Install manually: sudo apt-get install$missing_tools"
                return 1
            fi
        fi
    fi

    # Determine architecture (Docker uses x86_64/aarch64 naming)
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            # Docker uses x86_64 (not amd64)
            arch="x86_64"
            ;;
        aarch64)
            # Docker uses aarch64 (not arm64)
            arch="aarch64"
            ;;
        *)
            _cai_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Architecture: $arch"
    fi

    # Docker static binaries index URL
    local index_url="https://download.docker.com/linux/static/stable/${arch}/"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would fetch latest version from: $index_url"
        _cai_info "[DRY-RUN] Would download docker-<version>.tgz"
        _cai_info "[DRY-RUN] Would extract to: $_CAI_DOCKERD_BUNDLE_DIR/<version>/"
        _cai_info "[DRY-RUN] Would create symlinks in: $_CAI_DOCKERD_BIN_DIR/"
        _cai_info "[DRY-RUN] Would write version to: $_CAI_DOCKERD_VERSION_FILE"
        _cai_ok "Docker bundle installation (dry-run) complete"
        return 0
    fi

    # Fetch index and parse for latest version
    # Docker files are named: docker-X.Y.Z.tgz
    # We grep for links, extract versions, sort numerically, take the last one
    _cai_step "Resolving latest Docker version"
    local index_html latest_version

    # Use wget with timeout (wget is already ensured for Sysbox install)
    if ! index_html=$(_cai_timeout 30 wget -qO- "$index_url" 2>/dev/null); then
        _cai_error "Failed to fetch Docker index from: $index_url"
        _cai_error "  Check network connectivity"
        return 1
    fi

    # Parse HTML for docker-X.Y.Z.tgz links and extract latest version
    # Pattern: href="docker-X.Y.Z.tgz" - we extract X.Y.Z
    # Exclude rootless-extras packages
    latest_version=$(printf '%s' "$index_html" | \
        grep -oE 'href="docker-[0-9]+\.[0-9]+\.[0-9]+\.tgz"' | \
        grep -v rootless | \
        sed 's/href="docker-//; s/\.tgz"//' | \
        sort -t. -k1,1n -k2,2n -k3,3n | \
        tail -1)

    if [[ -z "$latest_version" ]]; then
        _cai_error "Could not determine latest Docker version from index"
        return 1
    fi

    _cai_info "Latest Docker version: $latest_version"

    # Check if already installed at this version
    if _cai_dockerd_bundle_installed; then
        local installed_version
        installed_version=$(_cai_dockerd_bundle_version) || installed_version=""
        if [[ "$installed_version" == "$latest_version" ]]; then
            _cai_info "Docker bundle already at version $latest_version"
            _cai_ok "Docker bundle is current"
            return 0
        fi
        _cai_info "Upgrading from $installed_version to $latest_version"
    fi

    # Download and install in subshell to contain cleanup trap
    local download_url="https://download.docker.com/linux/static/stable/${arch}/docker-${latest_version}.tgz"
    local install_rc

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Download URL: $download_url"
    fi

    (
        set -e
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT

        echo "[STEP] Downloading Docker $latest_version"
        # Use timeouts per spec: --connect-timeout=5 --timeout=120
        if ! wget -q --show-progress --connect-timeout=5 --timeout=120 -O "$tmpdir/docker.tgz" "$download_url"; then
            echo "[ERROR] Failed to download Docker bundle" >&2
            exit 1
        fi

        echo "[STEP] Extracting Docker bundle"
        # Docker tarball extracts to docker/ subdirectory
        if ! tar -xzf "$tmpdir/docker.tgz" -C "$tmpdir"; then
            echo "[ERROR] Failed to extract Docker bundle" >&2
            exit 1
        fi

        # Verify extraction produced expected files
        if [[ ! -f "$tmpdir/docker/dockerd" ]]; then
            echo "[ERROR] Extracted archive missing dockerd binary" >&2
            exit 1
        fi

        echo "[STEP] Installing to $_CAI_DOCKERD_BUNDLE_DIR/$latest_version/"

        # Create target directories
        sudo mkdir -p "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version"
        sudo mkdir -p "$_CAI_DOCKERD_BIN_DIR"

        # Move binaries from docker/ subdir to versioned directory
        sudo mv "$tmpdir/docker/"* "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version/"

        # SECURITY: Set proper ownership and permissions
        # Binaries are moved with user ownership from temp dir; dockerd runs as root
        # so we must ensure binaries are root-owned and not user-writable
        echo "[STEP] Setting secure ownership and permissions"
        sudo chown -R root:root "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version"
        sudo chmod -R u+rx,go+rx,go-w "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version"

        echo "[STEP] Validating required binaries"

        # Required binaries must all be present - fail if any are missing
        # Uses $_CAI_DOCKERD_BUNDLE_REQUIRED_BINARIES from docker.sh
        local bin missing_binaries=""
        for bin in $_CAI_DOCKERD_BUNDLE_REQUIRED_BINARIES; do
            if [[ ! -f "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version/$bin" ]]; then
                missing_binaries="$missing_binaries $bin"
            fi
        done

        if [[ -n "$missing_binaries" ]]; then
            echo "[ERROR] Docker bundle missing required binaries:$missing_binaries" >&2
            exit 1
        fi

        echo "[STEP] Creating symlinks in $_CAI_DOCKERD_BIN_DIR/"

        # Create symlinks for all bundle binaries using relative paths
        # Use ln -sfn for atomic symlink replacement
        # All required binaries from $_CAI_DOCKERD_BUNDLE_REQUIRED_BINARIES
        for bin in $_CAI_DOCKERD_BUNDLE_REQUIRED_BINARIES; do
            sudo ln -sfn "../docker/$latest_version/$bin" "$_CAI_DOCKERD_BIN_DIR/$bin"
        done

        # Write version file atomically (write to temp, then mv)
        echo "[STEP] Writing version to $_CAI_DOCKERD_VERSION_FILE"
        local version_tmp="${_CAI_DOCKERD_VERSION_FILE}.tmp"
        printf '%s' "$latest_version" | sudo tee "$version_tmp" >/dev/null
        sudo mv -f "$version_tmp" "$_CAI_DOCKERD_VERSION_FILE"

        exit 0
    ) && install_rc=0 || install_rc=$?

    if [[ $install_rc -ne 0 ]]; then
        return 1
    fi

    # Verify installation
    if ! _cai_dockerd_bundle_installed; then
        _cai_error "Bundle installation verification failed"
        return 1
    fi

    _cai_ok "Docker bundle $latest_version installed"
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
    local daemon_json="$1"  # Required - caller must specify path
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
        local backup_file
        backup_file="${daemon_json}.bak.$(date +%Y%m%d-%H%M%S)"
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

# ==============================================================================
# Legacy Cleanup Functions (shared between WSL2 and Linux)
# ==============================================================================

# Clean up legacy paths from previous ContainAI installations
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success (cleanup complete or nothing to clean)
# Note: This supports upgrades from earlier ContainAI versions
_cai_cleanup_legacy_paths() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local cleaned_any=false

    _cai_step "Checking for legacy ContainAI paths"

    # Clean up old socket (use -e to catch any file type, not just sockets)
    if [[ -e "$_CAI_LEGACY_SOCKET" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_info "[DRY-RUN] Would remove legacy socket: $_CAI_LEGACY_SOCKET"
        else
            _cai_info "Removing legacy socket: $_CAI_LEGACY_SOCKET"
            if sudo rm -f "$_CAI_LEGACY_SOCKET"; then
                cleaned_any=true
            else
                _cai_warn "Failed to remove legacy socket (continuing anyway)"
            fi
        fi
    elif [[ "$verbose" == "true" ]]; then
        _cai_info "No legacy socket found at $_CAI_LEGACY_SOCKET"
    fi

    # Clean up old context (use -f to avoid prompts in non-interactive mode)
    # Guard with command -v docker to avoid noisy errors if Docker isn't installed
    # NOTE: On macOS, defer context removal to _cai_cleanup_legacy_lima_vm() to ensure
    #       users keep a working context if the new VM setup fails midway.
    if command -v docker >/dev/null 2>&1 && docker context inspect "$_CAI_LEGACY_CONTEXT" >/dev/null 2>&1; then
        if _cai_is_macos; then
            # On macOS, legacy context cleanup is deferred to after VM verification
            [[ "$verbose" == "true" ]] && _cai_info "Legacy context cleanup deferred until after VM verification (macOS)"
        elif [[ "$dry_run" == "true" ]]; then
            _cai_info "[DRY-RUN] Would remove legacy context: $_CAI_LEGACY_CONTEXT"
        else
            _cai_info "Removing legacy context: $_CAI_LEGACY_CONTEXT"
            # Switch to default context first if legacy context is active
            local current_context
            current_context=$(docker context show 2>/dev/null || true)
            if [[ "$current_context" == "$_CAI_LEGACY_CONTEXT" ]]; then
                docker context use default >/dev/null 2>&1 || true
            fi
            if docker context rm -f "$_CAI_LEGACY_CONTEXT" >/dev/null 2>&1; then
                cleaned_any=true
            else
                _cai_warn "Failed to remove legacy context (continuing anyway)"
            fi
        fi
    elif [[ "$verbose" == "true" ]]; then
        _cai_info "No legacy context found: $_CAI_LEGACY_CONTEXT"
    fi

    # Clean up old drop-in
    if [[ -f "$_CAI_LEGACY_DROPIN" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_info "[DRY-RUN] Would remove legacy drop-in: $_CAI_LEGACY_DROPIN"
            _cai_info "[DRY-RUN] Would run: systemctl daemon-reload"
        else
            _cai_info "Removing legacy drop-in: $_CAI_LEGACY_DROPIN"
            if sudo rm -f "$_CAI_LEGACY_DROPIN"; then
                cleaned_any=true
                # Reload systemd after removing drop-in
                sudo systemctl daemon-reload || true
            else
                _cai_warn "Failed to remove legacy drop-in (continuing anyway)"
            fi
        fi
    elif [[ "$verbose" == "true" ]]; then
        _cai_info "No legacy drop-in found at $_CAI_LEGACY_DROPIN"
    fi

    # Note: Lima VM legacy cleanup is handled separately by _cai_cleanup_legacy_lima_vm()
    # to ensure we only delete the old VM after the new VM is verified working.
    # This prevents leaving users without a working VM if setup fails midway.

    if [[ "$cleaned_any" == "true" ]] || [[ "$dry_run" == "true" ]]; then
        _cai_ok "Legacy path cleanup complete"
    else
        _cai_info "No legacy paths to clean up"
    fi

    return 0
}

# Clean up legacy Lima VM and context (containai-secure -> containai-docker rename)
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
#            $3 = force flag ("true" to auto-delete without confirmation)
# Returns: 0=success (cleanup complete or nothing to clean)
# Note: This is called AFTER the new Lima VM is verified working, to avoid
#       leaving users without a working VM if setup fails midway.
#       Only runs on macOS - Lima is macOS-specific for ContainAI.
#       Also cleans up the legacy Docker context (deferred from _cai_cleanup_legacy_paths).
#       Without --force, prints manual cleanup instructions instead of auto-deleting VM.
_cai_cleanup_legacy_lima_vm() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local force="${3:-false}"
    local has_legacy_vm=false
    local has_legacy_context=false

    # Skip if not macOS
    if ! _cai_is_macos; then
        return 0
    fi

    # Check what legacy resources exist
    if command -v limactl >/dev/null 2>&1 && _cai_lima_vm_exists "$_CAI_LEGACY_LIMA_VM_NAME" 2>/dev/null; then
        has_legacy_vm=true
    fi
    if command -v docker >/dev/null 2>&1 && docker context inspect "$_CAI_LEGACY_CONTEXT" >/dev/null 2>&1; then
        has_legacy_context=true
    fi

    # Nothing to clean up
    if [[ "$has_legacy_vm" == "false" ]] && [[ "$has_legacy_context" == "false" ]]; then
        [[ "$verbose" == "true" ]] && _cai_info "No legacy Lima VM or context to clean up"
        return 0
    fi

    _cai_step "Legacy macOS resources detected"

    if [[ "$dry_run" == "true" ]]; then
        [[ "$has_legacy_vm" == "true" ]] && _cai_info "[DRY-RUN] Would offer to delete legacy Lima VM: $_CAI_LEGACY_LIMA_VM_NAME"
        [[ "$has_legacy_context" == "true" ]] && _cai_info "[DRY-RUN] Would remove legacy context: $_CAI_LEGACY_CONTEXT"
        _cai_info "[DRY-RUN] (Safe to delete: new VM '$_CAI_LIMA_VM_NAME' is verified working)"
        return 0
    fi

    _cai_info "New VM '$_CAI_LIMA_VM_NAME' is working"

    # Clean up legacy context first (doesn't depend on VM, safe to auto-remove)
    if [[ "$has_legacy_context" == "true" ]]; then
        _cai_info "Removing legacy context: $_CAI_LEGACY_CONTEXT"
        # Switch to default context first if legacy context is active
        local current_context
        current_context=$(docker context show 2>/dev/null || true)
        if [[ "$current_context" == "$_CAI_LEGACY_CONTEXT" ]]; then
            docker context use default >/dev/null 2>&1 || true
        fi
        if docker context rm -f "$_CAI_LEGACY_CONTEXT" >/dev/null 2>&1; then
            _cai_ok "Legacy context removed"
        else
            _cai_warn "Failed to remove legacy context (not critical)"
        fi
    fi

    # Clean up legacy VM - requires --force or manual action
    if [[ "$has_legacy_vm" == "true" ]]; then
        if [[ "$force" == "true" ]]; then
            _cai_info "Removing legacy Lima VM: $_CAI_LEGACY_LIMA_VM_NAME (--force)"
            _cai_info "  (VM was ContainAI-dedicated with no user data)"
            # Stop the VM first if running
            limactl stop "$_CAI_LEGACY_LIMA_VM_NAME" 2>/dev/null || true
            if limactl delete -f "$_CAI_LEGACY_LIMA_VM_NAME" 2>/dev/null; then
                _cai_ok "Legacy Lima VM deleted"
            else
                _cai_warn "Failed to delete legacy Lima VM (not critical)"
            fi
        else
            # Without --force, offer manual cleanup instructions
            _cai_info "Legacy Lima VM '$_CAI_LEGACY_LIMA_VM_NAME' still exists"
            _cai_info "  This VM is no longer needed (new VM '$_CAI_LIMA_VM_NAME' is working)"
            _cai_info "  To remove it manually:"
            _cai_info "    limactl stop $_CAI_LEGACY_LIMA_VM_NAME"
            _cai_info "    limactl delete $_CAI_LEGACY_LIMA_VM_NAME"
            _cai_info "  Or run: cai setup --force (to auto-delete legacy resources)"
        fi
    fi

    return 0
}

# ==============================================================================
# Isolated Docker Daemon Functions
# ==============================================================================

# Create daemon.json for isolated ContainAI Docker instance
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Note: This creates a complete isolated daemon.json with all paths specified
#       Unlike _cai_configure_daemon_json which only adds sysbox runtime
_cai_create_isolated_daemon_json() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_step "Creating isolated daemon.json: $_CAI_CONTAINAI_DOCKER_CONFIG"

    # Determine sysbox-runc path dynamically
    local sysbox_path
    sysbox_path=$(command -v sysbox-runc 2>/dev/null || true)
    if [[ -z "$sysbox_path" ]]; then
        # Fall back to standard path if not in PATH yet
        sysbox_path="/usr/bin/sysbox-runc"
        _cai_warn "sysbox-runc not in PATH, using default: $sysbox_path"
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Found sysbox-runc at: $sysbox_path"
    fi

    # Build isolated daemon configuration
    # PITFALL: Do NOT set "hosts" in both daemon.json AND use -H flag in service
    # We set hosts here, so service uses --config-file only
    # Note: "bridge" and "bip" are mutually exclusive in dockerd config
    # The bridge subnet is configured in _cai_ensure_isolated_bridge()
    local config
    config=$(cat <<EOF
{
  "runtimes": {
    "sysbox-runc": {
      "path": "$sysbox_path"
    }
  },
  "default-runtime": "sysbox-runc",
  "hosts": ["unix://$_CAI_CONTAINAI_DOCKER_SOCKET"],
  "data-root": "$_CAI_CONTAINAI_DOCKER_DATA",
  "exec-root": "$_CAI_CONTAINAI_DOCKER_EXEC",
  "pidfile": "$_CAI_CONTAINAI_DOCKER_PID",
  "bridge": "$_CAI_CONTAINAI_DOCKER_BRIDGE"
}
EOF
    )

    if [[ "$verbose" == "true" ]]; then
        _cai_info "daemon.json content:"
        printf '%s\n' "$config"
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would create directory: $(dirname "$_CAI_CONTAINAI_DOCKER_CONFIG")"
        _cai_info "[DRY-RUN] Would write: $_CAI_CONTAINAI_DOCKER_CONFIG"
        return 0
    fi

    # Create config directory
    if ! sudo mkdir -p "$(dirname "$_CAI_CONTAINAI_DOCKER_CONFIG")"; then
        _cai_error "Failed to create config directory"
        return 1
    fi

    # Write daemon.json
    if ! printf '%s\n' "$config" | sudo tee "$_CAI_CONTAINAI_DOCKER_CONFIG" >/dev/null; then
        _cai_error "Failed to write daemon.json"
        return 1
    fi

    _cai_ok "Isolated daemon.json created"
    return 0
}

# Create systemd service for isolated ContainAI Docker
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Note: Creates a separate service, NOT a drop-in to docker.service
#       Uses _cai_dockerd_unit_content() from docker.sh for single source of truth
_cai_create_isolated_docker_service() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_step "Creating isolated Docker service: $_CAI_CONTAINAI_DOCKER_SERVICE"

    # Use shared unit content from docker.sh
    local service_content
    service_content=$(_cai_dockerd_unit_content)

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Service file content:"
        printf '%s\n' "$service_content"
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would write: $_CAI_CONTAINAI_DOCKER_UNIT"
        _cai_info "[DRY-RUN] Would run: systemctl daemon-reload"
        return 0
    fi

    # Write service file
    if ! printf '%s\n' "$service_content" | sudo tee "$_CAI_CONTAINAI_DOCKER_UNIT" >/dev/null; then
        _cai_error "Failed to write service file"
        return 1
    fi

    # Reload systemd
    if ! sudo systemctl daemon-reload; then
        _cai_error "Failed to reload systemd daemon"
        return 1
    fi

    _cai_ok "Isolated Docker service created"
    return 0
}

# Create data directories for isolated Docker
# Arguments: $1 = dry_run flag ("true" to simulate)
# Returns: 0=success, 1=failure
_cai_create_isolated_docker_dirs() {
    local dry_run="${1:-false}"

    _cai_step "Creating isolated Docker directories"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would create: $_CAI_CONTAINAI_DOCKER_DATA"
        _cai_info "[DRY-RUN] Would create: $_CAI_CONTAINAI_DOCKER_EXEC"
        return 0
    fi

    if ! sudo mkdir -p "$_CAI_CONTAINAI_DOCKER_DATA"; then
        _cai_error "Failed to create data directory: $_CAI_CONTAINAI_DOCKER_DATA"
        return 1
    fi

    if ! sudo mkdir -p "$_CAI_CONTAINAI_DOCKER_EXEC"; then
        _cai_error "Failed to create exec-root directory: $_CAI_CONTAINAI_DOCKER_EXEC"
        return 1
    fi

    _cai_ok "Isolated Docker directories created"
    return 0
}

# Ensure isolated Docker bridge exists with expected subnet
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_ensure_isolated_bridge() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local bridge="$_CAI_CONTAINAI_DOCKER_BRIDGE"
    local bridge_addr="172.30.0.1/16"

    _cai_step "Ensuring isolated Docker bridge: $bridge"

    if ! command -v ip >/dev/null 2>&1; then
        _cai_warn "ip command not found; cannot configure $bridge"
        _cai_warn "  Install iproute2 and re-run setup to ensure isolated subnet"
        return 0
    fi

    local bridge_exists="false"
    if ip link show "$bridge" >/dev/null 2>&1; then
        bridge_exists="true"
    fi

    if [[ "$bridge_exists" == "false" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_info "[DRY-RUN] Would create bridge: $bridge"
        else
            if ! sudo ip link add name "$bridge" type bridge; then
                _cai_error "Failed to create bridge: $bridge"
                return 1
            fi
            bridge_exists="true"
        fi
    else
        if [[ "$verbose" == "true" ]]; then
            _cai_info "Bridge $bridge already exists"
        fi
    fi

    if [[ "$dry_run" == "true" && "$bridge_exists" == "false" ]]; then
        _cai_info "[DRY-RUN] Would assign $bridge_addr to $bridge"
        _cai_info "[DRY-RUN] Would bring up bridge: $bridge"
        return 0
    fi

    if ip -4 addr show dev "$bridge" | grep -q "$bridge_addr"; then
        if [[ "$verbose" == "true" ]]; then
            _cai_info "Bridge $bridge already has address $bridge_addr"
        fi
    else
        if ip -4 addr show dev "$bridge" | grep -q "inet "; then
            _cai_warn "Bridge $bridge has an IPv4 address not matching $bridge_addr"
            _cai_warn "  Leaving existing address as-is"
        else
            if [[ "$dry_run" == "true" ]]; then
                _cai_info "[DRY-RUN] Would assign $bridge_addr to $bridge"
            else
                if ! sudo ip addr add "$bridge_addr" dev "$bridge"; then
                    _cai_error "Failed to assign $bridge_addr to $bridge"
                    return 1
                fi
            fi
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would bring up bridge: $bridge"
    else
        if ! sudo ip link set "$bridge" up; then
            _cai_error "Failed to bring up bridge: $bridge"
            return 1
        fi
    fi

    _cai_ok "Isolated bridge ready: $bridge"
    return 0
}

# Start and enable isolated Docker service
# Arguments: $1 = dry_run flag ("true" to simulate)
# Returns: 0=success, 1=failure
_cai_start_isolated_docker_service() {
    local dry_run="${1:-false}"

    _cai_step "Starting isolated Docker service: $_CAI_CONTAINAI_DOCKER_SERVICE"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would enable and start $_CAI_CONTAINAI_DOCKER_SERVICE"
        _cai_info "[DRY-RUN] Would wait for socket: $_CAI_CONTAINAI_DOCKER_SOCKET"
        return 0
    fi

    # Enable service for auto-start
    if ! sudo systemctl enable "$_CAI_CONTAINAI_DOCKER_SERVICE" 2>/dev/null; then
        _cai_warn "Failed to enable service (may already be enabled)"
    fi

    # Start or restart service
    if sudo systemctl is-active --quiet "$_CAI_CONTAINAI_DOCKER_SERVICE" 2>/dev/null; then
        _cai_info "Service already running, restarting..."
        if ! sudo systemctl restart "$_CAI_CONTAINAI_DOCKER_SERVICE"; then
            _cai_error "Failed to restart $_CAI_CONTAINAI_DOCKER_SERVICE"
            _cai_error "  Check: sudo systemctl status $_CAI_CONTAINAI_DOCKER_SERVICE"
            return 1
        fi
    else
        if ! sudo systemctl start "$_CAI_CONTAINAI_DOCKER_SERVICE"; then
            _cai_error "Failed to start $_CAI_CONTAINAI_DOCKER_SERVICE"
            _cai_error "  Check: sudo systemctl status $_CAI_CONTAINAI_DOCKER_SERVICE"
            return 1
        fi
    fi

    # Wait for socket to appear
    local wait_count=0
    local max_wait=30
    _cai_step "Waiting for socket: $_CAI_CONTAINAI_DOCKER_SOCKET"
    while [[ ! -S "$_CAI_CONTAINAI_DOCKER_SOCKET" ]]; do
        sleep 1
        wait_count=$((wait_count + 1))
        if [[ $wait_count -ge $max_wait ]]; then
            _cai_error "Socket did not appear after ${max_wait}s: $_CAI_CONTAINAI_DOCKER_SOCKET"
            _cai_error "  Check: sudo systemctl status $_CAI_CONTAINAI_DOCKER_SERVICE"
            return 1
        fi
    done

    # Verify daemon is accessible
    if ! DOCKER_HOST="unix://$_CAI_CONTAINAI_DOCKER_SOCKET" docker info >/dev/null 2>&1; then
        _cai_error "Docker daemon not accessible via socket: $_CAI_CONTAINAI_DOCKER_SOCKET"
        return 1
    fi

    _cai_ok "Isolated Docker service started and socket ready"
    return 0
}

# Create Docker context for isolated ContainAI Docker
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Note: Creates context with name from $_CAI_CONTAINAI_DOCKER_CONTEXT
_cai_create_isolated_docker_context() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_step "Creating Docker context: $_CAI_CONTAINAI_DOCKER_CONTEXT"

    local expected_host
    expected_host=$(_cai_expected_docker_host)

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Expected endpoint: $expected_host"
    fi

    # Check if context already exists
    if docker context inspect "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
        local existing_host
        existing_host=$(docker context inspect "$_CAI_CONTAINAI_DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)

        if [[ "$existing_host" == "$expected_host" ]]; then
            _cai_info "Context '$_CAI_CONTAINAI_DOCKER_CONTEXT' already exists with correct endpoint"
            return 0
        else
            _cai_warn "Context '$_CAI_CONTAINAI_DOCKER_CONTEXT' exists but points to: $existing_host"
            _cai_warn "  Expected: $expected_host"

            if [[ "$dry_run" == "true" ]]; then
                _cai_info "[DRY-RUN] Would remove and recreate context"
            else
                _cai_step "Removing misconfigured context"
                # Switch away if this context is currently active
                local current_context
                current_context=$(docker context show 2>/dev/null || true)
                if [[ "$current_context" == "$_CAI_CONTAINAI_DOCKER_CONTEXT" ]]; then
                    docker context use default >/dev/null 2>&1 || true
                fi
                if ! docker context rm -f "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
                    _cai_error "Failed to remove existing context"
                    return 1
                fi
            fi
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: docker context create $_CAI_CONTAINAI_DOCKER_CONTEXT --docker host=$expected_host"
    else
        if ! docker context create "$_CAI_CONTAINAI_DOCKER_CONTEXT" --docker "host=$expected_host"; then
            _cai_error "Failed to create Docker context '$_CAI_CONTAINAI_DOCKER_CONTEXT'"
            return 1
        fi
    fi

    _cai_ok "Docker context '$_CAI_CONTAINAI_DOCKER_CONTEXT' created"
    return 0
}

# Verify isolated Docker installation
# Arguments: $1 = dry_run flag ("true" to skip actual verification)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_verify_isolated_docker() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_step "Verifying isolated Docker installation"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would verify sysbox-runc is default runtime"
        _cai_info "[DRY-RUN] Would verify Docker context: $_CAI_CONTAINAI_DOCKER_CONTEXT"
        _cai_info "[DRY-RUN] Would run test container"
        return 0
    fi

    # Check docker info via the context
    local docker_info
    docker_info=$(docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" info 2>&1) || {
        _cai_error "Cannot connect to isolated Docker daemon"
        return 1
    }

    # Check sysbox-runc is available
    if ! printf '%s' "$docker_info" | grep -q "sysbox-runc"; then
        _cai_error "sysbox-runc not found in docker info"
        return 1
    fi

    # Check sysbox-runc is the default runtime
    local default_runtime
    default_runtime=$(docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" info --format '{{.DefaultRuntime}}' 2>/dev/null || true)
    if [[ "$default_runtime" != "sysbox-runc" ]]; then
        _cai_error "Default runtime is not sysbox-runc (got: $default_runtime)"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Default runtime: $default_runtime"
    fi

    # Run test container
    _cai_step "Testing with minimal container"
    local test_output test_rc
    test_output=$(docker --context "$_CAI_CONTAINAI_DOCKER_CONTEXT" run --rm alpine echo "containai-docker-test-ok" 2>&1) && test_rc=0 || test_rc=$?

    if [[ $test_rc -ne 0 ]]; then
        _cai_warn "Test container failed: $test_output"
        _cai_warn "This may be expected - sysbox may still work for real containers"
    elif [[ "$test_output" == *"containai-docker-test-ok"* ]]; then
        _cai_ok "Test container succeeded with sysbox-runc default runtime"
    fi

    _cai_ok "Isolated Docker installation verified"
    return 0
}

# Configure dedicated Docker socket for containai-docker context (legacy)
# Arguments: $1 = socket path
#            $2 = dry_run flag ("true" to simulate)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Note: Creates systemd drop-in to add additional socket listener
_cai_configure_docker_socket() {
    local socket_path="$1"  # Required - caller must specify path
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

            dropin_content=$(
                cat <<EOF
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
        dropin_content=$(
            cat <<EOF
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
    local socket_path="$1"  # Required - caller must specify path
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

# Create containai-docker Docker context (legacy function - kept for API compatibility)
# Arguments: $1 = socket path
#            $2 = dry_run flag ("true" to simulate)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
# Note: This context points to dedicated Docker socket, NOT the default socket
_cai_create_containai_context() {
    local socket_path="$1"  # Required - caller must specify path
    local dry_run="${2:-false}"
    local verbose="${3:-false}"
    local context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"

    _cai_step "Creating $context_name Docker context"

    local expected_host="unix://$socket_path"

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Expected socket: $expected_host"
    fi

    # Check if context already exists
    if docker context inspect "$context_name" >/dev/null 2>&1; then
        # Verify it points to the expected socket
        local existing_host
        existing_host=$(docker context inspect "$context_name" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)

        if [[ "$existing_host" == "$expected_host" ]]; then
            _cai_info "Context '$context_name' already exists with correct endpoint"
            return 0
        else
            _cai_warn "Context '$context_name' exists but points to: $existing_host"
            _cai_warn "  Expected: $expected_host"

            if [[ "$dry_run" == "true" ]]; then
                _cai_info "[DRY-RUN] Would remove and recreate context"
            else
                _cai_step "Removing misconfigured context"
                if ! docker context rm "$context_name" >/dev/null 2>&1; then
                    _cai_error "Failed to remove existing context"
                    return 1
                fi
            fi
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: docker context create $context_name --docker host=$expected_host"
    else
        if ! docker context create "$context_name" --docker "host=$expected_host"; then
            _cai_error "Failed to create Docker context '$context_name'"
            return 1
        fi
    fi

    _cai_ok "Docker context '$context_name' created"
    return 0
}

# ==============================================================================
# Installation Verification
# ==============================================================================

# Verify Sysbox installation (legacy function - kept for API compatibility)
# Arguments: $1 = socket path for verification
#            $2 = dry_run flag ("true" to skip actual verification)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_verify_sysbox_install() {
    local socket_path="$1"  # Required - caller must specify path
    local dry_run="${2:-false}"
    local verbose="${3:-false}"
    local context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"

    _cai_step "Verifying Sysbox installation"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would verify sysbox-runc and sysbox-mgr"
        _cai_info "[DRY-RUN] Would verify Docker runtime configuration via socket: $socket_path"
        _cai_info "[DRY-RUN] Would verify $context_name context"
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

    # Check containai-docker context
    if ! docker context inspect "$context_name" >/dev/null 2>&1; then
        _cai_error "$context_name context not found"
        return 1
    fi

    # Verify sysbox-runc works by running a minimal container via the context
    _cai_step "Testing sysbox-runc with minimal container"
    local test_output test_rc test_passed=false
    test_output=$(docker --context "$context_name" run --rm --runtime=sysbox-runc alpine echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?

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
# WSL2 Windows Integration (TLS/TCP)
# ==============================================================================

# Find a Windows executable from WSL and return its WSL path
# Arguments: $1 = exe name (e.g., "npiperelay.exe")
# Returns: 0=found (prints WSL path), 1=not found
_cai_wsl_find_windows_exe() {
    local exe_name="$1"
    local win_path=""

    win_path=$(cmd.exe /c "where $exe_name" 2>/dev/null | head -1 | tr -d '\r') || win_path=""
    if [[ -z "$win_path" ]]; then
        return 1
    fi

    wslpath -u "$win_path" 2>/dev/null || return 1
}

# Configure Docker-over-SSH integration for containai-docker on WSL2
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success (or skipped), 1=failure
_cai_setup_wsl2_windows_npipe_bridge() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_step "Configuring Docker-over-SSH (containai-docker)"

    local host_alias="$_CAI_CONTAINAI_DOCKER_SSH_HOST"
    local legacy_alias="containai-docker-host"
    local ssh_port="${CAI_WSL_SSH_PORT:-$_CAI_CONTAINAI_DOCKER_SSH_PORT_DEFAULT}"
    local user_name
    user_name=$(id -un)
    local key_name="containai-docker-daemon"
    local wsl_key="$HOME/.ssh/$key_name"
    local wsl_key_pub="$HOME/.ssh/$key_name.pub"
    local wsl_ssh_config="$HOME/.ssh/config"
    local wsl_known_hosts="$HOME/.ssh/known_hosts"

    local win_userprofile=""
    local win_username=""
    if pushd /mnt/c >/dev/null 2>&1; then
        win_userprofile=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r') || win_userprofile=""
        win_username=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r') || win_username=""
        popd >/dev/null 2>&1 || true
    else
        win_userprofile=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r') || win_userprofile=""
        win_username=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r') || win_username=""
    fi
    if [[ -z "$win_userprofile" ]]; then
        _cai_warn "Could not determine Windows user profile; SSH integration may be incomplete"
    fi

    local win_ssh_dir=""
    local win_ssh_config=""
    local win_known_hosts=""
    local win_key=""
    local win_key_pub=""
    if [[ -n "$win_userprofile" ]]; then
        win_ssh_dir=$(wslpath -u "${win_userprofile}\\.ssh" 2>/dev/null || true)
        win_ssh_config="${win_ssh_dir}/config"
        win_known_hosts="${win_ssh_dir}/known_hosts"
        win_key="${win_ssh_dir}/${key_name}"
        win_key_pub="${win_key}.pub"
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "SSH host alias: $host_alias"
        _cai_info "SSH port: $ssh_port"
        _cai_info "SSH user: $user_name"
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would disable containai-npipe-bridge.service if present"
        _cai_info "[DRY-RUN] Would configure sshd for key-only auth on port $ssh_port"
        _cai_info "[DRY-RUN] Would create dedicated SSH key: $wsl_key"
        _cai_info "[DRY-RUN] Would add host entry: $host_alias"
        _cai_info "[DRY-RUN] Would update docker contexts to: $(_cai_expected_docker_host)"
        return 0
    fi

    # Disable old TCP bridge service if it exists
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^containai-npipe-bridge.service"; then
            sudo systemctl disable --now containai-npipe-bridge.service >/dev/null 2>&1 || _cai_warn "Failed to disable containai-npipe-bridge.service"
            sudo rm -f /usr/local/bin/containai-npipe-bridge /etc/systemd/system/containai-npipe-bridge.service >/dev/null 2>&1 || true
            sudo systemctl daemon-reload >/dev/null 2>&1 || true
        fi
    fi

    # Harden sshd configuration for key-only auth on the dedicated port
    local sshd_snippet="/etc/ssh/sshd_config.d/containai.conf"
    local sshd_content=""
    sshd_content=$(cat <<EOF
Port $ssh_port
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
EOF
)
    if ! printf '%s\n' "$sshd_content" | sudo tee "$sshd_snippet" >/dev/null; then
        _cai_error "Failed to write sshd hardening config: $sshd_snippet"
        return 1
    fi
    sudo systemctl restart ssh >/dev/null 2>&1 || _cai_warn "Failed to restart ssh.service"

    # Ensure SSH directories exist
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh" 2>/dev/null || true
    touch "$wsl_ssh_config" "$wsl_known_hosts"
    chmod 600 "$wsl_ssh_config" "$wsl_known_hosts" 2>/dev/null || true
    if [[ -n "$win_ssh_dir" ]]; then
        mkdir -p "$win_ssh_dir"
        touch "$win_ssh_config" "$win_known_hosts"
    fi

    # Ensure the key exists on WSL (single source of truth)
    if [[ ! -f "$wsl_key" || ! -f "$wsl_key_pub" ]]; then
        ssh-keygen -t ed25519 -f "$wsl_key" -N "" -C "$key_name" >/dev/null 2>&1 || {
            _cai_error "Failed to generate SSH key: $wsl_key"
            return 1
        }
    fi
    chmod 600 "$wsl_key" 2>/dev/null || true

    # Mirror the key to Windows and lock down ACLs for ssh.exe
    if [[ -n "$win_key" ]] && [[ -f "$wsl_key" ]]; then
        cp "$wsl_key" "$win_key"
        cp "$wsl_key_pub" "$win_key_pub" 2>/dev/null || true
        if command -v icacls.exe >/dev/null 2>&1 && [[ -n "$win_username" ]]; then
            local win_key_winpath=""
            win_key_winpath=$(wslpath -w "$win_key" 2>/dev/null || true)
            if [[ -n "$win_key_winpath" ]]; then
                icacls.exe "$win_key_winpath" /inheritance:r /grant:r "${win_username}:(F)" /c >/dev/null 2>&1 || true
                icacls.exe "${win_key_winpath}.pub" /inheritance:r /grant:r "${win_username}:(R)" /c >/dev/null 2>&1 || true
            fi
        fi
    fi

    # Ensure authorized_keys contains the dedicated key
    if [[ -f "$wsl_key_pub" ]]; then
        touch "$HOME/.ssh/authorized_keys"
        chmod 600 "$HOME/.ssh/authorized_keys"
        local pubkey_line=""
        pubkey_line=$(cat "$wsl_key_pub")
        if ! rg -F -x -q -- "$pubkey_line" "$HOME/.ssh/authorized_keys"; then
            printf '%s\n' "$pubkey_line" >>"$HOME/.ssh/authorized_keys"
        fi
    fi

    # Refresh known_hosts on both sides for the dedicated port
    local kh=""
    for kh in "$wsl_known_hosts" "$win_known_hosts"; do
        [[ -z "$kh" ]] && continue
        ssh-keygen -f "$kh" -R "[127.0.0.1]:${ssh_port}" >/dev/null 2>&1 || true
        ssh-keyscan -p "$ssh_port" 127.0.0.1 >>"$kh" 2>/dev/null || true
    done

    # Build SSH host blocks (Windows OpenSSH has issues with ControlMaster)
    local host_block_common=""
    host_block_common=$(cat <<EOF
Host $host_alias
    HostName 127.0.0.1
    Port $ssh_port
    User $user_name
    IdentityFile ~/.ssh/$key_name
    IdentitiesOnly yes
    IdentityAgent none
    HostKeyAlias [127.0.0.1]:$ssh_port
    StrictHostKeyChecking yes
EOF
)
    local host_block_wsl=""
    host_block_wsl=$(cat <<EOF
$host_block_common
    ControlMaster auto
    ControlPath ~/.ssh/control-%C
    ControlPersist yes
EOF
)
    local host_block_win="$host_block_common"

    # Upsert host block, removing legacy entries first
    upsert_host_block() {
        local config_file="$1"
        local host_block_content="$2"
        local tmp_file=""
        tmp_file=$(mktemp)
        awk -v host="$host_alias" -v legacy="$legacy_alias" '
            BEGIN {skip=0}
            /^[Hh]ost[[:space:]]+/ {
                skip=0
                n=split($0, parts, /[[:space:]]+/)
                for (i=2; i<=n; i++) {
                    if (parts[i]==host || parts[i]==legacy) {
                        skip=1
                    }
                }
            }
            skip==0 {print}
        ' "$config_file" >"$tmp_file"
        printf '\n%s\n' "$host_block_content" >>"$tmp_file"
        mv "$tmp_file" "$config_file"
    }

    upsert_host_block "$wsl_ssh_config" "$host_block_wsl"
    chmod 600 "$wsl_ssh_config" 2>/dev/null || true
    if [[ -n "$win_ssh_config" ]]; then
        upsert_host_block "$win_ssh_config" "$host_block_win"
    fi

    # Update Docker context on WSL
    local expected_host=""
    expected_host=$(_cai_expected_docker_host)
    if docker context inspect "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
        docker context update "$_CAI_CONTAINAI_DOCKER_CONTEXT" --docker "host=$expected_host" >/dev/null 2>&1 || \
            _cai_warn "Failed to update Docker context on WSL"
    else
        docker context create "$_CAI_CONTAINAI_DOCKER_CONTEXT" --docker "host=$expected_host" >/dev/null 2>&1 || \
            _cai_warn "Failed to create Docker context on WSL"
    fi

    # Update Docker context on Windows
    _cai_step "Configuring Windows Docker context (containai-docker)"
    if command -v docker.exe >/dev/null 2>&1; then
        local win_docker_config=""
        if [[ -n "$win_userprofile" ]]; then
            win_docker_config="${win_userprofile}\\.docker"
        fi
        if [[ -z "$win_docker_config" ]]; then
            _cai_warn "Could not determine Windows DOCKER_CONFIG path; skipping Windows context update"
            return 0
        fi
        local -a win_docker_env=("DOCKER_CONFIG=$win_docker_config" "HOME=$win_userprofile")
        if env "${win_docker_env[@]}" docker.exe context inspect "$_CAI_CONTAINAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
            env "${win_docker_env[@]}" docker.exe context update "$_CAI_CONTAINAI_DOCKER_CONTEXT" --docker "host=$expected_host" >/dev/null 2>&1 || \
                _cai_warn "Failed to update Windows Docker context"
        else
            env "${win_docker_env[@]}" docker.exe context create "$_CAI_CONTAINAI_DOCKER_CONTEXT" --docker "host=$expected_host" >/dev/null 2>&1 || \
                _cai_warn "Failed to create Windows Docker context"
        fi
    else
        _cai_warn "docker.exe not found in PATH; configure Windows context manually"
    fi

    # Smoke test SSH connectivity (key-only, no agent)
    if command -v ssh.exe >/dev/null 2>&1; then
        ssh.exe -o BatchMode=yes -o IdentityAgent=none "$host_alias" echo ok >/dev/null 2>&1 || \
            _cai_warn "Windows SSH test failed; check ~/.ssh/$key_name and authorized_keys"
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
# Returns: 0=success, 1=failure, 75=WSL restart required (mirrored mode was disabled)
# Note: Uses isolated Docker daemon - never modifies /etc/docker/daemon.json
#       Detects and blocks mirrored networking mode which is incompatible
_cai_setup_wsl2() {
    local force="${1:-false}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_info "Detected platform: WSL2"
    _cai_info "Setting up Secure Engine with isolated Docker daemon"

    # Step 0: Check for mirrored networking mode (BLOCKING - must be first)
    _cai_step "Checking for mirrored networking mode"
    local mirrored_rc
    _cai_detect_wsl2_mirrored_mode && mirrored_rc=0 || mirrored_rc=$?
    case $mirrored_rc in
        0)
            # Mirrored mode detected - this is a hard blocker
            # Handler returns 1 (declined) or 75 (restart required), never 0
            _cai_handle_wsl2_mirrored_mode "$dry_run"
            return $?
            ;;
        1)
            # Not mirrored - OK to proceed
            _cai_ok "Networking mode: NAT (OK)"
            ;;
        2)
            # Cannot detect - warn and proceed
            _cai_warn "Could not detect networking mode (proceeding)"
            ;;
    esac

    # Step 1: Check kernel version (Sysbox requires 5.5+)
    _cai_step "Checking kernel version"
    local kernel_version kernel_ok
    kernel_version=$(_cai_check_kernel_for_sysbox) && kernel_ok="true" || kernel_ok="false"
    if [[ "$kernel_ok" == "true" ]]; then
        _cai_ok "Kernel version $kernel_version (5.5+ required)"
    else
        _cai_error "Kernel $kernel_version is too old. Sysbox requires kernel 5.5+"
        _cai_error "  Update your WSL kernel:"
        _cai_error "  wsl --update"
        _cai_error "  wsl --shutdown"
        _cai_error "  # Then restart your WSL distribution"
        return 1
    fi

    # Step 2: Test seccomp compatibility
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

    # Step 3: Clean up legacy paths (support upgrades)
    if ! _cai_cleanup_legacy_paths "$dry_run" "$verbose"; then
        _cai_warn "Legacy cleanup had issues (continuing anyway)"
    fi

    # Step 4: Install Sysbox
    if ! _cai_install_sysbox_wsl2 "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 5: Install ContainAI-managed dockerd bundle
    if ! _cai_install_dockerd_bundle "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 6: Create isolated Docker directories
    if ! _cai_create_isolated_docker_dirs "$dry_run"; then
        return 1
    fi

    # Step 7: Ensure isolated bridge exists (cai0)
    if ! _cai_ensure_isolated_bridge "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 8: Create isolated daemon.json (NOT /etc/docker/daemon.json)
    if ! _cai_create_isolated_daemon_json "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 9: Create isolated systemd service (NOT a drop-in to docker.service)
    if ! _cai_create_isolated_docker_service "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 10: Start isolated Docker service
    if ! _cai_start_isolated_docker_service "$dry_run"; then
        return 1
    fi

    # Step 11: Create containai-docker context
    if ! _cai_create_isolated_docker_context "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 12: Configure Windows named-pipe bridge (WSL2 only)
    if ! _cai_setup_wsl2_windows_npipe_bridge "$dry_run" "$verbose"; then
        _cai_warn "Windows named-pipe bridge setup had issues (continuing)"
    fi

    # Step 13: Verify installation
    if ! _cai_verify_isolated_docker "$dry_run" "$verbose"; then
        # Verification failure is a warning, not fatal
        _cai_warn "Isolated Docker verification had issues - check output above"
    fi

    printf '\n'
    _cai_ok "Secure Engine setup complete"
    _cai_info "To use the Secure Engine:"
    _cai_info "  cai run --workspace /path/to/project"
    _cai_info "Or use docker directly: docker --context $_CAI_CONTAINAI_DOCKER_CONTEXT ..."
    _cai_info ""
    _cai_info "Note: sysbox-runc is the default runtime - no need to specify --runtime"

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
      # Add Lima user to docker group (default to 'lima' if LIMA_CIDATA_USER not set)
      usermod -aG docker "${LIMA_CIDATA_USER:-lima}"

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
      # Note: Inside Lima VM, /etc/containai/docker is the isolated path
      mkdir -p /etc/containai/docker
      cat > /etc/containai/docker/daemon.json << 'EOF'
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
    # Use -Fx for literal fixed-string exact match (safer than regex)
    if limactl list --format '{{.Name}}' 2>/dev/null | grep -Fqx "$vm_name"; then
        return 0
    fi
    # Fallback: JSON parsing (less reliable but works with older Lima)
    # Use -F for literal fixed-string match
    limactl list --json 2>/dev/null | grep -Fq "\"name\":\"$vm_name\"" || limactl list --json 2>/dev/null | grep -Fq "\"name\": \"$vm_name\""
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
        trap 'rm -f "$template_file"' EXIT
        _cai_lima_template >"$template_file"

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

# Repair Docker access in existing Lima VM
# Handles the case where socket exists but docker info fails due to permission issues
# (user not in docker group, or group membership not picked up by SSH session)
# Arguments: $1 = dry_run flag ("true" to simulate)
# Returns: 0=repaired, 1=failed
# Note: This function restarts the Lima VM to apply group changes
_cai_lima_repair_docker_access() {
    local dry_run="${1:-false}"

    _cai_step "Repairing Docker access in Lima VM"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would check and repair docker group membership"
        _cai_info "[DRY-RUN] Would restart Lima VM to apply changes"
        return 0
    fi

    # Check if VM exists and is running
    if ! _cai_lima_vm_exists "$_CAI_LIMA_VM_NAME"; then
        _cai_error "Lima VM '$_CAI_LIMA_VM_NAME' does not exist"
        return 1
    fi

    local status
    status=$(_cai_lima_vm_status "$_CAI_LIMA_VM_NAME")
    if [[ "$status" != "Running" ]]; then
        _cai_error "Lima VM is not running (status: $status)"
        return 1
    fi

    # Add user to docker group inside VM (idempotent)
    _cai_step "Ensuring user is in docker group"
    if ! limactl shell "$_CAI_LIMA_VM_NAME" sudo usermod -aG docker "\$USER" 2>/dev/null; then
        _cai_warn "Could not modify docker group (may already be configured)"
    fi

    # Restart VM to apply group changes
    # SSH master socket persists old group membership - must restart VM
    _cai_step "Restarting Lima VM to apply group changes"
    if ! limactl stop "$_CAI_LIMA_VM_NAME"; then
        _cai_error "Failed to stop Lima VM"
        return 1
    fi

    if ! limactl start "$_CAI_LIMA_VM_NAME"; then
        _cai_error "Failed to start Lima VM after repair"
        return 1
    fi

    _cai_ok "Lima VM restarted - Docker group membership should now be active"
    return 0
}

# Wait for Lima Docker socket to be available
# Arguments: $1 = timeout in seconds
#            $2 = dry_run flag
# Returns: 0=socket ready, 1=timeout
# Note: If socket exists but docker info fails, attempts automatic repair
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
    local docker_output docker_rc
    docker_output=$(DOCKER_HOST="unix://$socket_path" docker info 2>&1) && docker_rc=0 || docker_rc=$?

    if [[ $docker_rc -ne 0 ]]; then
        # Diagnose the failure mode
        if printf '%s' "$docker_output" | grep -qi "permission denied"; then
            _cai_warn "Docker permission denied - user likely not in docker group"
            _cai_info "Attempting automatic repair..."

            # Try to repair docker access
            if _cai_lima_repair_docker_access "$dry_run"; then
                # Wait for socket to come back after VM restart (reuse caller's timeout)
                _cai_step "Waiting for socket after VM restart"
                wait_count=0
                while [[ ! -S "$socket_path" ]]; do
                    sleep 1
                    wait_count=$((wait_count + 1))
                    if [[ $wait_count -ge $timeout ]]; then
                        _cai_error "Socket did not reappear after repair (waited ${timeout}s)"
                        return 1
                    fi
                done

                # Verify again
                if DOCKER_HOST="unix://$socket_path" docker info >/dev/null 2>&1; then
                    _cai_ok "Lima Docker socket ready (after repair)"
                    return 0
                else
                    _cai_error "Docker still not accessible after repair"
                    return 1
                fi
            else
                _cai_error "Automatic repair failed"
                return 1
            fi
        elif printf '%s' "$docker_output" | grep -qi "connection refused"; then
            _cai_error "Docker daemon not running inside Lima VM"
            _cai_error "  Try: limactl shell $_CAI_LIMA_VM_NAME sudo systemctl start docker"
            return 1
        else
            _cai_error "Docker not accessible via Lima socket"
            _cai_error "  Socket exists but docker info failed"
            _cai_error "  Error: $docker_output"
            return 1
        fi
    fi

    _cai_ok "Lima Docker socket ready"
    return 0
}

# Create containai-docker Docker context for Lima (macOS)
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_lima_create_context() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local socket_path="$_CAI_LIMA_SOCKET_PATH"
    local context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"

    _cai_step "Creating $context_name Docker context (macOS/Lima)"

    local expected_host="unix://$socket_path"

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Expected socket: $expected_host"
    fi

    # Check if context already exists
    if docker context inspect "$context_name" >/dev/null 2>&1; then
        local existing_host
        existing_host=$(docker context inspect "$context_name" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)

        if [[ "$existing_host" == "$expected_host" ]]; then
            _cai_info "Context '$context_name' already exists with correct endpoint"
            return 0
        else
            _cai_warn "Context '$context_name' exists but points to: $existing_host"
            _cai_warn "  Expected: $expected_host"

            if [[ "$dry_run" == "true" ]]; then
                _cai_info "[DRY-RUN] Would remove and recreate context"
            else
                _cai_step "Removing misconfigured context"
                # Switch away from context if it's currently active
                local current_context
                current_context=$(docker context show 2>/dev/null || true)
                if [[ "$current_context" == "$context_name" ]]; then
                    docker context use default >/dev/null 2>&1 || true
                fi
                # Force remove to avoid interactive prompts
                if ! docker context rm -f "$context_name" >/dev/null 2>&1; then
                    _cai_error "Failed to remove existing context"
                    return 1
                fi
            fi
        fi
    fi

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: docker context create $context_name --docker host=$expected_host"
    else
        if ! docker context create "$context_name" --docker "host=$expected_host"; then
            _cai_error "Failed to create Docker context '$context_name'"
            return 1
        fi
    fi

    _cai_ok "Docker context '$context_name' created"
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
    local context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"

    _cai_step "Verifying Lima + Sysbox installation"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would verify Lima VM status"
        _cai_info "[DRY-RUN] Would verify Sysbox in VM"
        _cai_info "[DRY-RUN] Would verify $context_name context"
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

    # Check containai-docker context exists
    if ! docker context inspect "$context_name" >/dev/null 2>&1; then
        _cai_error "$context_name context not found"
        return 1
    fi

    # Test Sysbox by running minimal container
    _cai_step "Testing sysbox-runc with minimal container"
    local test_output test_rc
    test_output=$(docker --context "$context_name" run --rm --runtime=sysbox-runc alpine echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?

    if [[ $test_rc -ne 0 ]]; then
        _cai_error "Sysbox test container failed (exit code: $test_rc)"
        _cai_error "  Output: $test_output"
        _cai_error "  Check VM provisioning: limactl shell $_CAI_LIMA_VM_NAME"
        return 1
    elif [[ "$test_output" == *"sysbox-test-ok"* ]]; then
        _cai_ok "Sysbox test container succeeded"
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
    if [[ "$current_context" == "$context_name" ]]; then
        _cai_warn "$context_name is currently the active context"
        _cai_warn "  Docker Desktop should remain default for safety"
        _cai_warn "  Switch back: docker context use default"
    elif [[ "$current_context" == "default" ]] || [[ "$current_context" == "desktop-linux" ]]; then
        _cai_ok "Docker Desktop remains the active context: $current_context"
    else
        _cai_info "Current Docker context: $current_context (not $context_name - acceptable)"
    fi

    _cai_ok "Lima + Sysbox installation verified"
    return 0
}

# macOS-specific setup using Lima VM
# Arguments: $1 = force flag ("true" to auto-delete legacy VM without prompting)
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
    _cai_info "  - Use --context $_CAI_CONTAINAI_DOCKER_CONTEXT to access Sysbox"
    printf '\n'

    # Step 0: Clean up legacy paths (sockets, contexts, drop-ins)
    # Note: Lima VM cleanup happens AFTER new VM is verified (Step 7)
    if ! _cai_cleanup_legacy_paths "$dry_run" "$verbose"; then
        _cai_warn "Legacy path cleanup had issues - continuing anyway"
    fi

    # Step 1: Ensure required host tools (jq, rg)
    _cai_step "Ensuring required host tools are installed"
    if ! _cai_macos_ensure_host_tools "$dry_run"; then
        return 1
    fi

    # Step 2: Install Lima (via Homebrew)
    if ! _cai_lima_install "$dry_run"; then
        return 1
    fi

    # Step 3: Create Lima VM with Docker + Sysbox
    if ! _cai_lima_create_vm "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 4: Wait for Lima Docker socket
    if ! _cai_lima_wait_socket 120 "$dry_run"; then
        return 1
    fi

    # Step 5: Create containai-docker context
    if ! _cai_lima_create_context "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 6: Verify installation
    local verify_ok=true
    if ! _cai_lima_verify_install "$dry_run" "$verbose"; then
        _cai_warn "Lima + Sysbox verification had issues - check output above"
        verify_ok=false
    fi

    # Step 7: Clean up legacy Lima VM (only if new VM is verified working)
    # This ensures users aren't left without a working VM if setup fails
    # Pass force flag to allow auto-deletion with --force, otherwise shows manual instructions
    if [[ "$verify_ok" == "true" ]]; then
        _cai_cleanup_legacy_lima_vm "$dry_run" "$verbose" "$force"
    else
        # Don't delete legacy VM if new VM has issues - user may need fallback
        if _cai_is_macos && _cai_lima_vm_exists "$_CAI_LEGACY_LIMA_VM_NAME" 2>/dev/null; then
            _cai_warn "Legacy Lima VM '$_CAI_LEGACY_LIMA_VM_NAME' preserved (new VM had issues)"
            _cai_info "To manually migrate after fixing issues:"
            _cai_info "  limactl stop $_CAI_LEGACY_LIMA_VM_NAME"
            _cai_info "  limactl delete $_CAI_LEGACY_LIMA_VM_NAME"
        fi
    fi

    printf '\n'
    _cai_ok "Secure Engine setup complete (macOS/Lima)"
    _cai_info "To use the Secure Engine:"
    _cai_info "  cai run --workspace /path/to/project"
    _cai_info "Or use docker directly: docker --context $_CAI_CONTAINAI_DOCKER_CONTEXT --runtime=sysbox-runc ..."
    printf '\n'
    _cai_info "Lima VM management:"
    _cai_info "  Start:  limactl start $_CAI_LIMA_VM_NAME"
    _cai_info "  Stop:   limactl stop $_CAI_LIMA_VM_NAME"
    _cai_info "  Shell:  limactl shell $_CAI_LIMA_VM_NAME"
    _cai_info "  Status: limactl list"

    return 0
}

# ==============================================================================
# Native Linux Setup
# ==============================================================================

# Native Linux supported distributions
# Returns: 0 if distro is fully supported (auto-install), 1 otherwise
# Outputs: Sets _CAI_LINUX_DISTRO, _CAI_LINUX_VERSION_ID
_cai_linux_detect_distro() {
    _CAI_LINUX_DISTRO=""
    _CAI_LINUX_VERSION_ID=""

    if [[ ! -f /etc/os-release ]]; then
        return 1
    fi

    # Source os-release to get ID and VERSION_ID
    # shellcheck disable=SC1091
    _CAI_LINUX_DISTRO=$(. /etc/os-release && printf '%s' "${ID:-unknown}")
    # shellcheck disable=SC1091
    _CAI_LINUX_VERSION_ID=$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")

    # Check if this is a supported distribution for auto-install
    case "$_CAI_LINUX_DISTRO" in
        ubuntu | debian)
            return 0
            ;;
        fedora | rhel | centos | arch | manjaro)
            # These are recognized but not auto-install supported
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if Docker Desktop is running on Linux (can coexist)
# Returns: 0 if Docker Desktop detected, 1 otherwise
_cai_linux_docker_desktop_detected() {
    # Check for Docker Desktop process
    if pgrep -x "docker-desktop" >/dev/null 2>&1; then
        return 0
    fi

    # Check for desktop-linux context (Docker Desktop creates this)
    if docker context ls 2>/dev/null | grep -q "desktop-linux"; then
        return 0
    fi

    return 1
}

# Install Sysbox on native Linux (Ubuntu/Debian)
# Arguments: $1 = dry_run flag ("true" to simulate)
#            $2 = verbose flag ("true" for verbose output)
#            $3 = force_install flag ("true" to reinstall even if present)
# Returns: 0=success, 1=failure
# Note: Similar to WSL2 but without WSL-specific checks (systemd PID 1, seccomp)
_cai_install_sysbox_linux() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local force_install="${3:-false}"

    # Detect distro
    if ! _cai_linux_detect_distro; then
        _cai_error "Sysbox auto-install only supports Ubuntu/Debian on native Linux"
        _cai_error "  Detected distro: ${_CAI_LINUX_DISTRO:-unknown}"
        _cai_error "  For other distros, install Sysbox manually:"
        _cai_error "  https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md"
        return 1
    fi

    _cai_info "Detected distribution: $_CAI_LINUX_DISTRO $_CAI_LINUX_VERSION_ID"

    # Check for systemd (required for Sysbox service)
    if ! command -v systemctl >/dev/null 2>&1; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_warn "[DRY-RUN] systemctl not found - systemd required for actual install"
        else
            _cai_error "Sysbox requires systemd (systemctl not found)"
            _cai_error "  Sysbox services require systemd to be the init system"
            return 1
        fi
    fi

    # Verify systemd is actually the init system (PID 1)
    # This catches containers, alternative inits, or minimal systems where systemctl exists
    # but systemd is not the init
    if [[ "$dry_run" != "true" ]]; then
        local pid1_cmd
        pid1_cmd=$(ps -p 1 -o comm= 2>/dev/null || true)
        if [[ "$pid1_cmd" != "systemd" ]]; then
            _cai_error "Sysbox requires systemd as the init system (PID 1)"
            _cai_error "  Found PID 1: ${pid1_cmd:-unknown}"
            _cai_error "  Sysbox services require systemd to manage sysbox-mgr and sysbox-fs"
            return 1
        fi
    fi

    # Ensure jq (daemon.json merge), ripgrep (rg), and wget are available
    _cai_step "Ensuring required tools are installed"
    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would ensure jq, ripgrep, and wget are installed"
    else
        local -a missing_tools=()
        if ! command -v jq >/dev/null 2>&1; then
            missing_tools+=(jq)
        fi
        if ! command -v rg >/dev/null 2>&1; then
            missing_tools+=(ripgrep)
        fi
        if ! command -v wget >/dev/null 2>&1; then
            missing_tools+=(wget)
        fi
        if ((${#missing_tools[@]} > 0)); then
            _cai_info "Installing required tools: ${missing_tools[*]}"
            if ! sudo apt-get update -qq; then
                _cai_error "Failed to run apt-get update"
                return 1
            fi
            if ! sudo apt-get install -y "${missing_tools[@]}"; then
                _cai_error "Failed to install required tools: ${missing_tools[*]}"
                return 1
            fi
        fi
    fi

    _cai_step "Checking for existing Sysbox installation"
    local installed_version_line=""
    local installed_version_semver=""
    local sysbox_present="false"
    if command -v sysbox-runc >/dev/null 2>&1; then
        sysbox_present="true"
        installed_version_line=$(sysbox-runc --version 2>/dev/null | head -1 || true)
        installed_version_semver=$(printf '%s' "$installed_version_line" | sed -n 's/[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)
        _cai_info "Sysbox already installed: ${installed_version_line:-unknown version}"
        if [[ -n "$installed_version_semver" ]] && [[ "$verbose" == "true" ]]; then
            _cai_info "Parsed installed version: $installed_version_semver"
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

    # Resolve target Sysbox version and download URL from GitHub
    # Support CAI_SYSBOX_VERSION override for pinning or rate limit workaround
    local sysbox_version_override="${CAI_SYSBOX_VERSION:-}"
    local release_url="https://api.github.com/repos/nestybox/sysbox/releases/latest"
    local download_url=""
    local latest_version=""
    local release_json=""

    if [[ -n "$sysbox_version_override" ]]; then
        latest_version="$sysbox_version_override"
        _cai_info "Using pinned Sysbox version: $latest_version"
        download_url="https://github.com/nestybox/sysbox/releases/download/v${latest_version}/sysbox-ce_${latest_version}-0.linux_${arch}.deb"
    fi

    if [[ "$dry_run" == "true" ]]; then
        if [[ -n "$sysbox_version_override" ]]; then
            _cai_info "[DRY-RUN] Would ensure Sysbox version: $latest_version"
        else
            _cai_info "[DRY-RUN] Would fetch latest release from: $release_url"
        fi
        _cai_info "[DRY-RUN] Would download Sysbox .deb for architecture: $arch"
        _cai_info "[DRY-RUN] Would install with: dpkg -i sysbox-ce.deb"
        _cai_ok "Sysbox installation (dry-run) complete"
        return 0
    fi

    # Fetch release info from GitHub API if not using pinned version
    if [[ -z "$sysbox_version_override" ]]; then
        release_json=$(wget -qO- "$release_url" 2>&1) || {
            _cai_error "Failed to fetch Sysbox release info from GitHub"
            _cai_error "  This may be due to GitHub API rate limiting or network issues"
            _cai_error "  Workaround: Set CAI_SYSBOX_VERSION to pin a specific version"
            _cai_error "  Example: export CAI_SYSBOX_VERSION=0.6.7"
            return 1
        }

        # Check for rate limit error
        if printf '%s' "$release_json" | grep -qiE "API rate limit|rate limit exceeded"; then
            _cai_error "GitHub API rate limit exceeded"
            _cai_error "  Workaround: Set CAI_SYSBOX_VERSION to pin a specific version"
            _cai_error "  Example: export CAI_SYSBOX_VERSION=0.6.7"
            _cai_error "  Find versions at: https://github.com/nestybox/sysbox/releases"
            return 1
        fi

        local latest_tag
        latest_tag=$(printf '%s' "$release_json" | jq -r '.tag_name // empty' | head -1)
        latest_version="${latest_tag#v}"
        if [[ -z "$latest_version" ]]; then
            _cai_error "Could not determine latest Sysbox version from GitHub"
            return 1
        fi

        # Extract .deb download URL for this architecture
        download_url=$(printf '%s' "$release_json" | jq -r ".assets[] | select(.name | test(\"sysbox-ce.*${arch}.deb\")) | .browser_download_url" | head -1)
    fi

    if [[ -n "$latest_version" ]]; then
        _cai_info "Target Sysbox version: $latest_version"
    fi

    # Determine if installation or upgrade is needed
    if [[ "$force_install" != "true" && "$sysbox_present" == "true" ]]; then
        if [[ -n "$installed_version_semver" ]] && [[ -n "$latest_version" ]]; then
            local highest_version
            highest_version=$(printf '%s\n%s\n' "$installed_version_semver" "$latest_version" | sort -V | tail -1)
            if [[ "$highest_version" == "$installed_version_semver" ]]; then
                _cai_ok "Sysbox already up to date ($installed_version_semver)"
                return 0
            fi
            _cai_info "Upgrading Sysbox from $installed_version_semver to $latest_version"
        else
            _cai_warn "Could not compare installed Sysbox version to target; proceeding with upgrade"
        fi
    fi

    _cai_step "Installing Sysbox dependencies"
    if ! command -v jq >/dev/null 2>&1 || ! command -v rg >/dev/null 2>&1 || ! command -v wget >/dev/null 2>&1; then
        _cai_info "Installing missing dependencies: jq ripgrep wget"
        if ! sudo apt-get update; then
            _cai_error "Failed to run apt-get update"
            return 1
        fi
        if ! sudo apt-get install -y jq ripgrep wget; then
            _cai_error "Failed to install dependencies (jq, ripgrep, wget)"
            return 1
        fi
    fi

    if [[ -z "$download_url" ]] || [[ "$download_url" == "null" ]]; then
        _cai_error "Could not find Sysbox .deb package for architecture: $arch"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Download URL: $download_url"
    fi

    # Download and install in subshell to contain cleanup trap
    local install_rc
    (
        set -e
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT
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

    # Verify Sysbox didn't modify /etc/docker/daemon.json (spec requirement)
    # Some Sysbox versions may auto-configure the system Docker, which we must prevent
    if [[ -f /etc/docker/daemon.json ]]; then
        if grep -q "sysbox-runc" /etc/docker/daemon.json 2>/dev/null; then
            _cai_warn "Sysbox may have modified /etc/docker/daemon.json"
            _cai_warn "  ContainAI uses an isolated daemon - system config should remain unchanged"
            _cai_warn "  You may want to remove sysbox-runc from /etc/docker/daemon.json"
            _cai_warn "  to keep system Docker unmodified."
            # Not fatal - user may want sysbox available in system Docker too
        fi
    fi

    _cai_ok "Sysbox installation complete"
    return 0
}

# Verify Sysbox installation on native Linux
# Arguments: $1 = socket path for verification
#            $2 = dry_run flag ("true" to skip actual verification)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_verify_sysbox_install_linux() {
    local socket_path="${1:-/var/run/docker.sock}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_step "Verifying Sysbox installation"

    local context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would verify sysbox-runc and sysbox-mgr"
        _cai_info "[DRY-RUN] Would verify Docker runtime configuration via socket: $socket_path"
        _cai_info "[DRY-RUN] Would verify $context_name context"
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

    # Check Docker recognizes sysbox-runc runtime (via specified socket)
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

    # Check containai-docker context
    if ! docker context inspect "$context_name" >/dev/null 2>&1; then
        _cai_error "$context_name context not found"
        return 1
    fi

    # Verify sysbox-runc works by running a minimal container via the context
    _cai_step "Testing sysbox-runc with minimal container"
    local test_output test_rc test_passed=false
    test_output=$(docker --context "$context_name" run --rm --runtime=sysbox-runc alpine echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?

    if [[ $test_rc -ne 0 ]]; then
        _cai_error "Sysbox test container failed (exit code: $test_rc)"
        _cai_error "  Output: $test_output"
        _cai_error "  Remediation: Check Sysbox installation and Docker configuration"
        # Native Linux: fail on test failure (unlike WSL2 which has known seccomp issues)
        return 1
    elif [[ "$test_output" == *"sysbox-test-ok"* ]]; then
        _cai_ok "Sysbox test container succeeded"
        test_passed=true
    else
        _cai_error "Sysbox test container did not produce expected output"
        _cai_error "  Output: $test_output"
        return 1
    fi

    _cai_ok "Sysbox installation verified"
    return 0
}

# Native Linux-specific setup
# Arguments: $1 = force flag (unused for native Linux, kept for API consistency)
#            $2 = dry_run flag ("true" to simulate)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_setup_linux() {
    local force="${1:-false}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    _cai_info "Detected platform: Linux (native)"
    _cai_info "Setting up Secure Engine with isolated Docker daemon"

    # Step 0: Check kernel version (Sysbox requires 5.5+)
    _cai_step "Checking kernel version"
    local kernel_version kernel_ok
    kernel_version=$(_cai_check_kernel_for_sysbox) && kernel_ok="true" || kernel_ok="false"
    if [[ "$kernel_ok" == "true" ]]; then
        _cai_ok "Kernel version $kernel_version (5.5+ required)"
    else
        _cai_error "Kernel $kernel_version is too old. Sysbox requires kernel 5.5+"
        _cai_error "  Upgrade your kernel to 5.5+ to use Sysbox."
        _cai_error "  Most modern distros (Ubuntu 22.04+, Debian 12+) include 5.15+."
        return 1
    fi

    # Detect distribution FIRST - if unsupported, show manual instructions
    # regardless of Docker status (per acceptance criteria: "handle unsupported
    # distributions gracefully with clear message")
    if ! _cai_linux_detect_distro; then
        # Distribution not supported for auto-install
        _cai_error "Auto-install not supported for distribution: ${_CAI_LINUX_DISTRO:-unknown}"
        printf '\n'
        _cai_info "Supported distributions for auto-install:"
        _cai_info "  - Ubuntu 22.04, 24.04"
        _cai_info "  - Debian 11, 12"
        printf '\n'
        _cai_info "For other distributions, install Sysbox manually:"
        _cai_info "  Fedora/RHEL: Build from source"
        _cai_info "  Arch Linux: AUR package (sysbox-ce-bin)"
        _cai_info ""
        _cai_info "Manual installation steps:"
        _cai_info "  1. Install Sysbox: https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md"
        _cai_info "  2. Download Docker static binaries from https://download.docker.com/linux/static/stable/"
        _cai_info "     Extract to /opt/containai/docker/<version>/ and create symlinks in /opt/containai/bin/"
        _cai_info "  3. Create isolated config: /etc/containai/docker/daemon.json"
        _cai_info "  4. Create systemd unit: /etc/systemd/system/containai-docker.service"
        _cai_info "     ExecStart=/opt/containai/bin/dockerd --config-file=/etc/containai/docker/daemon.json"
        _cai_info "     Environment=PATH=/opt/containai/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        _cai_info "  5. Start service: sudo systemctl enable --now containai-docker"
        _cai_info "  6. Create context: docker context create containai-docker --docker host=unix://$_CAI_CONTAINAI_DOCKER_SOCKET"
        return 1
    fi

    # Preflight: Check Docker CLI is available
    # (Only run after distro detection succeeds to ensure unsupported distros get
    # manual instructions regardless of Docker status)
    # We need docker CLI for context creation; dockerd comes from our bundle
    # In dry-run mode, degrade to warnings so users can see planned actions
    _cai_step "Preflight: Checking Docker CLI"
    if ! command -v docker >/dev/null 2>&1; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_warn "[DRY-RUN] Docker CLI not found - would be required for actual setup"
            _cai_warn "  Install Docker Engine first: https://docs.docker.com/engine/install/"
        else
            _cai_error "Docker CLI is not installed"
            _cai_error "  Install Docker Engine first:"
            _cai_error "  https://docs.docker.com/engine/install/"
            return 1
        fi
    else
        _cai_ok "Docker CLI available"
    fi

    # Note: We no longer require system dockerd - the bundle provides it
    # The bundle installs dockerd to /opt/containai/bin/dockerd

    # Step 1: Check for Docker Desktop coexistence
    _cai_step "Checking for Docker Desktop"
    if _cai_linux_docker_desktop_detected; then
        printf '\n'
        _cai_info "Docker Desktop detected on this system"
        _cai_info "  ContainAI creates a completely isolated Docker daemon"
        _cai_info "  Docker Desktop configuration will NOT be modified"
        _cai_info "  Use --context $_CAI_CONTAINAI_DOCKER_CONTEXT to access Sysbox isolation"
        printf '\n'
    fi

    # Check for active system Docker service (potential iptables conflicts)
    if systemctl is-active docker.service >/dev/null 2>&1; then
        printf '\n'
        _cai_warn "System docker.service is currently active"
        _cai_warn "  Running two Docker daemons can cause iptables/networking conflicts"
        _cai_warn "  ContainAI uses a separate bridge (cai0) and subnet (172.30.0.0/16)"
        _cai_warn "  to minimize conflicts, but issues may still occur."
        _cai_warn ""
        _cai_warn "  Options to avoid conflicts:"
        _cai_warn "    1. Stop system Docker while using ContainAI:"
        _cai_warn "       sudo systemctl stop docker.service"
        _cai_warn "    2. Or continue and monitor for networking issues"
        printf '\n'
        # Not a fatal error - user may want to run both carefully
    fi

    # Step 2: Clean up legacy paths (support upgrades from old installation)
    if ! _cai_cleanup_legacy_paths "$dry_run" "$verbose"; then
        _cai_warn "Legacy cleanup had issues (continuing anyway)"
    fi

    # Step 3: Install Sysbox
    if ! _cai_install_sysbox_linux "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 4: Install ContainAI-managed dockerd bundle
    if ! _cai_install_dockerd_bundle "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 5: Create isolated Docker directories
    if ! _cai_create_isolated_docker_dirs "$dry_run"; then
        return 1
    fi

    # Step 6: Ensure isolated bridge exists (cai0)
    if ! _cai_ensure_isolated_bridge "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 7: Create isolated daemon.json (NOT /etc/docker/daemon.json)
    if ! _cai_create_isolated_daemon_json "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 8: Create isolated systemd service (NOT a drop-in to docker.service)
    if ! _cai_create_isolated_docker_service "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 9: Start isolated Docker service
    if ! _cai_start_isolated_docker_service "$dry_run"; then
        return 1
    fi

    # Step 10: Create containai-docker context
    if ! _cai_create_isolated_docker_context "$dry_run" "$verbose"; then
        return 1
    fi

    # Step 11: Verify installation
    if ! _cai_verify_isolated_docker "$dry_run" "$verbose"; then
        # Verification failure is a warning, not fatal
        _cai_warn "Isolated Docker verification had issues - check output above"
    fi

    printf '\n'
    _cai_ok "Secure Engine setup complete"
    _cai_info "To use the Secure Engine:"
    _cai_info "  cai run --workspace /path/to/project"
    _cai_info "Or use docker directly: docker --context $_CAI_CONTAINAI_DOCKER_CONTEXT ..."
    _cai_info ""
    _cai_info "Note: sysbox-runc is the default runtime - no need to specify --runtime"

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
            --verbose | -v)
                verbose="true"
                shift
                ;;
            --help | -h)
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

    # Step 0: Setup SSH key and config directory (common to all platforms)
    if [[ "$dry_run" != "true" ]]; then
        if ! _cai_setup_ssh_key; then
            _cai_error "Failed to setup SSH key"
            return 1
        fi
        printf '\n'
        if ! _cai_setup_ssh_config; then
            _cai_error "Failed to setup SSH config"
            return 1
        fi
        printf '\n'
    else
        _cai_info "[DRY-RUN] Would create ~/.config/containai/ directory"
        _cai_info "[DRY-RUN] Would generate ed25519 SSH key at ~/.config/containai/id_containai"
        _cai_info "[DRY-RUN] Would create ~/.config/containai/config.toml"
        _cai_info "[DRY-RUN] Would create ~/.ssh/containai.d/ directory"
        _cai_info "[DRY-RUN] Would add Include directive to ~/.ssh/config"
        printf '\n'
    fi

    if _cai_is_container; then
        _cai_setup_nested "$dry_run" "$verbose"
        return $?
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
            _cai_setup_linux "$force" "$dry_run" "$verbose"
            return $?
            ;;
        *)
            _cai_error "Unknown platform: $platform"
            return 1
            ;;
    esac
}

# Nested setup (running inside a container)
# Use the default Docker daemon inside the container (no isolated containai-docker
# daemon). This avoids conflicting bridges and keeps Docker-in-Docker self-contained.
_cai_setup_nested() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_info "Detected container environment (nested setup)"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would stop containai-docker.service if running"
        _cai_info "[DRY-RUN] Would remove bridge $_CAI_CONTAINAI_DOCKER_BRIDGE if present"
        _cai_info "[DRY-RUN] Would ensure sysbox-runc is installed and up to date"
        _cai_info "[DRY-RUN] Would start sysbox-mgr/sysbox-fs if available"
        _cai_info "[DRY-RUN] Would ensure docker defaults to sysbox-runc"
        _cai_info "[DRY-RUN] Would ensure docker data-root is /var/lib/docker"
        _cai_info "[DRY-RUN] Would restart docker.service if configuration changes"
        _cai_info "[DRY-RUN] Would ensure docker.service is running"
        _cai_info "[DRY-RUN] Would verify Docker daemon via default context"
        _cai_info "[DRY-RUN] Would verify DockerRootDir is /var/lib/docker"
        _cai_info "[DRY-RUN] Would verify default runtime is sysbox-runc"
        return 0
    fi

    # If an inner containai-docker service is running, stop it to avoid network conflicts
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${_CAI_CONTAINAI_DOCKER_SERVICE}"; then
            if systemctl is-active --quiet "$_CAI_CONTAINAI_DOCKER_SERVICE" 2>/dev/null; then
                _cai_warn "containai-docker.service is running inside the container; stopping to avoid network conflicts"
                if ! sudo systemctl stop "$_CAI_CONTAINAI_DOCKER_SERVICE" 2>/dev/null; then
                    _cai_warn "Failed to stop $_CAI_CONTAINAI_DOCKER_SERVICE (continuing)"
                fi
            fi
            if systemctl is-enabled --quiet "$_CAI_CONTAINAI_DOCKER_SERVICE" 2>/dev/null; then
                if ! sudo systemctl disable "$_CAI_CONTAINAI_DOCKER_SERVICE" 2>/dev/null; then
                    _cai_warn "Failed to disable $_CAI_CONTAINAI_DOCKER_SERVICE (continuing)"
                fi
            fi
        fi
    fi

    # Remove leftover containai bridge if present (created by inner containai-docker)
    if command -v ip >/dev/null 2>&1; then
        if ip link show "$_CAI_CONTAINAI_DOCKER_BRIDGE" >/dev/null 2>&1; then
            _cai_warn "Found leftover bridge $_CAI_CONTAINAI_DOCKER_BRIDGE; removing to avoid conflicts"
            if ! sudo ip link delete "$_CAI_CONTAINAI_DOCKER_BRIDGE" 2>/dev/null; then
                _cai_warn "Failed to remove bridge $_CAI_CONTAINAI_DOCKER_BRIDGE (continuing)"
            fi
        fi
    fi

    local sysbox_missing_before="false"
    local sysbox_version_before=""
    if command -v sysbox-runc >/dev/null 2>&1; then
        sysbox_version_before=$(sysbox-runc --version 2>/dev/null | head -1 | sed -n 's/[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)
    else
        sysbox_missing_before="true"
    fi
    if ! _cai_install_sysbox_linux "false" "$verbose"; then
        _cai_error "Failed to install sysbox-runc inside the container"
        return 1
    fi
    local sysbox_version_after=""
    if command -v sysbox-runc >/dev/null 2>&1; then
        sysbox_version_after=$(sysbox-runc --version 2>/dev/null | head -1 | sed -n 's/[^0-9]*\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)
    else
        _cai_error "sysbox-runc is still not available after installation"
        return 1
    fi
    local sysbox_installed="false"
    if [[ "$sysbox_missing_before" == "true" ]]; then
        sysbox_installed="true"
    elif [[ -n "$sysbox_version_before" ]] && [[ -n "$sysbox_version_after" ]] && [[ "$sysbox_version_before" != "$sysbox_version_after" ]]; then
        sysbox_installed="true"
    elif [[ -z "$sysbox_version_before" ]] && [[ -n "$sysbox_version_after" ]]; then
        sysbox_installed="true"
    fi

    # Start sysbox services if available (required for sysbox-runc)
    if command -v systemctl >/dev/null 2>&1; then
        local svc sysbox_services_ok="true"
        for svc in sysbox-mgr.service sysbox-fs.service; do
            if ! systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${svc}"; then
                _cai_error "$svc not found (sysbox installation incomplete)"
                sysbox_services_ok="false"
                continue
            fi
            if ! systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                _cai_info "Enabling $svc"
                if ! sudo systemctl enable "$svc" >/dev/null 2>&1; then
                    _cai_warn "Failed to enable $svc"
                fi
            fi
            if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
                _cai_info "Starting $svc"
                if ! sudo systemctl start "$svc" 2>/dev/null; then
                    _cai_warn "Failed to start $svc"
                fi
            fi
            if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
                _cai_error "$svc is not running"
                sysbox_services_ok="false"
            fi
        done
        if [[ "$sysbox_services_ok" != "true" ]]; then
            _cai_error "Sysbox services must be running before Docker can start"
            return 1
        fi
    fi

    local runtime_config_updated="false"
    local docker_restart_needed="false"
    local daemon_json="/etc/docker/daemon.json"
    local desired_runtime_path="/usr/bin/sysbox-runc"
    local desired_data_root="/var/lib/docker"

    _cai_step "Ensuring docker defaults to sysbox-runc"

    if command -v apt-get >/dev/null 2>&1; then
        local -a missing_tools=()
        if ! command -v jq >/dev/null 2>&1; then
            missing_tools+=(jq)
        fi
        if ! command -v rg >/dev/null 2>&1; then
            missing_tools+=(ripgrep)
        fi
        if ((${#missing_tools[@]} > 0)); then
            _cai_info "Installing required tools: ${missing_tools[*]}"
            sudo apt-get update -qq >/dev/null 2>&1 || _cai_warn "apt-get update failed (continuing)"
            if ! sudo apt-get install -y "${missing_tools[@]}" >/dev/null 2>&1; then
                _cai_warn "Failed to install required tools: ${missing_tools[*]}"
            fi
        fi
    fi

    if command -v jq >/dev/null 2>&1 && [[ -f "$daemon_json" ]]; then
        local configured_data_root=""
        configured_data_root=$(jq -r '."data-root" // empty' "$daemon_json" 2>/dev/null || true)
        if [[ -n "$configured_data_root" ]] && [[ "$configured_data_root" != "$desired_data_root" ]]; then
            _cai_warn "Docker data-root is '$configured_data_root'; sysbox expects '$desired_data_root'"
        fi
    fi

    local new_config=""
    if command -v jq >/dev/null 2>&1 && [[ -f "$daemon_json" ]]; then
        new_config=$(jq --arg path "$desired_runtime_path" --arg data_root "$desired_data_root" '
            if type != "object" then {} else . end
            | .["data-root"] = $data_root
            | .runtimes = (.runtimes // {})
            | .runtimes["sysbox-runc"] = { "path": $path }
            | .["default-runtime"] = "sysbox-runc"
        ' "$daemon_json" 2>/dev/null || true)
    fi
    if [[ -z "$new_config" ]]; then
        new_config=$(cat <<EOF
{
  "data-root": "$desired_data_root",
  "default-runtime": "sysbox-runc",
  "runtimes": {
    "sysbox-runc": {
      "path": "$desired_runtime_path"
    }
  }
}
EOF
)
    fi

    local current_config=""
    current_config=$(cat "$daemon_json" 2>/dev/null || true)

    local configs_match="false"
    if command -v jq >/dev/null 2>&1 && [[ -n "$current_config" ]]; then
        local current_canon new_canon
        current_canon=$(jq -S '.' "$daemon_json" 2>/dev/null || true)
        new_canon=$(printf '%s\n' "$new_config" | jq -S '.' 2>/dev/null || true)
        if [[ -n "$current_canon" && -n "$new_canon" && "$current_canon" == "$new_canon" ]]; then
            configs_match="true"
        fi
    fi
    if [[ "$configs_match" != "true" && "$current_config" == "$new_config" ]]; then
        configs_match="true"
    fi

    if [[ "$configs_match" != "true" ]]; then
        if ! printf '%s\n' "$new_config" | sudo tee "$daemon_json" >/dev/null; then
            _cai_error "Failed to write $daemon_json"
            return 1
        fi
        runtime_config_updated="true"
    fi

    if [[ "$sysbox_installed" == "true" || "$runtime_config_updated" == "true" ]]; then
        docker_restart_needed="true"
    fi
    if [[ "$docker_restart_needed" == "true" ]]; then
        if command -v systemctl >/dev/null 2>&1; then
            _cai_info "Restarting docker.service to apply sysbox runtime changes"
            if ! sudo systemctl restart docker >/dev/null 2>&1; then
                _cai_error "Failed to restart docker.service inside container"
                return 1
            fi
        else
            _cai_error "systemctl not available inside container"
            return 1
        fi
    fi

    _cai_step "Checking inner Docker daemon"
    if ! DOCKER_CONTEXT= DOCKER_HOST= docker info >/dev/null 2>&1; then
        _cai_warn "Inner Docker not reachable, attempting to start docker.service"
        if command -v systemctl >/dev/null 2>&1; then
            if ! sudo systemctl start docker 2>/dev/null; then
                _cai_error "Failed to start docker.service inside container"
                return 1
            fi
        else
            _cai_error "systemctl not available inside container"
            return 1
        fi
        if ! DOCKER_CONTEXT= DOCKER_HOST= docker info >/dev/null 2>&1; then
            _cai_error "Inner Docker still not reachable"
            return 1
        fi
    fi
    _cai_ok "Inner Docker is reachable"

    # Check Docker root dir (sysbox expects /var/lib/docker)
    local docker_root
    docker_root=$(DOCKER_CONTEXT= DOCKER_HOST= docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)
    if [[ "$docker_root" == "/var/lib/docker" ]]; then
        _cai_ok "DockerRootDir: /var/lib/docker"
    else
        _cai_warn "DockerRootDir is '$docker_root' (expected /var/lib/docker for sysbox)"
    fi

    # Check runtimes and default runtime
    local runtimes_json=""
    runtimes_json=$(DOCKER_CONTEXT= DOCKER_HOST= docker info --format '{{json .Runtimes}}' 2>/dev/null || true)
    if printf '%s' "$runtimes_json" | grep -q "sysbox-runc"; then
        _cai_ok "sysbox-runc runtime available in inner Docker"
    else
        _cai_error "sysbox-runc runtime not found in inner Docker"
        _cai_error "  Run 'cai setup' again after ensuring sysbox services are healthy"
        return 1
    fi

    local default_runtime=""
    default_runtime=$(DOCKER_CONTEXT= DOCKER_HOST= docker info --format '{{.DefaultRuntime}}' 2>/dev/null || true)
    if [[ "$default_runtime" == "sysbox-runc" ]]; then
        _cai_ok "Default runtime: sysbox-runc"
    else
        _cai_error "Default runtime: ${default_runtime:-unknown} (expected sysbox-runc)"
        _cai_error "  Check /etc/docker/daemon.json and restart docker.service"
        return 1
    fi

    printf '\n'
    _cai_ok "Nested setup complete"
    _cai_info "Using default Docker context inside the container"
    return 0
}

# Setup help text
_cai_setup_help() {
    cat <<'EOF'
ContainAI Setup - Secure Engine Provisioning

Usage: cai setup [options]

Configures secure container isolation with Sysbox runtime.

Platform behavior:
  - Linux (Ubuntu/Debian) / WSL2: Installs Sysbox, creates isolated Docker daemon
  - Linux (other distros): Requires manual Sysbox install, then creates daemon
  - macOS: Creates a lightweight Linux VM (Lima) running Docker + Sysbox

Options:
  --force       Bypass seccomp compatibility warning and proceed (WSL2 only)
  --dry-run     Show what would be done without making changes
  --verbose     Show detailed progress information
  -h, --help    Show this help message

What It Does (Linux native):
  1. Detects distribution (Ubuntu/Debian supported for auto-install)
  2. Cleans up any legacy ContainAI paths from previous installations
  3. Downloads and installs Sysbox from GitHub releases
  4. Creates isolated Docker daemon with sysbox-runc as default runtime:
     - Config: /etc/containai/docker/daemon.json
     - Socket: /var/run/containai-docker.sock
     - Data:   /var/lib/containai-docker/
     - Service: containai-docker.service
  5. Creates 'containai-docker' Docker context pointing to isolated socket
  6. Verifies installation with test container
  Note: System Docker is NOT modified. Fedora/RHEL/Arch require manual install.

What It Does (WSL2):
  1. Checks seccomp compatibility (warns if WSL 1.1.0+ filter conflict)
  2. Cleans up any legacy ContainAI paths from previous installations
  3. Downloads and installs Sysbox from GitHub releases
  4. Creates isolated Docker daemon with sysbox-runc as default runtime:
     - Config: /etc/containai/docker/daemon.json
     - Socket: /var/run/containai-docker.sock
     - Service: containai-docker.service
  5. Creates 'containai-docker' Docker context pointing to isolated socket
  6. Verifies installation

What It Does (macOS):
  1. Installs Lima via Homebrew (if not present)
  2. Creates Lima VM 'containai-docker' with Ubuntu 24.04
  3. Installs Docker Engine and Sysbox inside the VM
  4. Exposes Docker socket to macOS host via Lima port forwarding
  5. Creates 'containai-docker' Docker context pointing to Lima socket
  6. Verifies installation

Requirements (Linux native):
  - Ubuntu 22.04/24.04 or Debian 11/12 (auto-install)
  - Other distros: Manual Sysbox installation required
  - systemd-based init system
  - Docker Engine installed
  - Internet access to download Sysbox
  - jq, ripgrep (rg), and wget installed (will install if missing)

Requirements (WSL2):
  - Ubuntu or Debian WSL2 distribution (WSL1 not supported)
  - systemd enabled ([boot] systemd=true in /etc/wsl.conf)
  - Docker Engine installed (standalone, not Docker Desktop integration)
  - Internet access to download Sysbox
  - jq, ripgrep (rg), and wget installed (will install if missing)

Requirements (macOS):
  - Homebrew installed
  - Internet access to download Lima and Ubuntu image
  - Disk space for Lima VM (~10GB)
  - Works on both Intel and Apple Silicon Macs

Security Notes:
  - sysbox-runc IS the default runtime for the isolated daemon
  - Does NOT modify Docker Desktop, system Docker, or /etc/docker/
  - Docker Desktop remains completely unchanged (CRITICAL)
  - Creates 'containai-docker' context pointing to isolated daemon
  - All platforms use completely separate socket for isolation (host)
  - Inside a ContainAI container, setup uses the default Docker daemon (no inner containai-docker daemon)

Lima VM Management (macOS):
  limactl start containai-docker    Start the VM
  limactl stop containai-docker     Stop the VM
  limactl shell containai-docker    Shell into the VM
  limactl list                      Show VM status

Isolated Docker (Linux/WSL2):
  Socket:  /var/run/containai-docker.sock
  Config:  /etc/containai/docker/daemon.json
  Data:    /var/lib/containai-docker/
  Service: containai-docker.service
  Context: containai-docker

  Usage after setup:
    docker --context containai-docker info
    docker --context containai-docker run hello-world

Examples:
  cai setup                    Configure isolation (auto-detects platform)
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
# Validation checks:
# 1. Context exists and endpoint matches expected socket
# 2. Engine reachable: docker --context <context> info
# 3. sysbox-runc is available: Check .Runtimes contains sysbox-runc
#    Note: On Linux/WSL2, sysbox-runc IS the default runtime (isolated daemon)
#          On macOS, sysbox-runc is NOT default (Lima VM setup)
# 4. User namespace enabled: Run container and check uid_map
# 5. Test container starts: docker run alpine:3.20 echo "..."
_cai_secure_engine_validate() {
    local verbose="false"

    # Parse arguments (same pattern as _cai_setup)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose | -v)
                verbose="true"
                shift
                ;;
            --help | -h)
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

    printf '\n'
    _cai_info "Secure Engine Validation"
    _cai_info "========================"
    printf '\n'

    # Detect platform for expected context and socket path
    # All platforms now use containai-docker context (Linux/WSL2 use isolated daemon, macOS uses Lima VM)
    local platform context_name expected_socket sysbox_is_default
    local in_container="false"
    platform=$(_cai_detect_platform)
    if _cai_is_container; then
        in_container="true"
        context_name="default"
        expected_socket=""
        sysbox_is_default="true"
    else
        case "$platform" in
            wsl)
                context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"
                expected_socket="unix://$_CAI_CONTAINAI_DOCKER_SOCKET"
                sysbox_is_default="true"
                ;;
            linux)
                context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"
                expected_socket="unix://$_CAI_CONTAINAI_DOCKER_SOCKET"
                sysbox_is_default="true"
                ;;
            macos)
                context_name="$_CAI_CONTAINAI_DOCKER_CONTEXT"
                expected_socket="unix://$_CAI_LIMA_SOCKET_PATH"
                sysbox_is_default="false"
                ;;
            *)
                _cai_error "Unknown platform: $platform"
                return 1
                ;;
        esac
    fi

    # Validation 1: Context exists AND endpoint matches expected socket
    _cai_step "Check 1: Context exists with correct endpoint"
    local actual_endpoint
    if ! docker context inspect "$context_name" >/dev/null 2>&1; then
        printf '%s\n' "[FAIL] Context '$context_name' not found"
        _cai_error "  Remediation: Run 'cai setup' to create the context"
        failed=1
    else
        actual_endpoint=$(docker context inspect "$context_name" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)
        if [[ "$in_container" == "true" ]]; then
            if [[ "$actual_endpoint" == unix://* ]]; then
                local socket_path="${actual_endpoint#unix://}"
                if [[ -S "$socket_path" ]]; then
                    printf '%s\n' "[PASS] Context '$context_name' exists with valid Unix socket"
                    if [[ "$verbose" == "true" ]]; then
                        _cai_info "  Endpoint: $actual_endpoint"
                    fi
                else
                    printf '%s\n' "[FAIL] Context '$context_name' socket not found"
                    _cai_error "  Endpoint: $actual_endpoint"
                    _cai_error "  Remediation: Ensure Docker daemon is running inside the container"
                    failed=1
                fi
            else
                printf '%s\n' "[FAIL] Context '$context_name' is not a Unix socket"
                _cai_error "  Endpoint: $actual_endpoint"
                _cai_error "  Remediation: Use the default Docker daemon inside the container"
                failed=1
            fi
        else
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
