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
#   _cai_update_macos_packages()      - Run apt update/upgrade in Lima VM
#   _cai_update_macos_recreate_vm()   - Recreate Lima VM (delete and create fresh)
#   _cai_update_systemd_unit()        - Update systemd unit if template changed
#   _cai_update_docker_context()      - Update Docker context if socket changed
#   _cai_update_check()               - Rate-limited check for dockerd bundle updates
#   _cai_update_dockerd_bundle()      - Update dockerd bundle to latest version
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
#   - Requires lib/config.sh for _containai_find_config
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
  --lima-recreate   Force Lima VM recreation (macOS only; bypasses hash check)
  --verbose, -v     Show verbose output
  -h, --help        Show this help message

What Gets Updated:

  Linux/WSL2:
    - Systemd unit file (if template changed)
    - Docker service restart
    - Docker context verification
    - Dockerd bundle version (with prompts unless --force)
    - Legacy path cleanup

  macOS Lima:
    - If template unchanged: apt update/upgrade in VM (non-destructive)
    - If template changed: VM deletion and recreation (with confirmation)
    - Docker context verification
    - Installation verification

Notes:
  - Template changes are detected by comparing SHA-256 hashes
  - VM recreation only occurs when template changes or --lima-recreate is used
  - VM recreation will stop all running containers in the VM
  - User is warned before destructive VM operations (unless --force)
  - CAI_YES=1 auto-confirms prompts for scripted usage
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
# Dockerd Bundle Update Check
# ==============================================================================

# State file for rate-limiting update checks
_CAI_UPDATE_CHECK_STATE_FILE="${HOME}/.cache/containai/update-check"

# Default check interval
_CAI_UPDATE_CHECK_DEFAULT_INTERVAL="daily"

# Convert interval string to seconds
# Arguments: $1 = interval (hourly, daily, weekly, never)
# Outputs: seconds (0 for never)
# Returns: 0
_cai_update_check_interval_seconds() {
    local interval="${1:-daily}"
    case "$interval" in
        hourly) printf '%s' "3600" ;;
        daily)  printf '%s' "86400" ;;
        weekly) printf '%s' "604800" ;;
        never)  printf '%s' "0" ;;
        *)      printf '%s' "86400" ;;  # Default to daily for invalid values
    esac
}

# Get the configured update check interval
# Reads from config file or env var, returns interval string
# Returns: 0=success
# Outputs: interval string (hourly, daily, weekly, never)
_cai_update_check_get_interval() {
    # 1. Env var override takes precedence
    if [[ -n "${CAI_UPDATE_CHECK_INTERVAL:-}" ]]; then
        printf '%s' "$CAI_UPDATE_CHECK_INTERVAL"
        return 0
    fi

    # 2. Try to read from config file
    # Use _containai_find_config with PWD, fallback to XDG config
    local config_file script_dir
    config_file=$(_containai_find_config "$PWD") || config_file=""

    if [[ -n "$config_file" ]] && [[ -f "$config_file" ]]; then
        # Check if Python is available for TOML parsing
        if command -v python3 >/dev/null 2>&1; then
            # Determine script directory (where parse-toml.py lives)
            if script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"; then
                local interval
                # Parse update.check_interval from config
                interval=$(python3 "$script_dir/parse-toml.py" --file "$config_file" --key "update.check_interval" 2>/dev/null) || interval=""
                if [[ -n "$interval" ]]; then
                    printf '%s' "$interval"
                    return 0
                fi
            fi
        fi
    fi

    # 3. Default to daily
    printf '%s' "$_CAI_UPDATE_CHECK_DEFAULT_INTERVAL"
}

# Check if update check should run based on rate limiting
# Uses file mtime for rate limiting
# Returns: 0=should check, 1=skip (interval not elapsed)
_cai_update_check_should_run() {
    local interval interval_secs
    interval=$(_cai_update_check_get_interval)
    interval_secs=$(_cai_update_check_interval_seconds "$interval")

    # never = skip all checks
    if [[ "$interval_secs" -eq 0 ]]; then
        return 1
    fi

    # Create cache dir if needed
    local cache_dir
    cache_dir=$(dirname "$_CAI_UPDATE_CHECK_STATE_FILE")
    if [[ ! -d "$cache_dir" ]]; then
        mkdir -p "$cache_dir" 2>/dev/null || return 1
    fi

    # If state file doesn't exist, should check
    if [[ ! -f "$_CAI_UPDATE_CHECK_STATE_FILE" ]]; then
        return 0
    fi

    # Compare mtime to current time
    local file_mtime current_time elapsed
    file_mtime=$(stat -c %Y "$_CAI_UPDATE_CHECK_STATE_FILE" 2>/dev/null) || file_mtime=0
    current_time=$(date +%s)
    elapsed=$((current_time - file_mtime))

    if [[ $elapsed -ge $interval_secs ]]; then
        return 0  # Interval elapsed, should check
    fi

    return 1  # Interval not elapsed, skip
}

# Touch state file and optionally write status
# Arguments: $1 = status (ok, network_error, parse_error)
_cai_update_check_touch_state() {
    local status="${1:-ok}"
    local cache_dir
    cache_dir=$(dirname "$_CAI_UPDATE_CHECK_STATE_FILE")

    # Create cache dir if needed
    mkdir -p "$cache_dir" 2>/dev/null || return 0

    # Write status atomically
    printf '%s' "$status" > "${_CAI_UPDATE_CHECK_STATE_FILE}.tmp" 2>/dev/null
    mv -f "${_CAI_UPDATE_CHECK_STATE_FILE}.tmp" "$_CAI_UPDATE_CHECK_STATE_FILE" 2>/dev/null || true
}

# Compare two semver versions
# Arguments: $1 = version A, $2 = version B
# Returns: 0 if A > B, 1 if A <= B
# Note: Uses sort -V which is available on Linux coreutils
_cai_version_is_greater() {
    local ver_a="${1:-}"
    local ver_b="${2:-}"

    # If either is empty, cannot compare
    if [[ -z "$ver_a" ]] || [[ -z "$ver_b" ]]; then
        return 1
    fi

    # If equal, A is not greater
    if [[ "$ver_a" == "$ver_b" ]]; then
        return 1
    fi

    # Use sort -V: if ver_a comes last when sorted, it's the greater version
    local highest
    highest=$(printf '%s\n%s\n' "$ver_a" "$ver_b" | sort -V | tail -1)
    if [[ "$highest" == "$ver_a" ]]; then
        return 0  # A > B
    fi
    return 1  # A <= B
}

# Get latest Docker version from the download index
# Arguments: $1 = architecture (x86_64, aarch64)
# Outputs: version string (e.g., "27.4.0") on stdout
# Returns: 0=success, 1=network error, 2=parse error
_cai_update_check_get_latest_version() {
    local arch="${1:-x86_64}"
    local index_url="https://download.docker.com/linux/static/stable/${arch}/"
    local index_html latest_version

    # Fetch index with short timeout (5s connect, 10s total - non-blocking)
    if ! index_html=$(_cai_timeout 10 wget -qO- --connect-timeout=5 "$index_url" 2>/dev/null); then
        return 1  # Network error
    fi

    # Parse HTML for docker-X.Y.Z.tgz links and extract latest version
    latest_version=$(printf '%s' "$index_html" | \
        grep -oE 'href="docker-[0-9]+\.[0-9]+\.[0-9]+\.tgz"' | \
        grep -v rootless | \
        sed 's/href="docker-//; s/\.tgz"//' | \
        sort -t. -k1,1n -k2,2n -k3,3n | \
        tail -1)

    if [[ -z "$latest_version" ]]; then
        return 2  # Parse error
    fi

    printf '%s' "$latest_version"
    return 0
}

# Rate-limited update check for dockerd bundle
# Called before every cai command (when wired in)
# Non-blocking: short timeouts, doesn't fail the command
# Arguments: none
# Returns: 0 always (never blocks command execution)
# Side effects: May print yellow warning if update available
_cai_update_check() {
    # Platform guard: skip on macOS (uses Lima VM)
    if _cai_is_macos; then
        return 0
    fi

    # Skip if bundle not installed
    if ! _cai_dockerd_bundle_installed; then
        return 0
    fi

    # Rate limit check
    if ! _cai_update_check_should_run; then
        return 0
    fi

    # Get architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *)       return 0 ;;  # Unsupported architecture, skip
    esac

    # Get latest version (non-blocking)
    local latest_version rc
    latest_version=$(_cai_update_check_get_latest_version "$arch") && rc=0 || rc=$?

    case $rc in
        0)
            # Success - compare versions
            local installed_version
            installed_version=$(_cai_dockerd_bundle_version) || installed_version=""

            # Only warn if latest is strictly greater than installed (not for downgrades)
            if [[ -n "$installed_version" ]] && _cai_version_is_greater "$latest_version" "$installed_version"; then
                # Update available - print yellow warning
                printf '\033[33m[WARN] Dockerd bundle update available: %s -> %s\033[0m\n' "$installed_version" "$latest_version" >&2
                printf '\033[33m       Updating will stop running containers.\033[0m\n' >&2
                printf '\033[33m       Run: cai update\033[0m\n' >&2
            fi

            _cai_update_check_touch_state "ok"
            ;;
        1)
            # Network error - touch state to avoid immediate re-check
            _cai_update_check_touch_state "network_error"
            ;;
        2)
            # Parse error
            _cai_update_check_touch_state "parse_error"
            ;;
    esac

    return 0  # Never fail the command
}

# Update dockerd bundle to latest version
# Arguments: $1 = force flag ("true" to skip confirmation)
#            $2 = dry_run flag ("true" to simulate)
#            $3 = verbose flag ("true" for verbose output)
# Returns: 0=success (updated or already current), 1=failure
_cai_update_dockerd_bundle() {
    local force="${1:-false}"
    local dry_run="${2:-false}"
    local verbose="${3:-false}"

    # Platform guard: skip on macOS (uses Lima VM)
    if _cai_is_macos; then
        if [[ "$verbose" == "true" ]]; then
            _cai_info "Skipping dockerd bundle update on macOS (uses Lima VM)"
        fi
        return 0
    fi

    # Skip if bundle not installed (user should run setup first)
    if ! _cai_dockerd_bundle_installed; then
        _cai_info "Dockerd bundle not installed - run 'cai setup' first"
        return 0
    fi

    _cai_step "Checking for dockerd bundle updates"

    # Get architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *)
            _cai_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    # Get latest version
    local latest_version rc
    latest_version=$(_cai_update_check_get_latest_version "$arch") && rc=0 || rc=$?

    if [[ $rc -ne 0 ]]; then
        _cai_error "Failed to check for latest Docker version"
        if [[ $rc -eq 1 ]]; then
            _cai_error "  Network error - check connectivity"
        else
            _cai_error "  Could not parse Docker download index"
        fi
        return 1
    fi

    # Compare to installed version
    local installed_version
    installed_version=$(_cai_dockerd_bundle_version) || installed_version=""

    if [[ "$installed_version" == "$latest_version" ]]; then
        _cai_info "Dockerd bundle is current: $installed_version"
        return 0
    fi

    # Only update if latest is strictly greater than installed (not downgrades)
    if ! _cai_version_is_greater "$latest_version" "$installed_version"; then
        _cai_info "Installed version ($installed_version) is newer than index ($latest_version)"
        _cai_info "Skipping update (no downgrade)"
        return 0
    fi

    _cai_info "Update available: $installed_version -> $latest_version"

    # Dry-run handling
    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would download docker-${latest_version}.tgz"
        _cai_info "[DRY-RUN] Would extract to $_CAI_DOCKERD_BUNDLE_DIR/$latest_version/"
        _cai_info "[DRY-RUN] Would update symlinks in $_CAI_DOCKERD_BIN_DIR/"
        _cai_info "[DRY-RUN] Would restart $_CAI_CONTAINAI_DOCKER_SERVICE"
        _cai_info "[DRY-RUN] Would cleanup old versions (keeping current + previous)"
        return 0
    fi

    # Prompt for confirmation (unless --force, use shared helper with CAI_YES support)
    if [[ "$force" != "true" ]]; then
        printf '\n'
        _cai_warn "Updating dockerd will stop running containers."
        if ! _cai_prompt_confirm "Continue?"; then
            printf '%s\n' "Cancelled."
            return 0
        fi
    fi

    # Download and install
    local download_url="https://download.docker.com/linux/static/stable/${arch}/docker-${latest_version}.tgz"
    local install_rc

    if [[ "$verbose" == "true" ]]; then
        _cai_info "Download URL: $download_url"
    fi

    # Perform download and installation in subshell for cleanup
    (
        set -e
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' EXIT

        printf '%s\n' "[STEP] Downloading Docker $latest_version"
        if ! wget -q --show-progress --connect-timeout=5 --timeout=120 -O "$tmpdir/docker.tgz" "$download_url"; then
            printf '%s\n' "[ERROR] Failed to download Docker bundle" >&2
            exit 1
        fi

        printf '%s\n' "[STEP] Extracting Docker bundle"
        if ! tar -xzf "$tmpdir/docker.tgz" -C "$tmpdir"; then
            printf '%s\n' "[ERROR] Failed to extract Docker bundle" >&2
            exit 1
        fi

        # Verify extraction produced expected files
        if [[ ! -f "$tmpdir/docker/dockerd" ]]; then
            printf '%s\n' "[ERROR] Extracted archive missing dockerd binary" >&2
            exit 1
        fi

        printf '%s\n' "[STEP] Installing to $_CAI_DOCKERD_BUNDLE_DIR/$latest_version/"

        # Create target directory
        sudo mkdir -p "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version"

        # Move binaries from docker/ subdir to versioned directory
        sudo mv "$tmpdir/docker/"* "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version/"

        # SECURITY: Set proper ownership and permissions
        printf '%s\n' "[STEP] Setting secure ownership and permissions"
        sudo chown -R root:root "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version"
        sudo chmod -R u+rx,go+rx,go-w "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version"

        printf '%s\n' "[STEP] Validating required binaries"

        # Required binaries must all be present
        local bin missing_binaries=""
        for bin in $_CAI_DOCKERD_BUNDLE_REQUIRED_BINARIES; do
            if [[ ! -f "$_CAI_DOCKERD_BUNDLE_DIR/$latest_version/$bin" ]]; then
                missing_binaries="$missing_binaries $bin"
            fi
        done

        if [[ -n "$missing_binaries" ]]; then
            printf '%s\n' "[ERROR] Docker bundle missing required binaries:$missing_binaries" >&2
            exit 1
        fi

        printf '%s\n' "[STEP] Updating symlinks in $_CAI_DOCKERD_BIN_DIR/"

        # Update symlinks atomically using ln -sfn
        for bin in $_CAI_DOCKERD_BUNDLE_REQUIRED_BINARIES; do
            sudo ln -sfn "../docker/$latest_version/$bin" "$_CAI_DOCKERD_BIN_DIR/$bin"
        done

        # Write version file atomically
        printf '%s\n' "[STEP] Writing version to $_CAI_DOCKERD_VERSION_FILE"
        local version_tmp="${_CAI_DOCKERD_VERSION_FILE}.tmp"
        printf '%s' "$latest_version" | sudo tee "$version_tmp" >/dev/null
        sudo mv -f "$version_tmp" "$_CAI_DOCKERD_VERSION_FILE"

        exit 0
    ) && install_rc=0 || install_rc=$?

    if [[ $install_rc -ne 0 ]]; then
        _cai_error "Failed to install Docker bundle"
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

    _cai_ok "Dockerd bundle updated: $installed_version -> $latest_version"

    # Cleanup old versions (keep current + previous only)
    _cai_step "Cleaning up old versions"
    local version_dirs version_count
    # shellcheck disable=SC2012 # ls is fine here - version dirs are always alphanumeric
    version_dirs=$(ls -1d "$_CAI_DOCKERD_BUNDLE_DIR"/*/ 2>/dev/null | sort -V) || version_dirs=""
    version_count=$(printf '%s\n' "$version_dirs" | grep -c .) || version_count=0

    if [[ $version_count -gt 2 ]]; then
        # Remove all but the last 2 versions
        local to_remove
        to_remove=$(printf '%s\n' "$version_dirs" | head -n $((version_count - 2)))
        local dir
        while IFS= read -r dir; do
            if [[ -n "$dir" ]] && [[ -d "$dir" ]]; then
                if [[ "$verbose" == "true" ]]; then
                    _cai_info "Removing old version: $dir"
                fi
                sudo rm -rf "$dir"
            fi
        done <<< "$to_remove"
        _cai_info "Cleaned up $((version_count - 2)) old version(s)"
    fi

    return 0
}

# ==============================================================================
# Linux/WSL2 Update
# ==============================================================================

# Update Linux/WSL2 installation
# Arguments: $1 = dry_run ("true" to simulate)
#            $2 = verbose ("true" for verbose output)
#            $3 = force ("true" to skip confirmation prompts)
# Returns: 0=success, 1=failure
_cai_update_linux_wsl2() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local force="${3:-false}"
    local overall_status=0

    _cai_info "Updating Linux/WSL2 installation"

    # Step 1: Clean up legacy paths
    if ! _cai_cleanup_legacy_paths "$dry_run" "$verbose"; then
        _cai_warn "Legacy cleanup had issues (continuing anyway)"
    fi

    # Step 2: Check dockerd bundle exists (required for unit update)
    # The systemd unit uses /opt/containai/bin/dockerd, so bundle must exist
    # If not installed, user needs to run 'cai setup' first
    # Upgrades are handled in Step 5 after context/unit updates
    _cai_step "Checking dockerd bundle"
    if ! _cai_dockerd_bundle_installed; then
        _cai_error "Dockerd bundle not installed"
        _cai_error "  The systemd unit requires /opt/containai/bin/dockerd"
        _cai_error "  Run 'cai setup' to install ContainAI"
        return 1
    fi
    _cai_info "Dockerd bundle installed"

    # Step 3: Check/update systemd unit
    if ! _cai_update_systemd_unit "$dry_run" "$verbose"; then
        overall_status=1
    fi

    # Step 4: Check/update Docker context
    if ! _cai_update_docker_context "$dry_run"; then
        overall_status=1
    fi

    # Step 5: Check/update dockerd bundle version (with prompts)
    # This is called after context/unit updates per spec
    if ! _cai_update_dockerd_bundle "$force" "$dry_run" "$verbose"; then
        _cai_warn "Dockerd bundle update had issues (continuing anyway)"
        # Don't fail overall - bundle might already be at latest version
    fi

    # Step 6: Verify installation
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

# Run package updates in Lima VM (apt update/upgrade)
# This is the non-destructive update path when template hasn't changed
# Arguments: $1 = dry_run ("true" to simulate)
#            $2 = verbose ("true" for verbose output)
# Returns: 0=success, 1=failure
_cai_update_macos_packages() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    _cai_step "Updating packages in Lima VM"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would run: limactl shell $_CAI_LIMA_VM_NAME -- sudo apt-get update"
        _cai_info "[DRY-RUN] Would run: limactl shell $_CAI_LIMA_VM_NAME -- sudo apt-get upgrade -y"
        return 0
    fi

    # Run apt update
    _cai_step "Running apt update in VM"
    if ! limactl shell "$_CAI_LIMA_VM_NAME" -- sudo apt-get update; then
        _cai_error "apt update failed in VM"
        return 1
    fi

    # Run apt upgrade
    _cai_step "Running apt upgrade in VM"
    if ! limactl shell "$_CAI_LIMA_VM_NAME" -- sudo apt-get upgrade -y; then
        _cai_error "apt upgrade failed in VM"
        return 1
    fi

    _cai_ok "Packages updated in Lima VM"
    return 0
}

# Recreate Lima VM (delete and create fresh)
# Internal helper for _cai_update_macos
# Arguments: $1 = dry_run, $2 = verbose
# Returns: 0=success, 1=failure
_cai_update_macos_recreate_vm() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"

    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[DRY-RUN] Would stop Lima VM: $_CAI_LIMA_VM_NAME"
        _cai_info "[DRY-RUN] Would delete Lima VM: $_CAI_LIMA_VM_NAME"
        _cai_info "[DRY-RUN] Would recreate Lima VM with latest template"
        return 0
    fi

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

    # Recreate VM (this also saves the hash after successful creation)
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
    return 0
}

# Update macOS Lima installation
# Arguments: $1 = dry_run ("true" to simulate)
#            $2 = verbose ("true" for verbose output)
#            $3 = force ("true" to skip confirmation)
#            $4 = lima_recreate ("true" to force VM recreation)
# Returns: 0=success, 1=failure, 130=cancelled by user
_cai_update_macos() {
    local dry_run="${1:-false}"
    local verbose="${2:-false}"
    local force="${3:-false}"
    local lima_recreate="${4:-false}"
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

    # Step 2: Determine if VM needs recreation (hash-based change detection)
    local current_hash stored_hash hash_file need_recreate="false"
    hash_file="$HOME/.config/containai/lima-template.hash"

    # Get current template hash
    if ! current_hash=$(_cai_lima_template_hash); then
        _cai_error "Failed to compute template hash"
        return 1
    fi

    # Get stored hash (if exists)
    stored_hash=$(cat "$hash_file" 2>/dev/null || echo "")

    # Decision: recreate or just update packages?
    # - --lima-recreate flag forces recreation
    # - Different hash -> prompt for recreation
    # - Missing hash file -> prompt for recreation (first update after migration)
    # - Same hash -> just update packages
    if [[ "$lima_recreate" == "true" ]]; then
        _cai_info "Force recreate requested (--lima-recreate)"
        need_recreate="true"
    elif [[ "$current_hash" == "$stored_hash" ]]; then
        _cai_info "Lima template unchanged, updating packages..."
        if ! _cai_update_macos_packages "$dry_run" "$verbose"; then
            _cai_warn "Package update had issues"
            overall_status=1
        fi
        need_recreate="false"
    else
        # Template changed or no stored hash
        if [[ -z "$stored_hash" ]]; then
            _cai_warn "Lima template hash not found (first update after install)"
        else
            _cai_warn "Lima template changed (was: $stored_hash, now: $current_hash)"
        fi
        need_recreate="true"
    fi

    # Step 3: Handle VM recreation if needed
    if [[ "$need_recreate" == "true" ]]; then
        _cai_step "Recreating Lima VM with latest template"

        # Warn about container loss (use shared helper with CAI_YES support)
        if [[ "$dry_run" != "true" ]]; then
            printf '\n'
            _cai_warn "This will DELETE the Lima VM and recreate it."
            _cai_warn "All running containers in the VM will be LOST."
            printf '\n'

            if [[ "$force" != "true" ]]; then
                if ! _cai_prompt_confirm "Recreate Lima VM?"; then
                    _cai_info "Update cancelled"
                    return 0
                fi
            fi
        fi

        if ! _cai_update_macos_recreate_vm "$dry_run" "$verbose"; then
            return 1
        fi
    fi

    # Step 4: Check/update Docker context
    if ! _cai_update_docker_context "$dry_run"; then
        overall_status=1
    fi

    # Step 5: Verify installation BEFORE legacy cleanup
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

    # Step 6: Clean up legacy Lima VM (only if verification passed)
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
                # Force Lima VM recreation even if template hasn't changed
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
        _cai_update_macos "$dry_run" "$verbose" "$force" "$lima_recreate"
        overall_status=$?
    else
        # Linux or WSL2
        _cai_update_linux_wsl2 "$dry_run" "$verbose" "$force"
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
