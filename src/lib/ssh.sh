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
#   _cai_find_available_port()   - Find first available port in SSH range (2300-2500)
#   _cai_allocate_ssh_port()     - Allocate SSH port for container (with reuse support)
#   _cai_get_container_ssh_port() - Get SSH port from container label
#   _cai_is_port_available()     - Check if a specific port is available
#
# Dependencies:
#   - Requires lib/core.sh for logging functions
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
_CAI_SSH_PORT_RANGE_START=2300
_CAI_SSH_PORT_RANGE_END=2500

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
            if ! ssh-keygen -y -f "$key_path" > "$pubkey_path" 2>/dev/null; then
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

        if (( major > min_major )) || { (( major == min_major )) && (( minor >= min_minor )); }; then
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
        if ! printf '%s\n' "$include_line" > "$ssh_config"; then
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
            } > "$temp_file"; then
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

# Get list of ports currently in use (listening TCP ports)
# Arguments: none
# Outputs: one port number per line (listening TCP ports only)
# Returns: 0 on success, 1 if ss command fails
_cai_get_used_ports() {
    local ss_output port line local_addr

    # Use ss -Htan (no header, TCP, all states, numeric) for reliability
    # Filter for LISTEN state only (ports actually bound)
    # Extract local address column and parse port number
    if ! ss_output=$(ss -Htan state listening 2>/dev/null); then
        # Fallback: try without state filter (older ss versions)
        if ! ss_output=$(ss -Htan 2>/dev/null); then
            _cai_debug "ss command failed, cannot determine used ports"
            return 1
        fi
        # Filter for LISTEN manually if state filter not supported
        ss_output=$(printf '%s' "$ss_output" | grep -E '^LISTEN' || true)
    fi

    # Parse output: extract port from Local Address column
    # ss -tan format: State Recv-Q Send-Q Local Address:Port Peer Address:Port
    # Local address can be:
    #   - *:port (all interfaces)
    #   - 0.0.0.0:port (IPv4 all)
    #   - [::]:port (IPv6 all)
    #   - 127.0.0.1:port (localhost)
    #   - [::1]:port (IPv6 localhost)
    printf '%s\n' "$ss_output" | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Extract local address:port (4th column in ss -tan output)
        # Handle both IPv4 (addr:port) and IPv6 ([addr]:port) formats
        local_addr=$(printf '%s' "$line" | awk '{print $4}')
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
#   $1 = port range start (optional, default: $_CAI_SSH_PORT_RANGE_START)
#   $2 = port range end (optional, default: $_CAI_SSH_PORT_RANGE_END)
# Outputs: available port number on success
# Returns: 0=port found, 1=all ports exhausted, 2=cannot check ports
#
# On exhaustion, outputs error message to stderr suggesting cleanup
_cai_find_available_port() {
    local range_start="${1:-$_CAI_SSH_PORT_RANGE_START}"
    local range_end="${2:-$_CAI_SSH_PORT_RANGE_END}"
    local used_ports port

    # Validate range
    if [[ ! "$range_start" =~ ^[0-9]+$ ]] || [[ ! "$range_end" =~ ^[0-9]+$ ]]; then
        _cai_error "Invalid port range: $range_start-$range_end"
        return 2
    fi
    if (( range_start >= range_end )); then
        _cai_error "Invalid port range: start ($range_start) must be less than end ($range_end)"
        return 2
    fi

    # Get list of used ports
    if ! used_ports=$(_cai_get_used_ports); then
        _cai_error "Cannot determine used ports (ss command failed)"
        _cai_error "Ensure 'ss' (iproute2) is installed"
        return 2
    fi

    # Convert to associative array for O(1) lookup
    local -A used_ports_map
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && used_ports_map["$line"]=1
    done <<< "$used_ports"

    # Find first available port in range
    for (( port = range_start; port <= range_end; port++ )); do
        if [[ -z "${used_ports_map[$port]:-}" ]]; then
            printf '%s' "$port"
            return 0
        fi
    done

    # All ports exhausted - provide actionable error
    _cai_error "All SSH ports in range $range_start-$range_end are in use"
    _cai_error ""
    _cai_error "To free up ports, you can:"
    _cai_error "  1. Run 'cai ssh cleanup' to remove stale SSH configs"
    _cai_error "  2. Stop unused containers: 'cai stop-all'"
    _cai_error "  3. Check which processes are using ports:"
    _cai_error "     ss -tlpn | grep -E ':2[3-5][0-9]{2}'"
    _cai_error ""
    return 1
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
    if ! port=$("${docker_cmd[@]}" inspect --format '{{index .Config.Labels "containai.ssh-port"}}' "$container_name" 2>/dev/null); then
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
#   $3 = port range start (optional)
#   $4 = port range end (optional)
# Outputs: allocated port number
# Returns: 0=success, 1=exhausted, 2=error
#
# Note: This does NOT update the container label - caller should do that
# when creating/updating the container
_cai_allocate_ssh_port() {
    local container_name="$1"
    local context="${2:-}"
    local range_start="${3:-$_CAI_SSH_PORT_RANGE_START}"
    local range_end="${4:-$_CAI_SSH_PORT_RANGE_END}"
    local existing_port used_ports line port_in_use

    # Check if container already has an allocated port
    if existing_port=$(_cai_get_container_ssh_port "$container_name" "$context"); then
        # Validate the existing port is a number and in range
        if [[ "$existing_port" =~ ^[0-9]+$ ]]; then
            if (( existing_port >= range_start && existing_port <= range_end )); then
                # Check if the port is still available
                if ! used_ports=$(_cai_get_used_ports); then
                    # Can't verify, assume it's fine (container may be stopped)
                    printf '%s' "$existing_port"
                    return 0
                fi

                # Check if port is in use by something OTHER than this container
                # Note: If the container is running, its port WILL be in use (by itself)
                # We consider that "available" for reuse
                port_in_use=false
                while IFS= read -r line; do
                    if [[ "$line" == "$existing_port" ]]; then
                        port_in_use=true
                        break
                    fi
                done <<< "$used_ports"

                # If port is not in use at all, reuse it
                if [[ "$port_in_use" == "false" ]]; then
                    _cai_debug "Reusing existing SSH port $existing_port for container $container_name"
                    printf '%s' "$existing_port"
                    return 0
                fi

                # Port is in use - check if it's by our container (if running)
                # For now, if container exists with this port, trust it
                # The container startup will handle any conflicts
                _cai_debug "SSH port $existing_port in use, will allocate new port"
            else
                _cai_debug "Existing SSH port $existing_port outside configured range, allocating new"
            fi
        fi
    fi

    # Allocate new port
    _cai_find_available_port "$range_start" "$range_end"
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
    done <<< "$used_ports"

    return 0
}

return 0
