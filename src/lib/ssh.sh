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

return 0
