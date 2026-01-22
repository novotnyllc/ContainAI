#!/usr/bin/env bash
# ==============================================================================
# ContainAI SSH Key Management
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _cai_setup_ssh_key()         - Generate dedicated SSH key for ContainAI
#   _cai_get_ssh_key_path()      - Return path to ContainAI SSH private key
#   _cai_get_ssh_pubkey_path()   - Return path to ContainAI SSH public key
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

return 0
