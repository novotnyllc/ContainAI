#!/usr/bin/env bash
# ==============================================================================
# ContainAI SSH Key Management
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_setup_ssh_key()         - Generate dedicated SSH key for ContainAI
#   _cai_setup_ssh_config()      - Setup ~/.ssh/containai.d/ and Include directive
#   _cai_check_ssh_version()     - Check if OpenSSH supports Include directive
#   _cai_get_ssh_key_path()      - Return path to ContainAI SSH private key
#   _cai_get_ssh_pubkey_path()   - Return path to ContainAI SSH public key
#   _cai_get_ssh_config_dir()    - Return path to ContainAI SSH config directory
#   _cai_get_ssh_port_range()    - Get effective SSH port range (config or defaults)
#   _cai_find_available_port()   - Find first available port in SSH range
#   _cai_allocate_ssh_port()     - Allocate SSH port for container (with reuse support)
#   _cai_get_container_ssh_port() - Get SSH port from container label
#   _cai_set_container_ssh_port() - Validate port setting (must use --label at creation)
#   _cai_get_reserved_container_ports() - Get all ports reserved by ContainAI containers
#   _cai_list_containers_with_ports() - List containers with their SSH port allocations
#   _cai_is_port_available()     - Check if a specific port is available
#   _cai_wait_for_sshd()         - Wait for sshd readiness with exponential backoff
#   _cai_inject_ssh_key()        - Inject public key into container's authorized_keys
#   _cai_update_known_hosts()    - Populate known_hosts via ssh-keyscan
#   _cai_clean_known_hosts()     - Remove stale known_hosts entries for a container
#   _cai_check_ssh_accept_new_support() - Check if OpenSSH supports accept-new
#   _cai_write_ssh_host_config() - Write per-container SSH host config
#   _cai_remove_ssh_host_config() - Remove SSH host config for a container
#   _cai_setup_container_ssh()   - Complete SSH setup for a container
#   _cai_cleanup_container_ssh() - Clean up SSH configuration for container removal
#   _cai_is_containai_ssh_config() - Check if a file is a ContainAI SSH config
#   _cai_ssh_cleanup()           - Remove stale SSH configs for non-existent containers
#
# Port range is configurable via [ssh] section in config.toml:
#   [ssh]
#   port_range_start = 2300
#   port_range_end = 2500
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
#   - Requires lib/docker.sh for _cai_timeout (portable timeout wrapper)
#
# Usage: source lib/ssh.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/ssh.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/ssh.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/ssh.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_SSH_LOADED:-}" ]]; then
    return 0
fi
_CAI_SSH_LOADED=1

# ==============================================================================
# Constants
# ==============================================================================

# ContainAI config directory
_CAI_CONFIG_DIR="$HOME/.config/containai"

# SSH key paths
_CAI_SSH_KEY_PATH="$_CAI_CONFIG_DIR/id_containai"
_CAI_SSH_PUBKEY_PATH="$_CAI_CONFIG_DIR/id_containai.pub"

# Config file path
_CAI_CONFIG_FILE="$_CAI_CONFIG_DIR/config.toml"

# SSH config directory for per-container configs
_CAI_SSH_CONFIG_DIR="$HOME/.ssh/containai.d"

# Minimum OpenSSH version for Include directive support
_CAI_SSH_MIN_VERSION="7.3"

# Default SSH port range for ContainAI containers
_CAI_SSH_PORT_RANGE_START_DEFAULT=2300
_CAI_SSH_PORT_RANGE_END_DEFAULT=2500

# Lock file for port allocation (prevents concurrent allocation races)
_CAI_SSH_PORT_LOCK_FILE="$_CAI_CONFIG_DIR/.ssh-port.lock"

# Known hosts file for ContainAI containers
_CAI_KNOWN_HOSTS_FILE="$_CAI_CONFIG_DIR/known_hosts"

# Hostname used for local SSH connections (IPv4 to avoid IPv6 resolution issues)
_CAI_SSH_HOST="127.0.0.1"

# Maximum wait time for sshd to become ready (seconds)
_CAI_SSHD_WAIT_MAX=30

# Lock file for known_hosts updates (prevents concurrent modification races)
_CAI_KNOWN_HOSTS_LOCK_FILE="$_CAI_CONFIG_DIR/.known_hosts.lock"

# Minimum OpenSSH version for StrictHostKeyChecking=accept-new (7.6)
_CAI_SSH_ACCEPT_NEW_MIN_VERSION="7.6"

# Get effective SSH port range (config overrides defaults)
# Outputs: "start end" (space-separated)
# Returns: 0 always
_cai_get_ssh_port_range() {
    local start="${_CAI_SSH_PORT_RANGE_START:-$_CAI_SSH_PORT_RANGE_START_DEFAULT}"
    local end="${_CAI_SSH_PORT_RANGE_END:-$_CAI_SSH_PORT_RANGE_END_DEFAULT}"

    # Use defaults from config.sh globals if set (parsed from [ssh] section)
    # These will be set by _containai_parse_config() if config has [ssh].port_range_start/end
    printf '%s %s' "$start" "$end"
}

# ==============================================================================
# Path getters
# ==============================================================================

# Return path to ContainAI SSH private key
_cai_get_ssh_key_path() {
    printf '%s' "$_CAI_SSH_KEY_PATH"
}

# Return path to ContainAI SSH public key
_cai_get_ssh_pubkey_path() {
    printf '%s' "$_CAI_SSH_PUBKEY_PATH"
}

# Return path to ContainAI SSH config directory
_cai_get_ssh_config_dir() {
    printf '%s' "$_CAI_SSH_CONFIG_DIR"
}

# ==============================================================================
# SSH Key Setup
# ==============================================================================

# Generate dedicated ed25519 SSH key for ContainAI
# Creates ~/.config/containai/ directory and generates SSH keypair
# Arguments: none
# Returns: 0=success (key exists or created), 1=failure
#
# Behavior:
# - Creates ~/.config/containai/ directory with 700 permissions if missing
# - Generates ed25519 key with no passphrase if key doesn't exist
# - Sets 600 permissions on private key, 644 on public key
# - Creates empty config.toml if missing
# - Idempotent: does NOT overwrite existing key
_cai_setup_ssh_key() {
    local config_dir="$_CAI_CONFIG_DIR"
    local key_path="$_CAI_SSH_KEY_PATH"
    local pubkey_path="$_CAI_SSH_PUBKEY_PATH"
    local config_file="$_CAI_CONFIG_FILE"

    _cai_step "Setting up ContainAI SSH key"

    # Check if ssh-keygen is available
    if ! command -v ssh-keygen >/dev/null 2>&1; then
        _cai_error "ssh-keygen is not installed or not in PATH"
        return 1
    fi

    # Create config directory with 700 permissions if missing
    if [[ ! -d "$config_dir" ]]; then
        _cai_debug "Creating config directory: $config_dir"
        if ! mkdir -p "$config_dir"; then
            _cai_error "Failed to create directory: $config_dir"
            return 1
        fi
        if ! chmod 700 "$config_dir"; then
            _cai_error "Failed to set permissions on: $config_dir"
            return 1
        fi
    else
        # Verify permissions on existing directory
        local dir_perms
        dir_perms=$(stat -c "%a" "$config_dir" 2>/dev/null || stat -f "%OLp" "$config_dir" 2>/dev/null)
        if [[ "$dir_perms" != "700" ]]; then
            _cai_debug "Fixing permissions on config directory"
            if ! chmod 700 "$config_dir"; then
                _cai_warn "Could not fix permissions on: $config_dir"
            fi
        fi
    fi

    # Check if SSH key already exists (idempotent)
    if [[ -f "$key_path" ]]; then
        _cai_info "SSH key already exists: $key_path"
        # Verify public key exists too
        if [[ ! -f "$pubkey_path" ]]; then
            _cai_warn "Private key exists but public key missing, regenerating public key"
            if ! ssh-keygen -y -f "$key_path" >"$pubkey_path" 2>/dev/null; then
                _cai_error "Failed to regenerate public key from private key"
                return 1
            fi
            chmod 644 "$pubkey_path"
        fi
    else
        # Generate new ed25519 key
        _cai_debug "Generating new ed25519 SSH key"
        if ! ssh-keygen -t ed25519 -f "$key_path" -N "" -C "containai" >/dev/null 2>&1; then
            _cai_error "Failed to generate SSH key"
            return 1
        fi
        _cai_info "Generated SSH key: $key_path"
    fi

    # Set correct permissions on keys
    if ! chmod 600 "$key_path"; then
        _cai_error "Failed to set permissions on private key"
        return 1
    fi
    if ! chmod 644 "$pubkey_path"; then
        _cai_error "Failed to set permissions on public key"
        return 1
    fi

    # Create empty config.toml if missing
    if [[ ! -f "$config_file" ]]; then
        _cai_debug "Creating empty config file: $config_file"
        if ! touch "$config_file"; then
            _cai_error "Failed to create config file: $config_file"
            return 1
        fi
    fi

    _cai_ok "SSH key setup complete"
    return 0
}

# ==============================================================================
# SSH Config Setup
# ==============================================================================

# Check if installed OpenSSH version supports Include directive
# Arguments: none
# Returns: 0=supported, 1=not supported or cannot determine
# Output: version string on stdout
_cai_check_ssh_version() {
    local ssh_version_output version_str major minor

    # Get SSH version output
    if ! ssh_version_output=$(ssh -V 2>&1); then
        _cai_debug "Could not determine SSH version"
        return 1
    fi

    # Parse version from output like "OpenSSH_8.9p1 Ubuntu-3ubuntu0.6"
    # Extract the version number (e.g., "8.9" from "OpenSSH_8.9p1")
    if [[ "$ssh_version_output" =~ OpenSSH_([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        version_str="${major}.${minor}"
        printf '%s' "$version_str"

        # Compare version: minimum is 7.3
        local min_major min_minor
        min_major="${_CAI_SSH_MIN_VERSION%%.*}"
        min_minor="${_CAI_SSH_MIN_VERSION#*.}"

        if ((major > min_major)) || { ((major == min_major)) && ((minor >= min_minor)); }; then
            return 0
        else
            return 1
        fi
    else
        _cai_debug "Could not parse SSH version from: $ssh_version_output"
        return 1
    fi
}

# Setup ~/.ssh/containai.d/ directory and add Include directive to SSH config
# Arguments: none
# Returns: 0=success, 1=failure
#
# Behavior:
# - Creates ~/.ssh/ directory with 700 permissions if missing
# - Creates ~/.ssh/containai.d/ directory with 700 permissions if missing
# - Creates ~/.ssh/config with 600 permissions if missing
# - Adds "Include ~/.ssh/containai.d/*.conf" at TOP of ~/.ssh/config if not present
# - If Include exists but not at top, moves it to top (required for SSH to process it)
# - Warns if OpenSSH version < 7.3p1 (Include directive not supported)
# - Idempotent: does NOT duplicate Include directive on re-run
# - Preserves existing SSH config content
# - Preserves symlinks (uses cp instead of mv)
_cai_setup_ssh_config() {
    local ssh_dir="$HOME/.ssh"
    local config_dir="$_CAI_SSH_CONFIG_DIR"
    local ssh_config="$ssh_dir/config"
    local include_line="Include ~/.ssh/containai.d/*.conf"
    local ssh_version

    _cai_step "Setting up SSH config for ContainAI"

    # Check OpenSSH version for Include directive support
    if ssh_version=$(_cai_check_ssh_version); then
        _cai_debug "OpenSSH version $ssh_version supports Include directive"
    else
        if [[ -n "$ssh_version" ]]; then
            _cai_warn "OpenSSH version $ssh_version may not support Include directive (requires 7.3+)"
            _cai_warn "SSH host configs will be created but may not be used automatically"
        else
            _cai_warn "Could not determine OpenSSH version; Include directive may not work"
        fi
    fi

    # Create ~/.ssh/ directory if missing
    if [[ ! -d "$ssh_dir" ]]; then
        _cai_debug "Creating SSH directory: $ssh_dir"
        if ! mkdir -p "$ssh_dir"; then
            _cai_error "Failed to create directory: $ssh_dir"
            return 1
        fi
        if ! chmod 700 "$ssh_dir"; then
            _cai_error "Failed to set permissions on: $ssh_dir"
            return 1
        fi
    fi

    # Create ~/.ssh/containai.d/ directory with 700 permissions
    if [[ ! -d "$config_dir" ]]; then
        _cai_debug "Creating SSH config directory: $config_dir"
        if ! mkdir -p "$config_dir"; then
            _cai_error "Failed to create directory: $config_dir"
            return 1
        fi
        if ! chmod 700 "$config_dir"; then
            _cai_error "Failed to set permissions on: $config_dir"
            return 1
        fi
        _cai_info "Created SSH config directory: $config_dir"
    else
        # Verify permissions on existing directory
        local dir_perms
        dir_perms=$(stat -c "%a" "$config_dir" 2>/dev/null || stat -f "%OLp" "$config_dir" 2>/dev/null)
        if [[ "$dir_perms" != "700" ]]; then
            _cai_debug "Fixing permissions on SSH config directory"
            if ! chmod 700 "$config_dir"; then
                _cai_warn "Could not fix permissions on: $config_dir"
            fi
        fi
        _cai_debug "SSH config directory already exists: $config_dir"
    fi

    # Create ~/.ssh/config if missing
    if [[ ! -f "$ssh_config" ]]; then
        _cai_debug "Creating SSH config file: $ssh_config"
        if ! printf '%s\n' "$include_line" >"$ssh_config"; then
            _cai_error "Failed to create SSH config: $ssh_config"
            return 1
        fi
        if ! chmod 600 "$ssh_config"; then
            _cai_error "Failed to set permissions on: $ssh_config"
            return 1
        fi
        _cai_info "Created SSH config with Include directive"
    else
        # Check if Include directive for containai.d already present at TOP of config
        # The Include directive MUST be at the top (before any Host/Match definitions)
        # Use case-insensitive regex to handle:
        # - Case variants (Include, include, INCLUDE)
        # - Path variants (~, $HOME, absolute path like /home/user)
        # - Whitespace variants and trailing comments
        local include_pattern='^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]+[^#]*containai\.d/\*\.conf'
        local first_effective_line include_present include_at_top
        include_present=false
        include_at_top=false

        # Check if include directive exists anywhere in the file (case-insensitive, path-tolerant)
        if grep -qE "$include_pattern" "$ssh_config"; then
            include_present=true
            # Check if it's at the top (first non-empty, non-comment line)
            first_effective_line=$(grep -v '^[[:space:]]*$' "$ssh_config" | grep -v '^[[:space:]]*#' | head -1)
            # Check if first effective line matches our include pattern
            if printf '%s' "$first_effective_line" | grep -qE "$include_pattern"; then
                include_at_top=true
            fi
        fi

        if [[ "$include_present" == "true" ]] && [[ "$include_at_top" == "true" ]]; then
            _cai_debug "Include directive already present at top of SSH config"
        else
            # Need to update config: either add Include or move it to top
            _cai_debug "Updating SSH config with Include directive at top"
            local temp_file
            if ! temp_file=$(mktemp); then
                _cai_error "Failed to create temporary file"
                return 1
            fi

            # Build new config: Include line at top, then existing content (minus any existing Include)
            if ! {
                printf '%s\n\n' "$include_line"
                # Remove any existing Include line for containai.d to avoid duplicates
                # Use same case-insensitive pattern to remove all variants (tilde, $HOME, absolute path)
                grep -vE "$include_pattern" "$ssh_config" || true
            } >"$temp_file"; then
                _cai_error "Failed to prepare SSH config update"
                rm -f "$temp_file"
                return 1
            fi

            # Use cp instead of mv to preserve symlinks
            # cp will follow the symlink and overwrite the target file content
            if ! cp "$temp_file" "$ssh_config"; then
                _cai_error "Failed to update SSH config"
                rm -f "$temp_file"
                return 1
            fi
            rm -f "$temp_file"

            if ! chmod 600 "$ssh_config"; then
                _cai_warn "Could not set permissions on SSH config"
            fi

            if [[ "$include_present" == "true" ]]; then
                _cai_info "Moved Include directive to top of SSH config"
            else
                _cai_info "Added Include directive to SSH config"
            fi
        fi
    fi

    _cai_ok "SSH config setup complete"
    return 0
}

# ==============================================================================
# SSH Port Allocation
# ==============================================================================

# Get list of ports currently in use (listening TCP/UDP ports)
# Arguments: none
# Outputs: one port number per line (listening ports only)
# Returns: 0 on success, 1 if ss command fails
_cai_get_used_ports() {
    local ss_output port line local_addr

    # Use ss -tulpn as specified (TCP+UDP, listening, show process, numeric)
    # -t: TCP, -u: UDP, -l: listening, -p: show process, -n: numeric
    if ! ss_output=$(ss -tulpn 2>/dev/null); then
        _cai_debug "ss command failed, cannot determine used ports"
        return 1
    fi

    # Parse output: extract port from Local Address column
    # ss -tulpn format: Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
    # Local address can be:
    #   - *:port (all interfaces)
    #   - 0.0.0.0:port (IPv4 all)
    #   - [::]:port (IPv6 all)
    #   - 127.0.0.1:port (localhost)
    #   - [::1]:port (IPv6 localhost)
    printf '%s\n' "$ss_output" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip header line
        [[ "$line" == Netid* ]] && continue
        # Extract local address:port (5th column in ss -tulpn output)
        # Handle both IPv4 (addr:port) and IPv6 ([addr]:port) formats
        local_addr=$(printf '%s' "$line" | awk '{print $5}')
        if [[ -z "$local_addr" ]]; then
            continue
        fi
        # Extract port number (everything after last colon)
        port="${local_addr##*:}"
        # Validate it's a number
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            printf '%s\n' "$port"
        fi
    done
}

# Find first available port in the ContainAI SSH port range
# Arguments:
#   $1 = port range start (optional, uses config or default 2300)
#   $2 = port range end (optional, uses config or default 2500)
#   $3 = docker context (optional, for checking container labels)
#   $4 = ignore port (optional, treat this port as available even if only reserved by container)
#   $5 = force ignore (optional, "true" to ignore port even if actively in use - for running containers)
# Outputs: available port number on success
# Returns: 0=port found, 1=all ports exhausted, 2=cannot check ports
#
# On exhaustion, outputs error message to stderr suggesting cleanup
_cai_find_available_port() {
    # Use config values if available, otherwise use defaults
    local default_start="${_CAI_SSH_PORT_RANGE_START:-$_CAI_SSH_PORT_RANGE_START_DEFAULT}"
    local default_end="${_CAI_SSH_PORT_RANGE_END:-$_CAI_SSH_PORT_RANGE_END_DEFAULT}"
    local range_start="${1:-$default_start}"
    local range_end="${2:-$default_end}"
    local context="${3:-}"
    local ignore_port="${4:-}"
    local force_ignore="${5:-}"
    local used_ports port

    # Validate range (allow single-port range where start == end)
    if [[ ! "$range_start" =~ ^[0-9]+$ ]] || [[ ! "$range_end" =~ ^[0-9]+$ ]]; then
        _cai_error "Invalid port range: $range_start-$range_end"
        return 2
    fi
    if ((range_start > range_end)); then
        _cai_error "Invalid port range: start ($range_start) must be <= end ($range_end)"
        return 2
    fi

    # Get list of used ports from ss
    if ! used_ports=$(_cai_get_used_ports); then
        _cai_error "Cannot determine used ports (ss command failed)"
        _cai_error "Ensure 'ss' (iproute2) is installed"
        return 2
    fi

    # Convert to associative array for O(1) lookup
    # Track which ports are actively in use (from ss) vs just reserved (from container labels)
    local -A used_ports_map
    local -A actively_used_map
    local line
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            used_ports_map["$line"]=1
            actively_used_map["$line"]=1
        fi
    done <<<"$used_ports"

    # Also collect ports reserved by container labels (including stopped containers)
    # This prevents allocating the same port to multiple containers
    local reserved_ports
    if reserved_ports=$(_cai_get_reserved_container_ports "$context" 2>/dev/null); then
        while IFS= read -r line; do
            # Skip the ignore_port (for dry-run scenarios where container will be removed)
            if [[ -n "$line" && "$line" != "$ignore_port" ]]; then
                used_ports_map["$line"]=1
            fi
        done <<<"$reserved_ports"
    fi

    # For ignore_port with force_ignore, also remove from used_ports_map even if actively in use
    # This handles --fresh/--restart on running containers where port will be freed before allocation
    if [[ -n "$ignore_port" && "$force_ignore" == "true" ]]; then
        unset "used_ports_map[$ignore_port]"
    fi

    # Find first available port in range (inclusive)
    for ((port = range_start; port <= range_end; port++)); do
        if [[ -z "${used_ports_map[$port]:-}" ]]; then
            printf '%s' "$port"
            return 0
        fi
    done

    # All ports exhausted - provide actionable error with container list
    local port_count=$((range_end - range_start + 1))
    _cai_error "All $port_count SSH ports in range $range_start-$range_end are in use"
    _cai_error ""

    # List containers using ports in the range
    local container_list
    if container_list=$(_cai_list_containers_with_ports "$context" 2>/dev/null); then
        if [[ -n "$container_list" ]]; then
            _cai_error "Containers using SSH ports:"
            while IFS= read -r line; do
                [[ -n "$line" ]] && _cai_error "  $line"
            done <<<"$container_list"
            _cai_error ""
        fi
    fi

    _cai_error "To free up ports, you can:"
    _cai_error "  1. Stop unused containers: cai-stop-all --all"
    _cai_error "  2. Remove stale SSH configs:"
    _cai_error "     rm ~/.ssh/containai.d/*.conf"
    _cai_error "  3. Check which processes are using ports:"
    _cai_error "     ss -tulpn | grep -E ':2[3-4][0-9]{2}|:2500'"
    _cai_error ""
    return 1
}

# List ContainAI containers with their SSH ports
# Arguments: $1 = docker context (optional)
# Outputs: "container_name: port" per line
# Returns: 0 on success
_cai_list_containers_with_ports() {
    local context="${1:-}"
    local -a docker_cmd=(docker)
    local container_output line name port

    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    # Get container name and ssh-port for all ContainAI containers
    if ! container_output=$("${docker_cmd[@]}" ps -a --filter "label=containai.managed=true" \
        --format '{{.Names}}\t{{index .Labels "containai.ssh-port"}}' 2>/dev/null); then
        return 1
    fi

    # Output formatted list
    while IFS=$'\t' read -r name port; do
        [[ -z "$name" ]] && continue
        if [[ -n "$port" ]] && [[ "$port" != "<no value>" ]]; then
            printf '%s: port %s\n' "$name" "$port"
        fi
    done <<<"$container_output"
}

# Get all SSH ports reserved by ContainAI containers (via labels)
# Includes both running and stopped containers to prevent port collisions
# Arguments: $1 = docker context (optional)
# Outputs: one port number per line
# Returns: 0 on success
_cai_get_reserved_container_ports() {
    local context="${1:-}"
    local -a docker_cmd=(docker)
    local ports_output line port

    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    # Get all ContainAI containers (running + stopped) and extract their ssh-port labels
    # Filter by our management label to only get our containers
    if ! ports_output=$("${docker_cmd[@]}" ps -a --filter "label=containai.managed=true" \
        --format '{{index .Labels "containai.ssh-port"}}' 2>/dev/null); then
        return 1
    fi

    # Output non-empty port values
    while IFS= read -r line; do
        # Skip empty lines and <no value>
        [[ -z "$line" ]] && continue
        [[ "$line" == "<no value>" ]] && continue
        # Validate it's a port number
        if [[ "$line" =~ ^[0-9]+$ ]]; then
            printf '%s\n' "$line"
        fi
    done <<<"$ports_output"
}

# Set the SSH port label on a container
# This stores the allocated port persistently with the container
# Arguments: $1 = container name, $2 = port, $3 = docker context (optional)
# Returns: 0 on success, 1 on failure
# Note: For new containers, use --label "containai.ssh-port=$port" at creation time
#       This function is for updating existing containers
_cai_set_container_ssh_port() {
    local container_name="$1"
    local port="$2"
    local context="${3:-}"
    local -a docker_cmd=(docker)

    if [[ -z "$container_name" ]] || [[ -z "$port" ]]; then
        _cai_error "Container name and port are required"
        return 1
    fi

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        _cai_error "Invalid port number: $port"
        return 1
    fi

    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    # Docker doesn't support updating labels on existing containers directly
    # The label must be set at container creation time with:
    #   --label "containai.ssh-port=$port"
    # This function serves as documentation and validation
    # Callers should ensure the label is set during container creation
    _cai_debug "SSH port $port should be set via --label at container creation"

    # Verify the container exists
    if ! "${docker_cmd[@]}" inspect --format '{{.Id}}' -- "$container_name" >/dev/null 2>&1; then
        _cai_error "Container not found: $container_name"
        return 1
    fi

    return 0
}

# Get the SSH port for a container from its label
# Arguments: $1 = container name, $2 = docker context (optional)
# Outputs: port number if found
# Returns: 0=port found, 1=no port label
_cai_get_container_ssh_port() {
    local container_name="$1"
    local context="${2:-}"
    local port

    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    # Get the containai.ssh-port label value
    # Use -- to prevent container names starting with - being interpreted as flags
    if ! port=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.ssh-port"}}' -- "$container_name" 2>/dev/null); then
        return 1
    fi

    # Check for <no value> or empty
    if [[ -z "$port" ]] || [[ "$port" == "<no value>" ]]; then
        return 1
    fi

    printf '%s' "$port"
    return 0
}

# Allocate SSH port for a container
# If container already has a port label, tries to reuse it (if still available)
# Otherwise allocates a new port from the range
#
# Arguments:
#   $1 = container name
#   $2 = docker context (optional)
#   $3 = port range start (optional, uses config or default 2300)
#   $4 = port range end (optional, uses config or default 2500)
# Outputs: allocated port number
# Returns: 0=success, 1=exhausted, 2=error
#
# Note: This does NOT update the container label - caller should do that
# when creating/updating the container with --label "containai.ssh-port=$port"
_cai_allocate_ssh_port() {
    local container_name="$1"
    local context="${2:-}"
    # Use config values if available, otherwise use defaults
    local default_start="${_CAI_SSH_PORT_RANGE_START:-$_CAI_SSH_PORT_RANGE_START_DEFAULT}"
    local default_end="${_CAI_SSH_PORT_RANGE_END:-$_CAI_SSH_PORT_RANGE_END_DEFAULT}"
    local range_start="${3:-$default_start}"
    local range_end="${4:-$default_end}"
    local existing_port used_ports line port_in_use container_state

    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    # Check if container already has an allocated port
    if existing_port=$(_cai_get_container_ssh_port "$container_name" "$context"); then
        # Validate the existing port is a number and in range
        if [[ "$existing_port" =~ ^[0-9]+$ ]]; then
            if ((existing_port >= range_start && existing_port <= range_end)); then
                # Check if the port is still available for use
                if ! used_ports=$(_cai_get_used_ports); then
                    # Cannot verify port availability - fail with error, not silent success
                    _cai_error "Cannot verify port availability (ss command failed)"
                    _cai_error "Ensure 'ss' (iproute2) is installed"
                    return 2
                fi

                # Check if port is in use
                port_in_use=false
                while IFS= read -r line; do
                    if [[ "$line" == "$existing_port" ]]; then
                        port_in_use=true
                        break
                    fi
                done <<<"$used_ports"

                # If port is not in use at all, reuse it (container is stopped)
                if [[ "$port_in_use" == "false" ]]; then
                    _cai_debug "Reusing existing SSH port $existing_port for container $container_name"
                    printf '%s' "$existing_port"
                    return 0
                fi

                # Port is in use - check if it's by THIS container (running)
                # Get container state to determine if it's running
                container_state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' -- "$container_name" 2>/dev/null) || container_state=""
                if [[ "$container_state" == "running" ]]; then
                    # Container is running and owns this port - reuse it
                    _cai_debug "Reusing SSH port $existing_port for running container $container_name"
                    printf '%s' "$existing_port"
                    return 0
                fi

                # Port is in use by something else - need new port
                _cai_debug "SSH port $existing_port in use by another process, allocating new port"
            else
                _cai_debug "Existing SSH port $existing_port outside configured range, allocating new"
            fi
        fi
    fi

    # Allocate new port (pass context for container label checking)
    _cai_find_available_port "$range_start" "$range_end" "$context"
}

# Check if a specific port is available (not in use)
# Arguments: $1 = port number
# Returns: 0=available, 1=in use, 2=cannot check
_cai_is_port_available() {
    local port="$1"
    local used_ports line

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        return 2
    fi

    if ! used_ports=$(_cai_get_used_ports); then
        return 2
    fi

    while IFS= read -r line; do
        if [[ "$line" == "$port" ]]; then
            return 1
        fi
    done <<<"$used_ports"

    return 0
}

# ==============================================================================
# SSH Connection Setup Functions
# ==============================================================================

# Wait for sshd to become ready in a container with exponential backoff
# Arguments:
#   $1 = container name
#   $2 = SSH port (on host)
#   $3 = docker context (optional)
# Returns: 0=sshd ready, 1=timeout (sshd not ready within max wait time)
#
# Uses exponential backoff starting at 100ms, doubling each attempt up to 2s max interval
# Total max wait time is controlled by _CAI_SSHD_WAIT_MAX (default 30s)
# Uses wall-clock time tracking to ensure accurate timeout regardless of command duration
_cai_wait_for_sshd() {
    local container_name="$1"
    local ssh_port="$2"
    local context="${3:-}"
    local -a docker_cmd=(docker)
    local wait_ms=100          # Start at 100ms
    local max_interval_ms=2000 # Cap at 2 seconds between retries
    local attempt=0

    # Validate port is numeric
    if [[ ! "$ssh_port" =~ ^[0-9]+$ ]]; then
        _cai_error "Invalid SSH port: $ssh_port (must be numeric)"
        return 1
    fi

    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    # Check if ssh-keyscan is available
    if ! command -v ssh-keyscan >/dev/null 2>&1; then
        _cai_error "ssh-keyscan is not installed or not in PATH"
        _cai_error "Install OpenSSH client tools to enable SSH access"
        return 1
    fi

    _cai_debug "Waiting for sshd to become ready on port $ssh_port (max ${_CAI_SSHD_WAIT_MAX}s)..."

    # Track wall-clock time using SECONDS builtin
    local start_seconds=$SECONDS

    while ((SECONDS - start_seconds < _CAI_SSHD_WAIT_MAX)); do
        attempt=$((attempt + 1))

        # First check: verify container is still running (with timeout to prevent hangs)
        local container_state inspect_rc
        if container_state=$(_cai_timeout 5 "${docker_cmd[@]}" inspect --format '{{.State.Status}}' -- "$container_name" 2>/dev/null); then
            inspect_rc=0
        else
            inspect_rc=$?
        fi

        # Handle timeout unavailable
        if [[ $inspect_rc -eq 125 ]]; then
            _cai_error "No timeout mechanism available (timeout/gtimeout/perl not found)"
            _cai_error "Install GNU coreutils to enable SSH wait functionality"
            _cai_error "  macOS: brew install coreutils"
            _cai_error "  Linux: apt install coreutils (usually pre-installed)"
            return 1
        fi

        if [[ "$container_state" != "running" ]]; then
            _cai_error "Container '$container_name' is not running (state: ${container_state:-unknown})"
            return 1
        fi

        # Second check: try to connect to sshd via ssh-keyscan (quick TCP connection test)
        # ssh-keyscan returns 0 if it can connect and get a host key, non-zero otherwise
        # Use _cai_timeout for portability (macOS doesn't have timeout by default)
        local keyscan_rc
        if _cai_timeout 2 ssh-keyscan -p "$ssh_port" -T 1 "$_CAI_SSH_HOST" >/dev/null 2>&1; then
            keyscan_rc=0
        else
            keyscan_rc=$?
        fi

        if [[ $keyscan_rc -eq 0 ]]; then
            local elapsed=$((SECONDS - start_seconds))
            _cai_debug "sshd is ready on port $ssh_port (after ${elapsed}s, attempt $attempt)"
            return 0
        fi

        # Sleep before retry (exponential backoff)
        local sleep_sec
        # Convert ms to seconds with decimal (e.g., 100ms -> 0.1)
        sleep_sec=$(awk "BEGIN {printf \"%.3f\", $wait_ms / 1000}")
        sleep "$sleep_sec"

        # Double the wait time, capped at max interval
        wait_ms=$((wait_ms * 2))
        if ((wait_ms > max_interval_ms)); then
            wait_ms=$max_interval_ms
        fi
    done

    _cai_error "sshd did not become ready within ${_CAI_SSHD_WAIT_MAX} seconds"
    _cai_error "  Container: $container_name"
    _cai_error "  Port: $ssh_port"
    _cai_error ""
    _cai_error "Troubleshooting:"
    _cai_error "  1. Check container logs: docker logs $container_name"
    _cai_error "  2. Check sshd status: docker exec $container_name systemctl status ssh"
    _cai_error "  3. Check listening ports: docker exec $container_name ss -tlnp"
    _cai_error "  4. Check if port is exposed: docker port $container_name 22"
    return 1
}

# Inject SSH public key into container's authorized_keys
# Creates /home/agent/.ssh/ directory if missing and adds the key
# Arguments:
#   $1 = container name
#   $2 = docker context (optional)
# Returns: 0=success, 1=failure
#
# Behavior:
# - Auto-generates SSH key if missing (transparent setup)
# - Reads pubkey from ~/.config/containai/id_containai.pub
# - Creates /home/agent/.ssh/ with 700 permissions via docker exec
# - Appends key to /home/agent/.ssh/authorized_keys (idempotent)
# - Sets 600 permissions on authorized_keys
# - Runs as root via docker exec, then chowns files to agent user
_cai_inject_ssh_key() {
    local container_name="$1"
    local context="${2:-}"
    local -a docker_cmd=(docker)
    local pubkey_path="$_CAI_SSH_PUBKEY_PATH"
    local pubkey_content

    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    # Auto-generate SSH key if missing (transparent setup)
    if [[ ! -f "$pubkey_path" ]]; then
        _cai_debug "SSH key not found, auto-generating..."
        if ! _cai_setup_ssh_key; then
            _cai_error "Failed to auto-generate SSH key"
            return 1
        fi
    fi

    # Read public key (should exist now)
    if [[ ! -f "$pubkey_path" ]]; then
        _cai_error "SSH public key not found after generation: $pubkey_path"
        return 1
    fi

    if ! pubkey_content=$(cat "$pubkey_path"); then
        _cai_error "Failed to read SSH public key: $pubkey_path"
        return 1
    fi

    # Validate key format (should start with ssh- or ecdsa-)
    if [[ ! "$pubkey_content" =~ ^(ssh-|ecdsa-) ]]; then
        _cai_error "Invalid SSH public key format in: $pubkey_path"
        return 1
    fi

    _cai_debug "Injecting SSH key into container $container_name"

    # Create .ssh directory with correct permissions (as root, then chown)
    # Use a single docker exec with a script to minimize round trips
    local inject_script
    inject_script=$(
        cat <<'SCRIPT_EOF'
set -e
SSH_DIR="/home/agent/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
PUBKEY="$1"

# Create .ssh directory if missing
if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
fi
chmod 700 "$SSH_DIR"
chown agent:agent "$SSH_DIR"

# Create authorized_keys if missing
if [ ! -f "$AUTH_KEYS" ]; then
    touch "$AUTH_KEYS"
fi
chmod 600 "$AUTH_KEYS"
chown agent:agent "$AUTH_KEYS"

# Add key if not already present (idempotent)
# Extract key material (field 2) for matching - ignores comment changes
KEY_MATERIAL=$(printf '%s' "$PUBKEY" | awk '{print $2}')
if [ -n "$KEY_MATERIAL" ] && ! grep -qF "$KEY_MATERIAL" "$AUTH_KEYS" 2>/dev/null; then
    printf '%s\n' "$PUBKEY" >> "$AUTH_KEYS"
fi
SCRIPT_EOF
    )

    # Execute the injection script in the container
    # Pass pubkey as argument to avoid shell escaping issues
    if ! "${docker_cmd[@]}" exec -- "$container_name" bash -c "$inject_script" _ "$pubkey_content"; then
        _cai_error "Failed to inject SSH key into container"
        return 1
    fi

    _cai_debug "SSH key injected successfully"
    return 0
}

# Update known_hosts with container's SSH host key
# Uses ssh-keyscan to retrieve the host key and stores it in ContainAI's known_hosts
# Arguments:
#   $1 = container name
#   $2 = SSH port (on host)
#   $3 = docker context (optional, unused but kept for API compatibility)
#   $4 = force_update (optional, "true" to replace keys without warning)
# Returns: 0=success, 1=failure
#
# Behavior:
# - Runs ssh-keyscan -p <port> $_CAI_SSH_HOST to get container's host key
# - Stores in ~/.config/containai/known_hosts
# - Handles port-specific host key format ([$_CAI_SSH_HOST]:port)
# - Retry with backoff since ssh-keyscan can fail if sshd just started
# - Detects host key changes and warns user (unless force_update=true)
# - Uses file locking to prevent concurrent modification races
_cai_update_known_hosts() {
    local container_name="$1"
    local ssh_port="$2"
    local context="${3:-}" # Unused but kept for API compatibility
    local force_update="${4:-false}"
    local known_hosts_file="$_CAI_KNOWN_HOSTS_FILE"
    local lock_file="$_CAI_KNOWN_HOSTS_LOCK_FILE"
    local host_keys retry_count=0 max_retries=3
    local wait_ms=200
    local lock_fd

    # Validate port is numeric
    if [[ ! "$ssh_port" =~ ^[0-9]+$ ]]; then
        _cai_error "Invalid SSH port: $ssh_port (must be numeric)"
        return 1
    fi

    _cai_debug "Retrieving SSH host keys for container $container_name on port $ssh_port"

    # Ensure config directory exists
    if ! mkdir -p "$(dirname "$known_hosts_file")" 2>/dev/null; then
        _cai_error "Failed to create config directory for known_hosts"
        return 1
    fi

    # Ensure known_hosts file exists with correct permissions
    if [[ ! -f "$known_hosts_file" ]]; then
        if ! touch "$known_hosts_file"; then
            _cai_error "Failed to create known_hosts file: $known_hosts_file"
            return 1
        fi
        if ! chmod 600 "$known_hosts_file"; then
            _cai_error "Failed to set permissions on known_hosts file"
            return 1
        fi
    fi

    # Retrieve host keys with retry (ssh-keyscan can fail if sshd just started)
    # Do this BEFORE acquiring lock to minimize lock hold time
    while ((retry_count < max_retries)); do
        # ssh-keyscan -p outputs keys in format: [host]:port ssh-type key
        # -T 5 sets connection timeout, -t rsa,ed25519 gets specific key types
        # Filter out comment lines (starting with #) and ensure valid key format (3+ fields)
        if host_keys=$(ssh-keyscan -p "$ssh_port" -T 5 -t rsa,ed25519,ecdsa "$_CAI_SSH_HOST" 2>/dev/null | awk '$1 !~ /^#/ && NF >= 3'); then
            if [[ -n "$host_keys" ]]; then
                break
            fi
        fi

        retry_count=$((retry_count + 1))
        if ((retry_count < max_retries)); then
            _cai_debug "ssh-keyscan failed, retrying (attempt $((retry_count + 1))/$max_retries)..."
            local sleep_sec
            sleep_sec=$(awk "BEGIN {printf \"%.3f\", $wait_ms / 1000}")
            sleep "$sleep_sec"
            wait_ms=$((wait_ms * 2))
        fi
    done

    if [[ -z "$host_keys" ]]; then
        _cai_error "Failed to retrieve SSH host keys for port $ssh_port"
        _cai_error "ssh-keyscan failed after $max_retries attempts"
        return 1
    fi

    # Acquire lock for atomic known_hosts modification
    # This prevents concurrent cai start commands from corrupting the file
    if command -v flock >/dev/null 2>&1; then
        # Try to open lock file; if it fails (permissions/dir issues), skip locking
        if exec {lock_fd}>"$lock_file" 2>/dev/null; then
            if ! flock -w 10 "$lock_fd"; then
                _cai_warn "Timeout acquiring known_hosts lock, proceeding without lock"
                # Close the FD to avoid leak before clearing
                exec {lock_fd}>&-
                lock_fd=""
            fi
        else
            _cai_debug "Could not open lock file, proceeding without lock"
            lock_fd=""
        fi
    fi

    # Check for existing keys and detect changes (unless force_update)
    # Host spec format depends on port (22 uses plain host, others use "[host]:port")
    local host_spec
    if [[ "$ssh_port" == "22" ]]; then
        host_spec="$_CAI_SSH_HOST"
    else
        host_spec="[${_CAI_SSH_HOST}]:${ssh_port}"
    fi
    local existing_keys=""
    if [[ -f "$known_hosts_file" ]]; then
        existing_keys=$(grep -F "$host_spec" "$known_hosts_file" 2>/dev/null || true)
    fi

    if [[ -n "$existing_keys" && "$force_update" != "true" ]]; then
        # Compare existing keys with scanned keys per key type
        # Only flag as mismatch if an existing key type has CHANGED
        # Allow adding new key types without warning
        local key_changed=false
        local key_type existing_key scanned_key

        # Check each existing key type to see if it changed
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            key_type=$(printf '%s' "$line" | awk '{print $2}')
            existing_key=$(printf '%s' "$line" | awk '{print $3}')

            # Find the same key type in scanned keys
            scanned_key=$(printf '%s\n' "$host_keys" | awk -v t="$key_type" '$2 == t {print $3}')

            if [[ -n "$scanned_key" && "$existing_key" != "$scanned_key" ]]; then
                # Same key type but different key material - this is a real change
                key_changed=true
                _cai_warn "SSH host key has changed for container $container_name (port $ssh_port)"
                _cai_warn "  Key type: $key_type"
                _cai_warn ""
                _cai_warn "This could indicate:"
                _cai_warn "  1. Container was recreated (expected after --fresh)"
                _cai_warn "  2. A potential security concern (man-in-the-middle)"
                _cai_warn ""
                _cai_warn "If you trust this is the correct container, clean the old key with:"
                _cai_warn "  ssh-keygen -R \"$host_spec\" -f \"$known_hosts_file\""
                _cai_warn "Then retry the operation, or use --fresh to force recreation."
                break
            fi
        done <<<"$existing_keys"

        if [[ "$key_changed" == "true" ]]; then
            # Release lock before returning
            if [[ -n "${lock_fd:-}" ]]; then
                exec {lock_fd}>&-
            fi
            return 1
        fi

        # Check if there are new key types to add
        local new_keys_to_add=""
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            key_type=$(printf '%s' "$line" | awk '{print $2}')
            # If this key type doesn't exist in existing_keys, it's new
            # Use awk for exact field matching (avoids regex issues with [host]:port)
            if ! printf '%s\n' "$existing_keys" | awk -v h="$host_spec" -v t="$key_type" '$1 == h && $2 == t {found=1; exit} END {exit !found}'; then
                new_keys_to_add="${new_keys_to_add}${line}"$'\n'
            fi
        done <<<"$host_keys"

        if [[ -n "$new_keys_to_add" ]]; then
            # Add new key types (this is safe - not a change)
            printf '%s' "$new_keys_to_add" >>"$known_hosts_file"
            _cai_debug "Added new key type(s) to known_hosts"
        else
            _cai_debug "Host keys unchanged for port $ssh_port"
        fi
    else
        # No existing keys or force_update - clean and add
        _cai_clean_known_hosts "$ssh_port"

        # Append host keys to known_hosts file
        if ! printf '%s\n' "$host_keys" >>"$known_hosts_file"; then
            _cai_error "Failed to write host keys to known_hosts file"
            if [[ -n "${lock_fd:-}" ]]; then
                exec {lock_fd}>&-
            fi
            return 1
        fi
        _cai_debug "Added $(printf '%s\n' "$host_keys" | wc -l) host key(s) to known_hosts"
    fi

    # Release lock
    if [[ -n "${lock_fd:-}" ]]; then
        exec {lock_fd}>&-
    fi

    return 0
}

# Remove stale known_hosts entries for a specific port
# Arguments:
#   $1 = SSH port
# Returns: 0 always
#
# Removes entries matching [host]:<port> pattern (or host for port 22)
# Called before updating known_hosts to handle container recreation
# Uses ssh-keygen -R for robust removal (avoids regex injection risks)
_cai_clean_known_hosts() {
    local ssh_port="$1"
    local known_hosts_file="$_CAI_KNOWN_HOSTS_FILE"

    if [[ ! -f "$known_hosts_file" ]]; then
        return 0
    fi

    # Validate port is numeric to prevent injection
    if [[ ! "$ssh_port" =~ ^[0-9]+$ ]]; then
        _cai_debug "Invalid port for known_hosts cleanup: $ssh_port"
        return 0
    fi

    # ssh-keyscan output format depends on port:
    # - Port 22: "host" (no brackets)
    # - Other ports: "[host]:port"
    # Use ssh-keygen -R for robust removal (handles hashed keys, avoids regex issues)
    # -f specifies the known_hosts file to modify

    # ssh-keygen -R exits 0 even if no matching entry found
    # Suppress output (it prints "Host found" messages to stdout)
    # Build host list: primary host + legacy localhost for cleanup
    local -a hosts=()
    hosts+=("$_CAI_SSH_HOST")
    if [[ "$_CAI_SSH_HOST" != "localhost" ]]; then
        hosts+=("localhost")
    fi

    local host
    for host in "${hosts[@]}"; do
        if [[ "$ssh_port" == "22" ]]; then
            # Port 22 uses "host" without brackets
            ssh-keygen -R "$host" -f "$known_hosts_file" >/dev/null 2>&1 || true
            # Also try with brackets in case it was added that way
            ssh-keygen -R "[$host]:22" -f "$known_hosts_file" >/dev/null 2>&1 || true
        else
            # Non-standard ports use [host]:port format
            ssh-keygen -R "[$host]:${ssh_port}" -f "$known_hosts_file" >/dev/null 2>&1 || true
        fi
    done

    _cai_debug "Cleaned known_hosts entries for port $ssh_port"
    return 0
}

# Check if installed OpenSSH supports StrictHostKeyChecking=accept-new
# Requires OpenSSH 7.6 or later
# Returns: 0=supported, 1=not supported
_cai_check_ssh_accept_new_support() {
    local ssh_version major minor min_major min_minor

    # Get SSH version
    if ! ssh_version=$(_cai_check_ssh_version 2>/dev/null); then
        return 1
    fi

    # Parse version (format: "X.Y")
    if [[ "$ssh_version" =~ ^([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
    else
        return 1
    fi

    # Compare against minimum (7.6)
    min_major="${_CAI_SSH_ACCEPT_NEW_MIN_VERSION%%.*}"
    min_minor="${_CAI_SSH_ACCEPT_NEW_MIN_VERSION#*.}"

    if ((major > min_major)) || { ((major == min_major)) && ((minor >= min_minor)); }; then
        return 0
    fi
    return 1
}

# Write SSH host config for a container to ~/.ssh/containai.d/
# Arguments:
#   $1 = container name
#   $2 = SSH port (on host)
# Returns: 0=success, 1=failure
#
# Creates a config file at ~/.ssh/containai.d/<container-name>.conf with:
# - Host alias matching container name
# - Connection to $_CAI_SSH_HOST:<port>
# - ContainAI identity key
# - ContainAI known_hosts file
# - StrictHostKeyChecking=accept-new (secure but allows first connection)
#   Falls back to 'yes' on older OpenSSH versions
# - ForwardAgent (if enabled in config) - allows SSH agent forwarding
# - LocalForward entries (from config) - enables port tunneling
#
# Config options (from [ssh] section):
# - forward_agent = true    -> ForwardAgent yes
# - local_forward = [...]   -> LocalForward entries
#
# SECURITY NOTE: ForwardAgent has security implications - an attacker with
# root access on the container could hijack the forwarded agent. Only enable
# if you trust the container environment.
_cai_write_ssh_host_config() {
    local container_name="$1"
    local ssh_port="$2"
    local config_dir="$_CAI_SSH_CONFIG_DIR"
    local identity_file="$_CAI_SSH_KEY_PATH"
    local known_hosts_file="$_CAI_KNOWN_HOSTS_FILE"
    local config_file="$config_dir/${container_name}.conf"
    local strict_host_key_checking

    # Always run SSH config setup to ensure:
    # 1. Config directory exists
    # 2. Include directive is present in ~/.ssh/config
    # This handles cases where user deleted ~/.ssh/containai.d/ or removed the Include line
    if ! _cai_setup_ssh_config; then
        _cai_error "Failed to set up SSH config directory"
        return 1
    fi

    # Determine StrictHostKeyChecking value based on OpenSSH version
    # accept-new (7.6+): accepts new keys, rejects changes (ideal for containers)
    # yes: requires key to exist in known_hosts already (we pre-populate via ssh-keyscan)
    if _cai_check_ssh_accept_new_support; then
        strict_host_key_checking="accept-new"
    else
        _cai_debug "OpenSSH < 7.6 detected, using StrictHostKeyChecking=yes"
        strict_host_key_checking="yes"
    fi

    _cai_debug "Writing SSH host config for $container_name to $config_file"

    # Build ForwardAgent directive based on config
    # SECURITY: ForwardAgent allows the container to use your SSH agent for
    # authentication to other hosts. Only enable if you trust the container.
    # IMPORTANT: We ALWAYS write an explicit ForwardAgent directive to override
    # any user's global config (e.g., "Host *" with ForwardAgent yes).
    local forward_agent_line=""
    if [[ "${_CAI_SSH_FORWARD_AGENT:-}" == "true" ]]; then
        forward_agent_line="    ForwardAgent yes"
        _cai_debug "ForwardAgent enabled via config"
    else
        forward_agent_line="    ForwardAgent no"
        _cai_debug "ForwardAgent explicitly disabled (default)"
    fi

    # Build LocalForward directives from config
    # Format in config: "localport:remotehost:remoteport"
    # Format in SSH config: "LocalForward localport remotehost:remoteport"
    local local_forward_lines=""
    local forward_entry local_port remote_part
    for forward_entry in "${_CAI_SSH_LOCAL_FORWARDS[@]:-}"; do
        if [[ -n "$forward_entry" ]]; then
            # Parse "8080:localhost:8080" -> "8080" and "localhost:8080"
            local_port="${forward_entry%%:*}"
            remote_part="${forward_entry#*:}"
            local_forward_lines="${local_forward_lines}    LocalForward ${local_port} ${remote_part}
"
            _cai_debug "LocalForward: $local_port -> $remote_part"
        fi
    done

    # Write the config file
    # Use StrictHostKeyChecking=accept-new which:
    # - Accepts new keys on first connection
    # - Rejects if key changes (MITM protection)
    # - Better than StrictHostKeyChecking=no which accepts everything
    if ! {
        cat <<EOF
# ContainAI SSH config for container: $container_name
# Auto-generated - do not edit manually
# Generated at: $(date -Iseconds 2>/dev/null || date)
#
# VS Code Remote-SSH: Use this Host name in Remote-SSH extension to connect.
# Example: Remote-SSH: Connect to Host... -> $container_name

Host $container_name
    HostName $_CAI_SSH_HOST
    AddressFamily inet
    Port $ssh_port
    User agent
    IdentityFile $identity_file
    IdentitiesOnly yes
    UserKnownHostsFile $known_hosts_file
    StrictHostKeyChecking $strict_host_key_checking
    # Disable password auth (key-only)
    PreferredAuthentications publickey
    # Faster connection (no GSSAPI, no password)
    GSSAPIAuthentication no
    PasswordAuthentication no
EOF

        # Add ForwardAgent directive (always explicit to override global config)
        printf '%s\n' "    # SSH agent forwarding (explicit to override global config)"
        printf '%s\n' "$forward_agent_line"

        # Add LocalForward entries if configured
        if [[ -n "$local_forward_lines" ]]; then
            printf '%s\n' "    # Port forwarding (from [ssh].local_forward config)"
            printf '%s' "$local_forward_lines"
        fi
    } >"$config_file"; then
        _cai_error "Failed to write SSH config: $config_file"
        return 1
    fi

    chmod 600 "$config_file"
    _cai_debug "SSH host config written: $config_file"
    _cai_info "SSH access configured: ssh $container_name"
    return 0
}

# Remove SSH host config for a container
# Arguments:
#   $1 = container name
# Returns: 0 always (idempotent)
#
# Removes ~/.ssh/containai.d/<container-name>.conf if it exists
_cai_remove_ssh_host_config() {
    local container_name="$1"
    local config_file="$_CAI_SSH_CONFIG_DIR/${container_name}.conf"

    if [[ -f "$config_file" ]]; then
        rm -f "$config_file"
        _cai_debug "Removed SSH host config: $config_file"
    fi
    return 0
}

# Complete SSH setup for a container after creation/start
# This is the main entry point for SSH setup, combining all steps
# Arguments:
#   $1 = container name
#   $2 = SSH port (on host)
#   $3 = docker context (optional)
#   $4 = force_update (optional, "true" for --fresh/new containers)
#   $5 = quick_check (optional, "true" for fast-path on running containers)
# Returns: 0=success, 1=failure
#
# Steps:
# 1. Wait for sshd to become ready (quick_check uses single attempt)
# 2. Inject public key to authorized_keys
# 3. Update known_hosts via ssh-keyscan (detects changes unless force_update)
# 4. Write SSH host config
_cai_setup_container_ssh() {
    local container_name="$1"
    local ssh_port="$2"
    local context="${3:-}"
    local force_update="${4:-false}"
    local quick_check="${5:-false}"

    _cai_step "Configuring SSH access for container $container_name"

    # Step 1: Wait for sshd (or quick check for already-running containers)
    if [[ "$quick_check" == "true" ]]; then
        # Fast path: single keyscan attempt for running containers
        # Avoids 30s wait if sshd/port is broken
        if ! _cai_timeout 3 ssh-keyscan -p "$ssh_port" -T 2 "$_CAI_SSH_HOST" >/dev/null 2>&1; then
            _cai_debug "Quick SSH check failed for port $ssh_port"
            return 1
        fi
    else
        if ! _cai_wait_for_sshd "$container_name" "$ssh_port" "$context"; then
            return 1
        fi
    fi

    # Step 2: Inject SSH key
    if ! _cai_inject_ssh_key "$container_name" "$context"; then
        return 1
    fi

    # Step 3: Update known_hosts (force_update bypasses change detection)
    if ! _cai_update_known_hosts "$container_name" "$ssh_port" "$context" "$force_update"; then
        return 1
    fi

    # Step 4: Write SSH host config
    if ! _cai_write_ssh_host_config "$container_name" "$ssh_port"; then
        return 1
    fi

    _cai_ok "SSH access configured for container $container_name"
    return 0
}

# Clean up SSH configuration for a container (on --fresh or container removal)
# Arguments:
#   $1 = container name
#   $2 = SSH port (on host)
# Returns: 0 always
#
# Removes:
# - SSH host config file
# - known_hosts entries for the port
_cai_cleanup_container_ssh() {
    local container_name="$1"
    local ssh_port="$2"

    _cai_debug "Cleaning up SSH configuration for container $container_name"

    # Remove SSH host config
    _cai_remove_ssh_host_config "$container_name"

    # Clean known_hosts entries for this port
    _cai_clean_known_hosts "$ssh_port"

    return 0
}

# ==============================================================================
# SSH Shell Connection
# ==============================================================================

# Exit codes for SSH shell connection
_CAI_SSH_EXIT_SUCCESS=0
_CAI_SSH_EXIT_CONTAINER_NOT_FOUND=10
_CAI_SSH_EXIT_CONTAINER_START_FAILED=11
_CAI_SSH_EXIT_SSH_SETUP_FAILED=12
_CAI_SSH_EXIT_SSH_CONNECT_FAILED=13
_CAI_SSH_EXIT_HOST_KEY_MISMATCH=14
_CAI_SSH_EXIT_CONTAINER_FOREIGN=15

# Connect to container via SSH with bulletproof connection handling
# This is the main entry point for SSH-based shell access
#
# Arguments:
#   $1 = container name
#   $2 = docker context (optional)
#   $3 = force_update (optional, "true" for --fresh containers)
#   $4 = quiet (optional, "true" to suppress verbose output)
#
# Returns:
#   0 = success (SSH session completed)
#   10 = container not found
#   11 = container start failed
#   12 = SSH setup failed
#   13 = SSH connection failed after retries
#   14 = host key mismatch (manual intervention required)
#   15 = container exists but not owned by ContainAI
#
# Features:
# - Retry on transient failures (connection refused, timeout)
# - Max 3 retries with exponential backoff
# - Auto-recover from stale host keys (when force_update=true)
# - Auto-regenerate missing SSH config
# - Clear error messages with remediation steps
# - Agent forwarding works if configured in host SSH
_cai_ssh_shell() {
    local container_name="$1"
    local context="${2:-}"
    local force_update="${3:-false}"
    local quiet="${4:-false}"

    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    # Get container state
    local container_state
    if ! container_state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' -- "$container_name" 2>/dev/null); then
        _cai_error "Container not found: $container_name"
        _cai_error ""
        _cai_error "To create a container for this workspace, run:"
        _cai_error "  cai run /path/to/workspace"
        return "$_CAI_SSH_EXIT_CONTAINER_NOT_FOUND"
    fi

    # Check ownership - verify this is a ContainAI container
    local label_val
    label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' -- "$container_name" 2>/dev/null) || label_val=""
    if [[ "$label_val" != "true" ]]; then
        # Fallback: check if image is from our repo (for legacy containers without label)
        local image_name
        image_name=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' -- "$container_name" 2>/dev/null) || image_name=""
        if ! _containai_is_our_image "$image_name"; then
            _cai_error "Container '$container_name' exists but was not created by ContainAI"
            _cai_error ""
            _cai_error "This is a name collision with a container not managed by ContainAI."
            _cai_error "Use a different workspace path or remove the conflicting container."
            return "$_CAI_SSH_EXIT_CONTAINER_FOREIGN"
        fi
    fi

    # Start container if not running
    if [[ "$container_state" != "running" ]]; then
        if [[ "$quiet" != "true" ]]; then
            _cai_info "Starting container $container_name..."
        fi
        if ! "${docker_cmd[@]}" start "$container_name" >/dev/null 2>&1; then
            _cai_error "Failed to start container: $container_name"
            _cai_error ""
            _cai_error "Check container logs for details:"
            _cai_error "  docker logs $container_name"
            return "$_CAI_SSH_EXIT_CONTAINER_START_FAILED"
        fi

        # Wait for container to be running
        local wait_count=0
        local max_wait=30
        while [[ $wait_count -lt $max_wait ]]; do
            local state
            state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' -- "$container_name" 2>/dev/null) || state=""
            if [[ "$state" == "running" ]]; then
                break
            fi
            sleep 0.5
            ((wait_count++))
        done
        if [[ $wait_count -ge $max_wait ]]; then
            _cai_error "Container failed to start within ${max_wait} attempts"
            return "$_CAI_SSH_EXIT_CONTAINER_START_FAILED"
        fi
    fi

    # Get SSH port from container label
    local ssh_port
    if ! ssh_port=$(_cai_get_container_ssh_port "$container_name" "$context"); then
        _cai_error "Container has no SSH port configured"
        _cai_error ""
        _cai_error "This container may have been created before SSH support was added."
        _cai_error "Recreate the container with: cai shell --fresh /path/to/workspace"
        return "$_CAI_SSH_EXIT_SSH_SETUP_FAILED"
    fi

    # Check if SSH config exists, regenerate if missing
    local config_file="$_CAI_SSH_CONFIG_DIR/${container_name}.conf"
    if [[ ! -f "$config_file" ]] || [[ "$force_update" == "true" ]]; then
        if [[ "$quiet" != "true" ]]; then
            _cai_info "Setting up SSH configuration..."
        fi

        # Full SSH setup (wait for sshd, inject key, update known_hosts, write config)
        if ! _cai_setup_container_ssh "$container_name" "$ssh_port" "$context" "$force_update"; then
            _cai_error "SSH setup failed for container $container_name"
            _cai_error ""
            _cai_error "Troubleshooting:"
            _cai_error "  1. Check container logs: docker logs $container_name"
            _cai_error "  2. Check sshd status: docker exec $container_name systemctl status ssh"
            _cai_error "  3. Try recreating: cai shell --fresh /path/to/workspace"
            return "$_CAI_SSH_EXIT_SSH_SETUP_FAILED"
        fi
    fi

    # Connect via SSH with retry logic
    if ! _cai_ssh_connect_with_retry "$container_name" "$ssh_port" "$context" "$quiet"; then
        return $? # Propagate specific exit code
    fi

    return "$_CAI_SSH_EXIT_SUCCESS"
}

# Connect to container via SSH with retry and auto-recovery
# Arguments:
#   $1 = container name
#   $2 = SSH port
#   $3 = docker context (optional)
#   $4 = quiet (optional)
# Returns: exit code from SSH or specific error codes
_cai_ssh_connect_with_retry() {
    local container_name="$1"
    local ssh_port="$2"
    local context="${3:-}"
    local quiet="${4:-false}"

    local max_retries=3
    local retry_count=0
    local wait_ms=500      # Start at 500ms
    local max_wait_ms=4000 # Cap at 4 seconds
    local ssh_exit_code
    local host_key_auto_recovered=false

    # Determine StrictHostKeyChecking value based on OpenSSH version
    local strict_host_key_checking
    if _cai_check_ssh_accept_new_support; then
        strict_host_key_checking="accept-new"
    else
        strict_host_key_checking="yes"
    fi

    while ((retry_count < max_retries)); do
        # Build SSH command with explicit options (does not depend on ~/.ssh/config)
        # This makes connection robust even if Include directive is missing/broken
        local -a ssh_cmd=(ssh)
        ssh_cmd+=(-o "HostName=$_CAI_SSH_HOST")
        ssh_cmd+=(-o "Port=$ssh_port")
        ssh_cmd+=(-o "User=agent")
        ssh_cmd+=(-o "IdentityFile=$_CAI_SSH_KEY_PATH")
        ssh_cmd+=(-o "IdentitiesOnly=yes")
        ssh_cmd+=(-o "UserKnownHostsFile=$_CAI_KNOWN_HOSTS_FILE")
        ssh_cmd+=(-o "StrictHostKeyChecking=$strict_host_key_checking")
        ssh_cmd+=(-o "PreferredAuthentications=publickey")
        ssh_cmd+=(-o "GSSAPIAuthentication=no")
        ssh_cmd+=(-o "PasswordAuthentication=no")
        ssh_cmd+=(-o "AddressFamily=inet")
        ssh_cmd+=(-o "ConnectTimeout=10")

        # Set ForwardAgent explicitly based on config (overrides any global SSH config)
        # Only enable if BOTH config allows AND SSH_AUTH_SOCK is available
        if [[ "${_CAI_SSH_FORWARD_AGENT:-}" == "true" ]] && [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
            ssh_cmd+=(-o "ForwardAgent=yes")
        else
            ssh_cmd+=(-o "ForwardAgent=no")
        fi

        # Force TTY allocation for interactive shell session
        # Use -tt (double t) to force pseudo-TTY even when stdin is not a terminal
        # This ensures shell always works even when stdin is piped/redirected
        ssh_cmd+=(-tt)

        # Connect to IPv4 loopback (explicit options override any host alias)
        ssh_cmd+=("$_CAI_SSH_HOST")

        # Start shell in workspace directory (matches cai run behavior)
        # Use exec $SHELL -l to get a proper login shell with .profile/.bashrc
        ssh_cmd+=("cd /home/agent/workspace && exec \$SHELL -l")

        if [[ "$quiet" != "true" && $retry_count -eq 0 ]]; then
            _cai_info "Connecting to container via SSH..."
        fi

        # Execute SSH and capture exit code + stderr for diagnostics
        local ssh_stderr_file
        ssh_stderr_file=$(mktemp)
        if "${ssh_cmd[@]}" 2>"$ssh_stderr_file"; then
            ssh_exit_code=0
        else
            ssh_exit_code=$?
        fi
        local ssh_stderr
        ssh_stderr=$(cat "$ssh_stderr_file" 2>/dev/null || true)
        rm -f "$ssh_stderr_file"

        # Check exit code and decide whether to retry
        case $ssh_exit_code in
            0)
                # Success
                if [[ "$host_key_auto_recovered" == "true" && "$quiet" != "true" ]]; then
                    _cai_info "Auto-recovered from stale host key"
                fi
                return "$_CAI_SSH_EXIT_SUCCESS"
                ;;
            255)
                # SSH error - analyze stderr to determine cause
                # Check for host key mismatch
                if printf '%s' "$ssh_stderr" | grep -qiE "host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED"; then
                    # Auto-recover: clean stale keys and retry (once)
                    if [[ "$host_key_auto_recovered" != "true" ]]; then
                        if [[ "$quiet" != "true" ]]; then
                            _cai_warn "SSH host key changed, auto-recovering..."
                        fi
                        _cai_clean_known_hosts "$ssh_port"
                        _cai_update_known_hosts "$container_name" "$ssh_port" "$context" "true" 2>/dev/null || true
                        host_key_auto_recovered=true
                        # Don't count this as a retry - it's auto-recovery
                        continue
                    fi
                    # Already tried auto-recovery, fail with guidance
                    _cai_error "SSH host key mismatch could not be auto-recovered"
                    _cai_error ""
                    _cai_error "Try recreating the container: cai shell --fresh /path/to/workspace"
                    return "$_CAI_SSH_EXIT_HOST_KEY_MISMATCH"
                fi

                # Check for non-transient errors that should not retry
                if printf '%s' "$ssh_stderr" | grep -qiE "permission denied|no such identity|could not resolve hostname|bad configuration|no route to host"; then
                    # Non-transient error - fail fast with clear message
                    _cai_error "SSH connection failed: non-transient error"
                    _cai_error ""
                    printf '%s\n' "$ssh_stderr" | while IFS= read -r line; do
                        [[ -n "$line" ]] && _cai_error "  $line"
                    done
                    _cai_error ""
                    _cai_error "Troubleshooting:"
                    if printf '%s' "$ssh_stderr" | grep -qiE "permission denied|no such identity"; then
                        _cai_error "  SSH key issue. Verify key exists: ls -la $_CAI_SSH_KEY_PATH"
                        _cai_error "  Or regenerate with: cai setup"
                    fi
                    return "$_CAI_SSH_EXIT_SSH_CONNECT_FAILED"
                fi

                # Connection refused or timeout - these are transient, retry
                retry_count=$((retry_count + 1))
                if ((retry_count < max_retries)); then
                    if [[ "$quiet" != "true" ]]; then
                        _cai_warn "SSH connection failed, retrying ($retry_count/$max_retries)..."
                    fi

                    # Exponential backoff
                    local sleep_sec
                    sleep_sec=$(awk "BEGIN {printf \"%.3f\", $wait_ms / 1000}")
                    sleep "$sleep_sec"
                    wait_ms=$((wait_ms * 2))
                    if ((wait_ms > max_wait_ms)); then
                        wait_ms=$max_wait_ms
                    fi

                    # On retry, ensure SSH is set up (sshd might have been slow to start)
                    _cai_setup_container_ssh "$container_name" "$ssh_port" "$context" "" "true" 2>/dev/null || true
                    continue
                fi

                # All retries exhausted
                _cai_error "SSH connection failed after $max_retries retries"
                _cai_error ""
                _cai_error "Troubleshooting:"
                _cai_error "  1. Check container is running: docker ps | grep $container_name"
                _cai_error "  2. Check sshd status: docker exec $container_name systemctl status ssh"
                _cai_error "  3. Check port mapping: docker port $container_name 22"
                _cai_error "  4. Test SSH manually: ssh -v -p $ssh_port agent@$_CAI_SSH_HOST"
                return "$_CAI_SSH_EXIT_SSH_CONNECT_FAILED"
                ;;
            *)
                # Other exit codes are from the remote shell session
                # Pass them through as-is (user's command exit code)
                return $ssh_exit_code
                ;;
        esac
    done

    return "$_CAI_SSH_EXIT_SSH_CONNECT_FAILED"
}

# ==============================================================================
# SSH Command Execution
# ==============================================================================

# Run a command in container via SSH
# This is the main entry point for SSH-based command execution (used by cai run)
#
# Arguments:
#   $1 = container name
#   $2 = docker context (optional)
#   $3 = force_update (optional, "true" for --fresh containers)
#   $4 = quiet (optional, "true" to suppress verbose output)
#   $5 = detached (optional, "true" for background execution)
#   $6 = allocate_tty (optional, "true" for interactive TTY)
#   $7+ = command and arguments to run (env vars can be passed as leading VAR=value args)
#
# Returns:
#   Exit code from the remote command, or error codes (10-15) on failure
#
# Features:
#   - Env vars: pass as leading VAR=value args before command (e.g., FOO=bar cmd args)
#   - TTY allocation for interactive commands (-t flag)
#   - Detached mode via nohup (background execution)
#   - Proper argument quoting/escaping
#   - Retry on transient failures
#   - Clear error messages with remediation steps
_cai_ssh_run() {
    local container_name="$1"
    local context="${2:-}"
    local force_update="${3:-false}"
    local quiet="${4:-false}"
    local detached="${5:-false}"
    local allocate_tty="${6:-false}"
    shift 6

    local -a cmd_args=("$@")

    local -a docker_cmd=(docker)
    if [[ -n "$context" ]]; then
        docker_cmd=(docker --context "$context")
    fi

    # Get container state
    local container_state
    if ! container_state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' -- "$container_name" 2>/dev/null); then
        _cai_error "Container not found: $container_name"
        _cai_error ""
        _cai_error "To create a container for this workspace, run:"
        _cai_error "  cai run /path/to/workspace"
        return "$_CAI_SSH_EXIT_CONTAINER_NOT_FOUND"
    fi

    # Check ownership - verify this is a ContainAI container
    local label_val
    label_val=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.managed"}}' -- "$container_name" 2>/dev/null) || label_val=""
    if [[ "$label_val" != "true" ]]; then
        # Fallback: check if image is from our repo (for legacy containers without label)
        local image_name
        image_name=$("${docker_cmd[@]}" inspect --format '{{.Config.Image}}' -- "$container_name" 2>/dev/null) || image_name=""
        if ! _containai_is_our_image "$image_name"; then
            _cai_error "Container '$container_name' exists but was not created by ContainAI"
            _cai_error ""
            _cai_error "This is a name collision with a container not managed by ContainAI."
            _cai_error "Use a different workspace path or remove the conflicting container."
            return "$_CAI_SSH_EXIT_CONTAINER_FOREIGN"
        fi
    fi

    # Start container if not running
    if [[ "$container_state" != "running" ]]; then
        if [[ "$quiet" != "true" ]]; then
            _cai_info "Starting container $container_name..."
        fi
        if ! "${docker_cmd[@]}" start "$container_name" >/dev/null 2>&1; then
            _cai_error "Failed to start container: $container_name"
            _cai_error ""
            _cai_error "Check container logs for details:"
            _cai_error "  docker logs $container_name"
            return "$_CAI_SSH_EXIT_CONTAINER_START_FAILED"
        fi

        # Wait for container to be running
        local wait_count=0
        local max_wait=30
        while [[ $wait_count -lt $max_wait ]]; do
            local state
            state=$("${docker_cmd[@]}" inspect --format '{{.State.Status}}' -- "$container_name" 2>/dev/null) || state=""
            if [[ "$state" == "running" ]]; then
                break
            fi
            sleep 0.5
            ((wait_count++))
        done
        if [[ $wait_count -ge $max_wait ]]; then
            _cai_error "Container failed to start within ${max_wait} attempts"
            return "$_CAI_SSH_EXIT_CONTAINER_START_FAILED"
        fi
    fi

    # Get SSH port from container label
    local ssh_port
    if ! ssh_port=$(_cai_get_container_ssh_port "$container_name" "$context"); then
        _cai_error "Container has no SSH port configured"
        _cai_error ""
        _cai_error "This container may have been created before SSH support was added."
        _cai_error "Recreate the container with: cai run --fresh /path/to/workspace"
        return "$_CAI_SSH_EXIT_SSH_SETUP_FAILED"
    fi

    # Check if SSH config exists, regenerate if missing
    local config_file="$_CAI_SSH_CONFIG_DIR/${container_name}.conf"
    if [[ ! -f "$config_file" ]] || [[ "$force_update" == "true" ]]; then
        if [[ "$quiet" != "true" ]]; then
            _cai_info "Setting up SSH configuration..."
        fi

        # Full SSH setup (wait for sshd, inject key, update known_hosts, write config)
        if ! _cai_setup_container_ssh "$container_name" "$ssh_port" "$context" "$force_update"; then
            _cai_error "SSH setup failed for container $container_name"
            _cai_error ""
            _cai_error "Troubleshooting:"
            _cai_error "  1. Check container logs: docker logs $container_name"
            _cai_error "  2. Check sshd status: docker exec $container_name systemctl status ssh"
            _cai_error "  3. Try recreating: cai run --fresh /path/to/workspace"
            return "$_CAI_SSH_EXIT_SSH_SETUP_FAILED"
        fi
    fi

    # Run command via SSH
    _cai_ssh_run_with_retry "$container_name" "$ssh_port" "$context" "$quiet" "$detached" "$allocate_tty" "${cmd_args[@]}"
}

# Run a command via SSH with retry and auto-recovery
# Arguments:
#   $1 = container name
#   $2 = SSH port
#   $3 = docker context (optional)
#   $4 = quiet (optional)
#   $5 = detached (optional, "true" for background execution)
#   $6 = allocate_tty (optional, "true" for interactive TTY)
#   $7+ = command and arguments
# Returns: exit code from SSH or specific error codes
_cai_ssh_run_with_retry() {
    local container_name="$1"
    local ssh_port="$2"
    local context="${3:-}"
    local quiet="${4:-false}"
    local detached="${5:-false}"
    local allocate_tty="${6:-false}"
    shift 6

    local -a cmd_args=("$@")

    local max_retries=3
    local retry_count=0
    local wait_ms=500      # Start at 500ms
    local max_wait_ms=4000 # Cap at 4 seconds
    local ssh_exit_code
    local host_key_auto_recovered=false

    # Determine StrictHostKeyChecking value based on OpenSSH version
    local strict_host_key_checking
    if _cai_check_ssh_accept_new_support; then
        strict_host_key_checking="accept-new"
    else
        strict_host_key_checking="yes"
    fi

    while ((retry_count < max_retries)); do
        # Build SSH command with explicit options (does not depend on ~/.ssh/config)
        local -a ssh_cmd=(ssh)
        ssh_cmd+=(-o "HostName=$_CAI_SSH_HOST")
        ssh_cmd+=(-o "Port=$ssh_port")
        ssh_cmd+=(-o "User=agent")
        ssh_cmd+=(-o "IdentityFile=$_CAI_SSH_KEY_PATH")
        ssh_cmd+=(-o "IdentitiesOnly=yes")
        ssh_cmd+=(-o "UserKnownHostsFile=$_CAI_KNOWN_HOSTS_FILE")
        ssh_cmd+=(-o "StrictHostKeyChecking=$strict_host_key_checking")
        ssh_cmd+=(-o "PreferredAuthentications=publickey")
        ssh_cmd+=(-o "GSSAPIAuthentication=no")
        ssh_cmd+=(-o "PasswordAuthentication=no")
        ssh_cmd+=(-o "AddressFamily=inet")
        ssh_cmd+=(-o "ConnectTimeout=10")

        # Note: SSH agent forwarding (-A) is intentionally NOT enabled by default.
        # Enabling it would grant the container access to the user's SSH keys,
        # which is a significant security expansion. If needed, users can manually
        # SSH into the container with: ssh -A <container-name>

        # Allocate TTY for interactive commands
        if [[ "$allocate_tty" == "true" ]]; then
            ssh_cmd+=(-t)
        fi

        # Connect to IPv4 loopback (explicit options override any host alias)
        ssh_cmd+=("$_CAI_SSH_HOST")

        # Build the remote command string
        # For detached mode, wrap with nohup and redirect output
        local remote_cmd=""
        if [[ ${#cmd_args[@]} -gt 0 ]]; then
            # Separate env vars (VAR=value) from actual command arguments
            local -a env_prefix_parts=()
            local -a actual_cmd_parts=()
            local arg
            local in_command=false

            for arg in "${cmd_args[@]}"; do
                if [[ "$in_command" == "false" && "$arg" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
                    # This is an environment variable assignment
                    local var_name="${arg%%=*}"
                    local var_value="${arg#*=}"
                    local quoted_value
                    quoted_value=$(printf '%q' "$var_value")
                    env_prefix_parts+=("${var_name}=${quoted_value}")
                else
                    # This is a command or command argument
                    in_command=true
                    local quoted_arg
                    quoted_arg=$(printf '%q' "$arg")
                    actual_cmd_parts+=("$quoted_arg")
                fi
            done

            # Build the full command string with env prefix
            local env_prefix=""
            if [[ ${#env_prefix_parts[@]} -gt 0 ]]; then
                env_prefix="${env_prefix_parts[*]} "
            fi

            local quoted_args=""
            if [[ ${#actual_cmd_parts[@]} -gt 0 ]]; then
                quoted_args="${actual_cmd_parts[*]}"
            fi

            if [[ "$detached" == "true" ]]; then
                # Run in background with nohup, redirect output to /dev/null
                # Use bash -lc wrapper for consistent command parsing (matches printf %q escaping)
                # printf %q produces bash-compatible output that can be safely passed to bash -c
                # We double-quote the entire command so bash -lc gets it as a single argument
                # Return PID so we can verify the process started
                local bash_cmd_arg
                bash_cmd_arg=$(printf '%q' "${env_prefix}${quoted_args}")
                remote_cmd="cd /home/agent/workspace && nohup bash -lc ${bash_cmd_arg} </dev/null >/dev/null 2>&1 & echo \$!"
            else
                # Run in foreground
                remote_cmd="cd /home/agent/workspace && ${env_prefix}${quoted_args}"
            fi
            ssh_cmd+=("$remote_cmd")
        fi

        # Show progress message for non-detached commands (before execution)
        # Detached mode message is shown AFTER PID verification
        if [[ "$quiet" != "true" && $retry_count -eq 0 && "$detached" != "true" ]]; then
            if [[ ${#cmd_args[@]} -gt 0 ]]; then
                _cai_info "Running command via SSH..."
            else
                _cai_info "Connecting to container via SSH..."
            fi
        fi

        # Execute SSH and capture exit code + stderr for diagnostics
        # For detached mode, also capture stdout to get the PID
        local ssh_stderr_file ssh_stdout_file
        ssh_stderr_file=$(mktemp)
        ssh_stdout_file=$(mktemp)
        if "${ssh_cmd[@]}" >"$ssh_stdout_file" 2>"$ssh_stderr_file"; then
            ssh_exit_code=0
        else
            ssh_exit_code=$?
        fi
        local ssh_stderr ssh_stdout
        ssh_stderr=$(cat "$ssh_stderr_file" 2>/dev/null || true)
        ssh_stdout=$(cat "$ssh_stdout_file" 2>/dev/null || true)
        rm -f "$ssh_stderr_file" "$ssh_stdout_file"

        # Check exit code and decide whether to retry
        case $ssh_exit_code in
            0)
                # Success
                if [[ "$host_key_auto_recovered" == "true" && "$quiet" != "true" ]]; then
                    _cai_info "Auto-recovered from stale host key"
                fi

                # For detached mode, verify the process actually started
                if [[ "$detached" == "true" ]]; then
                    local remote_pid
                    remote_pid=$(printf '%s' "$ssh_stdout" | tr -d '[:space:]')
                    if [[ -n "$remote_pid" && "$remote_pid" =~ ^[0-9]+$ ]]; then
                        # Verify process is running with kill -0 via a quick SSH check
                        local -a verify_ssh_cmd=(ssh)
                        verify_ssh_cmd+=(-o "HostName=$_CAI_SSH_HOST")
                        verify_ssh_cmd+=(-o "Port=$ssh_port")
                        verify_ssh_cmd+=(-o "User=agent")
                        verify_ssh_cmd+=(-o "IdentityFile=$_CAI_SSH_KEY_PATH")
                        verify_ssh_cmd+=(-o "IdentitiesOnly=yes")
                        verify_ssh_cmd+=(-o "UserKnownHostsFile=$_CAI_KNOWN_HOSTS_FILE")
                        verify_ssh_cmd+=(-o "StrictHostKeyChecking=$strict_host_key_checking")
                        verify_ssh_cmd+=(-o "ConnectTimeout=5")
                        verify_ssh_cmd+=(-n)  # Prevent reading stdin
                        verify_ssh_cmd+=("$_CAI_SSH_HOST")
                        verify_ssh_cmd+=("kill -0 $remote_pid 2>/dev/null && echo running")
                        local verify_result
                        verify_result=$("${verify_ssh_cmd[@]}" 2>/dev/null || true)
                        if [[ "$verify_result" == *"running"* ]]; then
                            if [[ "$quiet" != "true" ]]; then
                                _cai_info "Command running in background (PID: $remote_pid)"
                            fi
                        else
                            _cai_error "Background command failed to start (PID $remote_pid not found)"
                            return 1
                        fi
                    else
                        _cai_error "Background command failed: could not get PID"
                        return 1
                    fi
                else
                    # For non-detached mode, output any stdout
                    if [[ -n "$ssh_stdout" ]]; then
                        printf '%s\n' "$ssh_stdout"
                    fi
                fi
                return 0
                ;;
            255)
                # SSH error - analyze stderr to determine cause
                # Check for host key mismatch
                if printf '%s' "$ssh_stderr" | grep -qiE "host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED"; then
                    # Auto-recover: clean stale keys and retry (once)
                    if [[ "$host_key_auto_recovered" != "true" ]]; then
                        if [[ "$quiet" != "true" ]]; then
                            _cai_warn "SSH host key changed, auto-recovering..."
                        fi
                        _cai_clean_known_hosts "$ssh_port"
                        _cai_update_known_hosts "$container_name" "$ssh_port" "$context" "true" 2>/dev/null || true
                        host_key_auto_recovered=true
                        # Don't count this as a retry - it's auto-recovery
                        continue
                    fi
                    # Already tried auto-recovery, fail with guidance
                    _cai_error "SSH host key mismatch could not be auto-recovered"
                    _cai_error ""
                    _cai_error "Try recreating the container: cai run --fresh /path/to/workspace"
                    return "$_CAI_SSH_EXIT_HOST_KEY_MISMATCH"
                fi

                # Check for non-transient errors that should not retry
                if printf '%s' "$ssh_stderr" | grep -qiE "permission denied|no such identity|could not resolve hostname|bad configuration|no route to host"; then
                    # Non-transient error - fail fast with clear message
                    _cai_error "SSH connection failed: non-transient error"
                    _cai_error ""
                    printf '%s\n' "$ssh_stderr" | while IFS= read -r line; do
                        [[ -n "$line" ]] && _cai_error "  $line"
                    done
                    _cai_error ""
                    _cai_error "Troubleshooting:"
                    if printf '%s' "$ssh_stderr" | grep -qiE "permission denied|no such identity"; then
                        _cai_error "  SSH key issue. Verify key exists: ls -la $_CAI_SSH_KEY_PATH"
                        _cai_error "  Or regenerate with: cai setup"
                    fi
                    return "$_CAI_SSH_EXIT_SSH_CONNECT_FAILED"
                fi

                # Connection refused or timeout - these are transient, retry
                retry_count=$((retry_count + 1))
                if ((retry_count < max_retries)); then
                    if [[ "$quiet" != "true" ]]; then
                        _cai_warn "SSH connection failed, retrying ($retry_count/$max_retries)..."
                    fi

                    # Exponential backoff
                    local sleep_sec
                    sleep_sec=$(awk "BEGIN {printf \"%.3f\", $wait_ms / 1000}")
                    sleep "$sleep_sec"
                    wait_ms=$((wait_ms * 2))
                    if ((wait_ms > max_wait_ms)); then
                        wait_ms=$max_wait_ms
                    fi

                    # On retry, ensure SSH is set up (sshd might have been slow to start)
                    _cai_setup_container_ssh "$container_name" "$ssh_port" "$context" "" "true" 2>/dev/null || true
                    continue
                fi

                # All retries exhausted
                _cai_error "SSH connection failed after $max_retries retries"
                _cai_error ""
                _cai_error "Troubleshooting:"
                _cai_error "  1. Check container is running: docker ps | grep $container_name"
                _cai_error "  2. Check sshd status: docker exec $container_name systemctl status ssh"
                _cai_error "  3. Check port mapping: docker port $container_name 22"
                _cai_error "  4. Test SSH manually: ssh -v -p $ssh_port agent@$_CAI_SSH_HOST"
                return "$_CAI_SSH_EXIT_SSH_CONNECT_FAILED"
                ;;
            *)
                # Other exit codes are from the remote command
                # Pass them through as-is (propagate exit code)
                return $ssh_exit_code
                ;;
        esac
    done

    return "$_CAI_SSH_EXIT_SSH_CONNECT_FAILED"
}

# Build SSH command with environment variables prepended
# Arguments:
#   $1 = name of env vars array (array of VAR=value strings)
#   $2+ = command and arguments
# Outputs: the full command string with env vars prepended
# Example: _cai_build_ssh_cmd_with_env env_vars claude --print
#   -> "FOO=bar BAZ=qux claude --print"
_cai_build_ssh_cmd_with_env() {
    local env_array_name="$1"
    shift
    local -a cmd_args=("$@")

    # Build env var prefix
    local env_prefix=""
    local -n env_ref="$env_array_name" 2>/dev/null || true

    if [[ -n "${env_ref+x}" ]]; then
        local env_var
        for env_var in "${env_ref[@]}"; do
            # Validate env var format (VAR=value)
            if [[ "$env_var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*= ]]; then
                # Quote the value properly for shell
                local var_name="${env_var%%=*}"
                local var_value="${env_var#*=}"
                local quoted_value
                quoted_value=$(printf '%q' "$var_value")
                if [[ -z "$env_prefix" ]]; then
                    env_prefix="${var_name}=${quoted_value}"
                else
                    env_prefix="$env_prefix ${var_name}=${quoted_value}"
                fi
            fi
        done
    fi

    # Build command string
    local cmd_str=""
    local arg
    for arg in "${cmd_args[@]}"; do
        if [[ -z "$cmd_str" ]]; then
            cmd_str=$(printf '%q' "$arg")
        else
            cmd_str="$cmd_str $(printf '%q' "$arg")"
        fi
    done

    # Combine env prefix and command
    if [[ -n "$env_prefix" ]]; then
        printf '%s %s' "$env_prefix" "$cmd_str"
    else
        printf '%s' "$cmd_str"
    fi
}

# ==============================================================================
# SSH Cleanup
# ==============================================================================

# Check if a file is a ContainAI SSH config by validating its content markers
# Arguments:
#   $1 = config file path
# Returns: 0 if ContainAI config, 1 otherwise
_cai_is_containai_ssh_config() {
    local config_file="$1"

    # Check for ContainAI marker comment at the start of the file
    if head -1 "$config_file" 2>/dev/null | grep -qF "# ContainAI SSH config"; then
        return 0
    fi

    # Also check for IdentityFile pointing to our key as a secondary marker
    if grep -qF "$_CAI_SSH_KEY_PATH" "$config_file" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Clean up stale SSH configurations for containers that no longer exist
# Scans ~/.ssh/containai.d/*.conf and removes configs for non-existent containers
#
# Arguments:
#   $1 = dry_run (optional, "true" to show what would be cleaned without doing it)
#
# Returns: 0 on success, 1 on Docker unavailability
#
# Behavior:
# - Requires Docker to be available (aborts if not)
# - Scans all *.conf files in ~/.ssh/containai.d/
# - Validates each file is a ContainAI config (checks content markers)
# - Extracts container name from filename (<container-name>.conf)
# - Checks if corresponding container exists in any known Docker context
# - Removes config file and known_hosts entries for non-existent containers
# - Reports what was cleaned (or would be cleaned in dry-run mode)
# - Tracks actual successful removals vs. discovery count
# - Returns 0 even if nothing to clean (idempotent)
_cai_ssh_cleanup() {
    local dry_run="${1:-false}"
    local config_dir="$_CAI_SSH_CONFIG_DIR"

    local to_clean_count=0
    local skipped_count=0
    local foreign_count=0
    local success_count=0
    local fail_count=0

    # Use associative array for 1:1 mapping of config -> port
    # This prevents index mismatch when ports are missing
    declare -A config_to_port

    # Check if config directory exists
    if [[ ! -d "$config_dir" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            _cai_info "[dry-run] SSH config directory does not exist: $config_dir"
        else
            _cai_info "SSH config directory does not exist: $config_dir"
        fi
        _cai_info "Nothing to clean."
        return 0
    fi

    # Get list of config files
    local -a config_files=()
    local config_file
    for config_file in "$config_dir"/*.conf; do
        # Skip if glob didn't match anything (bash returns the literal glob pattern)
        if [[ ! -f "$config_file" ]]; then
            continue
        fi
        config_files+=("$config_file")
    done

    if [[ ${#config_files[@]} -eq 0 ]]; then
        _cai_info "No SSH configs found in $config_dir"
        _cai_info "Nothing to clean."
        return 0
    fi

    # CRITICAL: Verify Docker CLI is available before proceeding
    if ! command -v docker >/dev/null 2>&1; then
        _cai_error "Docker is not installed or not in PATH"
        _cai_error "Cannot verify container existence - aborting cleanup to prevent data loss"
        return 1
    fi

    # Build list of contexts to check and verify at least one is reachable
    # We check per-context reachability rather than requiring default context
    local -a contexts_to_check=()
    local -a reachable_contexts=()
    local default_secure_context="$_CAI_CONTAINAI_DOCKER_CONTEXT"
    local ctx

    # Always try default context
    contexts_to_check+=("")

    # Add containai-docker context if it exists
    if docker context inspect "$default_secure_context" >/dev/null 2>&1; then
        contexts_to_check+=("$default_secure_context")
    fi

    # Also check configured context if different
    local configured_context
    configured_context=$(_containai_resolve_secure_engine_context 2>/dev/null) || configured_context=""
    if [[ -n "$configured_context" && "$configured_context" != "$default_secure_context" ]]; then
        if docker context inspect "$configured_context" >/dev/null 2>&1; then
            contexts_to_check+=("$configured_context")
        fi
    fi

    # Check which contexts are actually reachable (with timeout to avoid hangs)
    for ctx in "${contexts_to_check[@]}"; do
        local -a docker_cmd=(docker)
        if [[ -n "$ctx" ]]; then
            docker_cmd=(docker --context "$ctx")
        fi

        # Use timeout wrapper to avoid hanging on wedged/remote daemons
        if _cai_timeout 5 "${docker_cmd[@]}" info >/dev/null 2>&1; then
            reachable_contexts+=("$ctx")
            _cai_debug "Docker context reachable: ${ctx:-default}"
        else
            _cai_debug "Docker context unreachable: ${ctx:-default}"
        fi
    done

    # CRITICAL: Abort if NO contexts are reachable
    # If we can't reach any Docker daemon, all inspect calls would fail and
    # we'd incorrectly delete ALL configs thinking containers don't exist
    if [[ ${#reachable_contexts[@]} -eq 0 ]]; then
        _cai_error "No Docker daemon is reachable"
        _cai_error "Cannot verify container existence - aborting cleanup to prevent data loss"
        _cai_error ""
        _cai_error "Troubleshooting:"
        _cai_error "  1. Check Docker is running: docker info"
        _cai_error "  2. Check containai-docker context: docker --context $_CAI_CONTAINAI_DOCKER_CONTEXT info"
        return 1
    fi

    # Use only reachable contexts for container checks
    contexts_to_check=("${reachable_contexts[@]}")

    _cai_step "Scanning SSH configs for stale entries"
    _cai_info "Found ${#config_files[@]} SSH config(s) in $config_dir"

    # Build list of configs to clean
    local -a configs_to_clean=()
    local basename container_name ssh_port container_exists ctx

    for config_file in "${config_files[@]}"; do
        basename=$(basename "$config_file")
        container_name="${basename%.conf}"

        # Validate this is a ContainAI config (not a foreign file)
        if ! _cai_is_containai_ssh_config "$config_file"; then
            _cai_debug "Skipping non-ContainAI config: $config_file"
            ((foreign_count++))
            continue
        fi

        # Extract SSH port from config file (Port line)
        # Store empty string if not found - associative array handles this correctly
        ssh_port=$(grep -E '^[[:space:]]*Port[[:space:]]+' "$config_file" 2>/dev/null | awk '{print $2}' | head -1) || ssh_port=""

        # Check if container exists in any context
        container_exists=false
        for ctx in "${contexts_to_check[@]}"; do
            local -a docker_cmd=(docker)
            if [[ -n "$ctx" ]]; then
                docker_cmd=(docker --context "$ctx")
            fi

            # Check if container exists (running or stopped)
            if "${docker_cmd[@]}" inspect --type container -- "$container_name" >/dev/null 2>&1; then
                container_exists=true
                break
            fi
        done

        if [[ "$container_exists" == "true" ]]; then
            _cai_debug "Container exists: $container_name (keeping config)"
            ((skipped_count++))
        else
            # Container doesn't exist - mark for cleanup
            configs_to_clean+=("$config_file")
            config_to_port["$config_file"]="$ssh_port"
            ((to_clean_count++))
        fi
    done

    # Report and perform cleanup
    if [[ $to_clean_count -eq 0 ]]; then
        local total_checked=$((skipped_count + foreign_count))
        _cai_info "All $skipped_count ContainAI SSH config(s) have existing containers."
        if [[ $foreign_count -gt 0 ]]; then
            _cai_info "($foreign_count non-ContainAI config(s) skipped)"
        fi
        _cai_info "Nothing to clean."
        return 0
    fi

    _cai_info ""
    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[dry-run] Would remove $to_clean_count stale SSH config(s):"
    else
        _cai_info "Removing $to_clean_count stale SSH config(s):"
    fi

    for config_file in "${configs_to_clean[@]}"; do
        basename=$(basename "$config_file")
        container_name="${basename%.conf}"
        ssh_port="${config_to_port[$config_file]:-}"

        if [[ "$dry_run" == "true" ]]; then
            _cai_info "  [dry-run] Would remove: $container_name"
            _cai_info "            Config: $config_file"
            if [[ -n "$ssh_port" ]]; then
                _cai_info "            Port: $ssh_port (would clean known_hosts)"
            fi
        else
            _cai_info "  Removing: $container_name"

            # Remove config file and track success/failure
            if rm -f "$config_file" 2>/dev/null; then
                _cai_debug "    Removed config: $config_file"
                ((success_count++))

                # Clean known_hosts entries for this port (only if config removal succeeded)
                if [[ -n "$ssh_port" ]]; then
                    _cai_clean_known_hosts "$ssh_port"
                    _cai_debug "    Cleaned known_hosts for port $ssh_port"
                fi
            else
                _cai_warn "    Failed to remove config: $config_file"
                ((fail_count++))
            fi
        fi
    done

    _cai_info ""
    if [[ "$dry_run" == "true" ]]; then
        _cai_info "[dry-run] Summary: Would remove $to_clean_count config(s), keep $skipped_count config(s)"
        if [[ $foreign_count -gt 0 ]]; then
            _cai_info "          ($foreign_count non-ContainAI config(s) ignored)"
        fi
    else
        if [[ $fail_count -gt 0 ]]; then
            _cai_warn "Cleaned $success_count stale SSH config(s), $fail_count failed, kept $skipped_count active config(s)"
        else
            _cai_ok "Cleaned $success_count stale SSH config(s), kept $skipped_count active config(s)"
        fi
        if [[ $foreign_count -gt 0 ]]; then
            _cai_info "($foreign_count non-ContainAI config(s) ignored)"
        fi
    fi

    return 0
}

return 0
