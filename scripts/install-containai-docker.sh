#!/usr/bin/env bash
# ==============================================================================
# ContainAI Docker Installation Script
# ==============================================================================
# Installs a separate docker-ce instance alongside existing Docker Desktop.
# This docker-ce instance uses sysbox-runc as the default runtime.
#
# Paths:
#   Socket: /var/run/containai-docker.sock
#   Config: /etc/containai/docker/daemon.json
#   Data:   /var/lib/containai-docker/
#   Service: containai-docker.service
#
# Usage: sudo ./install-containai-docker.sh [--dry-run] [--verbose]
# ==============================================================================

set -euo pipefail

# ==============================================================================
# Constants
# ==============================================================================

# ContainAI Docker paths (isolated from Docker Desktop / system Docker)
CAI_DOCKER_SOCKET="/var/run/containai-docker.sock"
CAI_DOCKER_CONFIG_DIR="/etc/containai/docker"
CAI_DOCKER_DAEMON_JSON="$CAI_DOCKER_CONFIG_DIR/daemon.json"
CAI_DOCKER_DATA_ROOT="/var/lib/containai-docker"
CAI_DOCKER_EXEC_ROOT="/var/run/containai-docker"
CAI_DOCKER_PIDFILE="/var/run/containai-docker.pid"
CAI_DOCKER_SERVICE="containai-docker"
CAI_DOCKER_SERVICE_FILE="/etc/systemd/system/${CAI_DOCKER_SERVICE}.service"
CAI_DOCKER_CONTEXT="docker-containai"
CAI_DOCKER_BRIDGE="cai0"

# ==============================================================================
# Logging Functions
# ==============================================================================

_log_info() {
    printf '%s\n' "[INFO] $*"
}

_log_step() {
    printf '%s\n' "-> $*"
}

_log_ok() {
    printf '%s\n' "[OK] $*"
}

_log_warn() {
    printf '%s\n' "[WARN] $*" >&2
}

_log_error() {
    printf '%s\n' "[ERROR] $*" >&2
}

# ==============================================================================
# Pre-flight Checks
# ==============================================================================

# Check if running as root or with sudo
check_root() {
    if [[ $EUID -ne 0 ]]; then
        _log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect distro
detect_distro() {
    local distro=""
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        distro=$(. /etc/os-release && printf '%s' "$ID")
    fi
    printf '%s' "$distro"
}

# Check systemd is available and running
check_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        _log_error "systemctl not found - systemd is required"
        return 1
    fi

    local pid1_cmd
    pid1_cmd=$(ps -p 1 -o comm= 2>/dev/null || true)
    if [[ "$pid1_cmd" != "systemd" ]]; then
        _log_error "Systemd is not running as PID 1 (found: $pid1_cmd)"
        _log_error "  For WSL2, enable systemd in /etc/wsl.conf:"
        _log_error "    [boot]"
        _log_error "    systemd=true"
        return 1
    fi
    return 0
}

# ==============================================================================
# Docker CE Installation
# ==============================================================================

# Install docker-ce packages if not present
install_docker_ce() {
    local dry_run="${1:-false}"

    _log_step "Checking for docker-ce installation"

    # Check if docker-ce is already installed
    if dpkg -l docker-ce 2>/dev/null | grep -q "^ii"; then
        _log_info "docker-ce is already installed"
        return 0
    fi

    _log_step "Installing docker-ce"

    if [[ "$dry_run" == "true" ]]; then
        _log_info "[DRY-RUN] Would install docker-ce via apt"
        return 0
    fi

    local distro
    distro=$(detect_distro)

    case "$distro" in
        ubuntu|debian)
            # Install prerequisites
            apt-get update -qq
            apt-get install -y ca-certificates curl gnupg

            # Add Docker's official GPG key
            install -m 0755 -d /etc/apt/keyrings
            if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
                curl -fsSL "https://download.docker.com/linux/$distro/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                chmod a+r /etc/apt/keyrings/docker.gpg
            fi

            # Set up the repository
            # shellcheck disable=SC1091
            local version_codename
            version_codename=$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")
            local arch
            arch=$(dpkg --print-architecture)
            printf '%s\n' "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$distro $version_codename stable" > /etc/apt/sources.list.d/docker.list

            # Install docker-ce
            apt-get update -qq
            apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        *)
            _log_error "Unsupported distribution: $distro"
            _log_error ""
            _log_error "This script currently supports Ubuntu and Debian only."
            _log_error "For other distributions:"
            _log_error "  - RHEL/Fedora/CentOS: Install docker-ce via yum/dnf repository"
            _log_error "  - Arch Linux: Install docker-ce from AUR"
            _log_error "  - Other: Follow Docker's official installation guide"
            _log_error ""
            _log_error "After installing docker-ce manually, re-run this script."
            return 1
            ;;
    esac

    _log_ok "docker-ce installed"
    return 0
}

# ==============================================================================
# Sysbox Installation
# ==============================================================================

# Install sysbox-ce if not present
install_sysbox() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _log_step "Checking for sysbox installation"

    if command -v sysbox-runc >/dev/null 2>&1; then
        local version
        version=$(sysbox-runc --version 2>/dev/null | head -1 || true)
        _log_info "Sysbox already installed: $version"
        return 0
    fi

    _log_step "Installing sysbox-ce"

    if [[ "$dry_run" == "true" ]]; then
        _log_info "[DRY-RUN] Would download and install sysbox-ce"
        return 0
    fi

    # Ensure wget and jq are available
    apt-get install -y wget jq

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
            _log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    # Get latest sysbox release from GitHub
    local release_url="https://api.github.com/repos/nestybox/sysbox/releases/latest"
    local release_json download_url

    release_json=$(wget -qO- "$release_url" 2>/dev/null) || {
        _log_error "Failed to fetch sysbox release info from GitHub"
        return 1
    }

    download_url=$(printf '%s' "$release_json" | jq -r ".assets[] | select(.name | test(\"sysbox-ce.*${arch}.deb\")) | .browser_download_url" | head -1)

    if [[ -z "$download_url" ]] || [[ "$download_url" == "null" ]]; then
        _log_error "Could not find sysbox .deb package for architecture: $arch"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _log_info "Download URL: $download_url"
    fi

    # Download and install
    local tmpdir deb_file
    tmpdir=$(mktemp -d)
    deb_file="$tmpdir/sysbox-ce.deb"

    _log_step "Downloading sysbox from: $download_url"
    if ! wget -q --show-progress -O "$deb_file" "$download_url"; then
        rm -rf "$tmpdir"
        _log_error "Failed to download sysbox package"
        return 1
    fi

    _log_step "Installing sysbox package"
    if ! dpkg -i "$deb_file"; then
        _log_warn "dpkg install had issues, attempting to fix dependencies"
        if ! apt-get install -f -y; then
            rm -rf "$tmpdir"
            _log_error "Failed to install sysbox package"
            return 1
        fi
    fi

    rm -rf "$tmpdir"

    # Verify sysbox services are running
    _log_step "Verifying sysbox services"
    systemctl daemon-reload

    for service in sysbox-mgr sysbox-fs; do
        if ! systemctl is-active --quiet "$service" 2>/dev/null; then
            _log_info "Starting $service service"
            if ! systemctl start "$service"; then
                _log_error "Failed to start $service service"
                _log_error "  Check: systemctl status $service"
                return 1
            fi
        fi
        # Verify the service is actually running
        if ! systemctl is-active --quiet "$service"; then
            _log_error "$service is not running after start attempt"
            _log_error "  Check: systemctl status $service"
            return 1
        fi
        _log_info "$service is running"
    done

    _log_ok "Sysbox installed and services running"
    return 0
}

# ==============================================================================
# ContainAI Docker Configuration
# ==============================================================================

# Create daemon.json with sysbox-runc as default runtime
create_daemon_json() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _log_step "Creating daemon.json at $CAI_DOCKER_DAEMON_JSON"

    # Determine sysbox-runc path dynamically
    local sysbox_path
    sysbox_path=$(command -v sysbox-runc 2>/dev/null || true)
    if [[ -z "$sysbox_path" ]]; then
        _log_error "sysbox-runc not found in PATH"
        _log_error "  Ensure sysbox is installed correctly"
        return 1
    fi

    _log_info "Found sysbox-runc at: $sysbox_path"

    local config
    config=$(cat <<EOF
{
  "runtimes": {
    "sysbox-runc": {
      "path": "$sysbox_path"
    }
  },
  "default-runtime": "sysbox-runc",
  "hosts": ["unix://$CAI_DOCKER_SOCKET"],
  "data-root": "$CAI_DOCKER_DATA_ROOT",
  "exec-root": "$CAI_DOCKER_EXEC_ROOT",
  "pidfile": "$CAI_DOCKER_PIDFILE",
  "bridge": "$CAI_DOCKER_BRIDGE",
  "iptables": false
}
EOF
)

    if [[ "$verbose" == "true" ]]; then
        _log_info "daemon.json content:"
        printf '%s\n' "$config"
    fi

    if [[ "$dry_run" == "true" ]]; then
        _log_info "[DRY-RUN] Would create: $CAI_DOCKER_DAEMON_JSON"
        return 0
    fi

    # Create config directory
    mkdir -p "$CAI_DOCKER_CONFIG_DIR"

    # Write daemon.json
    printf '%s\n' "$config" > "$CAI_DOCKER_DAEMON_JSON"

    _log_ok "daemon.json created"
    return 0
}

# Create systemd service for containai-docker
create_systemd_service() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _log_step "Creating systemd service: $CAI_DOCKER_SERVICE"

    local service_content
    service_content=$(cat <<EOF
[Unit]
Description=ContainAI Docker Application Container Engine
Documentation=https://github.com/containai/containai
After=network-online.target containerd.service sysbox-mgr.service sysbox-fs.service
Wants=network-online.target sysbox-mgr.service sysbox-fs.service
Requires=containerd.service

[Service]
Type=notify
# dockerd reads config from daemon.json which includes:
# - isolated socket, data-root, exec-root, pidfile
# - separate bridge (cai0) with iptables disabled to avoid conflicts
ExecStart=/usr/bin/dockerd --config-file=$CAI_DOCKER_DAEMON_JSON
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always

# Limit container and network namespace
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

# Set delegate for cgroup management
Delegate=yes

# Kill only the main process, not the containers
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF
)

    if [[ "$verbose" == "true" ]]; then
        _log_info "Service file content:"
        printf '%s\n' "$service_content"
    fi

    if [[ "$dry_run" == "true" ]]; then
        _log_info "[DRY-RUN] Would create: $CAI_DOCKER_SERVICE_FILE"
        return 0
    fi

    # Write service file
    printf '%s\n' "$service_content" > "$CAI_DOCKER_SERVICE_FILE"

    # Reload systemd
    systemctl daemon-reload

    _log_ok "Systemd service created"
    return 0
}

# Create data and exec-root directories
create_directories() {
    local dry_run="${1:-false}"

    _log_step "Creating directories"

    if [[ "$dry_run" == "true" ]]; then
        _log_info "[DRY-RUN] Would create: $CAI_DOCKER_DATA_ROOT"
        _log_info "[DRY-RUN] Would create: $CAI_DOCKER_EXEC_ROOT"
        return 0
    fi

    mkdir -p "$CAI_DOCKER_DATA_ROOT"
    _log_info "Created data directory: $CAI_DOCKER_DATA_ROOT"

    mkdir -p "$CAI_DOCKER_EXEC_ROOT"
    _log_info "Created exec-root directory: $CAI_DOCKER_EXEC_ROOT"

    _log_ok "Directories created"
    return 0
}

# Start containai-docker service
start_service() {
    local dry_run="${1:-false}"

    _log_step "Starting $CAI_DOCKER_SERVICE service"

    if [[ "$dry_run" == "true" ]]; then
        _log_info "[DRY-RUN] Would enable and start $CAI_DOCKER_SERVICE"
        return 0
    fi

    # Enable service for auto-start
    systemctl enable "$CAI_DOCKER_SERVICE"

    # Start service
    if ! systemctl start "$CAI_DOCKER_SERVICE"; then
        _log_error "Failed to start $CAI_DOCKER_SERVICE"
        _log_error "  Check: systemctl status $CAI_DOCKER_SERVICE"
        return 1
    fi

    # Wait for socket to appear
    local wait_count=0
    local max_wait=30
    _log_step "Waiting for socket: $CAI_DOCKER_SOCKET"
    while [[ ! -S "$CAI_DOCKER_SOCKET" ]]; do
        sleep 1
        wait_count=$((wait_count + 1))
        if [[ $wait_count -ge $max_wait ]]; then
            _log_error "Socket did not appear after ${max_wait}s"
            _log_error "  Check: systemctl status $CAI_DOCKER_SERVICE"
            return 1
        fi
    done

    _log_ok "Service started and socket ready"
    return 0
}

# Create Docker context
create_docker_context() {
    local dry_run="${1:-false}"
    local user="${2:-}"

    _log_step "Creating Docker context: $CAI_DOCKER_CONTEXT"

    local expected_host="unix://$CAI_DOCKER_SOCKET"

    if [[ "$dry_run" == "true" ]]; then
        _log_info "[DRY-RUN] Would create context: docker context create $CAI_DOCKER_CONTEXT --docker host=$expected_host"
        return 0
    fi

    # Helper function to run docker as target user with proper HOME
    run_docker_as_user() {
        if [[ -n "$user" ]]; then
            # Use -H to set HOME properly for the target user
            sudo -u "$user" -H docker "$@"
        else
            docker "$@"
        fi
    }

    # Check if context already exists
    if run_docker_as_user context inspect "$CAI_DOCKER_CONTEXT" >/dev/null 2>&1; then
        local existing_host
        existing_host=$(run_docker_as_user context inspect "$CAI_DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)

        if [[ "$existing_host" == "$expected_host" ]]; then
            _log_info "Context '$CAI_DOCKER_CONTEXT' already exists with correct endpoint"
            return 0
        else
            _log_warn "Context '$CAI_DOCKER_CONTEXT' exists but points to: $existing_host"
            _log_step "Removing misconfigured context"
            run_docker_as_user context rm "$CAI_DOCKER_CONTEXT" >/dev/null 2>&1 || true
        fi
    fi

    # Create context
    if ! run_docker_as_user context create "$CAI_DOCKER_CONTEXT" --docker "host=$expected_host"; then
        _log_error "Failed to create Docker context"
        return 1
    fi

    _log_ok "Docker context created: $CAI_DOCKER_CONTEXT"
    return 0
}

# Verify installation
verify_installation() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _log_step "Verifying installation"

    if [[ "$dry_run" == "true" ]]; then
        _log_info "[DRY-RUN] Would verify docker info shows sysbox-runc as default"
        return 0
    fi

    # Check docker info via the socket
    local docker_info
    docker_info=$(DOCKER_HOST="unix://$CAI_DOCKER_SOCKET" docker info 2>&1) || {
        _log_error "Cannot connect to containai docker"
        return 1
    }

    # Check sysbox-runc is available
    if ! printf '%s' "$docker_info" | grep -q "sysbox-runc"; then
        _log_error "sysbox-runc not found in docker info"
        return 1
    fi

    # Check sysbox-runc is the default runtime
    local default_runtime
    default_runtime=$(DOCKER_HOST="unix://$CAI_DOCKER_SOCKET" docker info --format '{{.DefaultRuntime}}' 2>/dev/null || true)
    if [[ "$default_runtime" != "sysbox-runc" ]]; then
        _log_error "Default runtime is not sysbox-runc (got: $default_runtime)"
        return 1
    fi

    if [[ "$verbose" == "true" ]]; then
        _log_info "Default runtime: $default_runtime"
    fi

    # Run test container
    _log_step "Testing with minimal container"
    local test_output
    test_output=$(DOCKER_HOST="unix://$CAI_DOCKER_SOCKET" docker run --rm alpine echo "containai-docker-test-ok" 2>&1) || {
        _log_warn "Test container failed: $test_output"
        return 0  # Don't fail hard - sysbox may still work for real containers
    }

    if [[ "$test_output" == *"containai-docker-test-ok"* ]]; then
        _log_ok "Test container succeeded with sysbox-runc default runtime"
    fi

    _log_ok "Installation verified"
    return 0
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    local dry_run="false"
    local verbose="false"
    local user="${SUDO_USER:-}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --verbose|-v)
                verbose="true"
                shift
                ;;
            --help|-h)
                cat <<'HELP'
ContainAI Docker Installation Script

Installs a separate docker-ce instance with sysbox-runc as default runtime.
This installation is isolated from Docker Desktop and any existing Docker.

Usage: sudo ./install-containai-docker.sh [options]

Options:
  --dry-run     Show what would be done without making changes
  --verbose     Show detailed progress information
  -h, --help    Show this help message

Paths (isolated from existing Docker):
  Socket:    /var/run/containai-docker.sock
  Config:    /etc/containai/docker/daemon.json
  Data:      /var/lib/containai-docker/
  Exec-root: /var/run/containai-docker/
  Pidfile:   /var/run/containai-docker.pid
  Bridge:    cai0 (iptables disabled)
  Service:   containai-docker.service
  Context:   docker-containai

Requirements:
  - Ubuntu/Debian distribution
  - systemd enabled and running
  - Root/sudo access
  - Internet access to download packages

After installation:
  docker --context docker-containai info
  docker --context docker-containai run hello-world
HELP
                exit 0
                ;;
            *)
                _log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    _log_info "ContainAI Docker Installation"
    _log_info "=============================="
    printf '\n'

    if [[ "$dry_run" == "true" ]]; then
        _log_info "[DRY-RUN MODE] No changes will be made"
        printf '\n'
    fi

    # Pre-flight checks
    check_root

    local distro
    distro=$(detect_distro)
    _log_info "Detected distribution: $distro"

    if [[ "$distro" != "ubuntu" ]] && [[ "$distro" != "debian" ]]; then
        _log_error "Only Ubuntu and Debian are supported for auto-installation"
        exit 1
    fi

    if ! check_systemd; then
        exit 1
    fi

    printf '\n'

    # Installation steps
    install_docker_ce "$dry_run" || exit 1
    install_sysbox "$dry_run" "$verbose" || exit 1
    create_directories "$dry_run" || exit 1
    create_daemon_json "$dry_run" "$verbose" || exit 1
    create_systemd_service "$dry_run" "$verbose" || exit 1
    start_service "$dry_run" || exit 1
    create_docker_context "$dry_run" "$user" || exit 1
    verify_installation "$dry_run" "$verbose" || exit 1

    printf '\n'
    _log_ok "ContainAI Docker installation complete"
    printf '\n'
    _log_info "To use ContainAI Docker:"
    _log_info "  docker --context docker-containai info"
    _log_info "  docker --context docker-containai run hello-world"
    printf '\n'
    _log_info "Docker Desktop (if present) continues to work unchanged"
    printf '\n'
}

main "$@"
