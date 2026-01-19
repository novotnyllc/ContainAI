#!/usr/bin/env bash
# ==============================================================================
# ContainAI Config Loading & Volume Resolution
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides:
#   _containai_find_config        - Find config file by walking up from workspace
#   _containai_parse_config       - Parse config file via parse-toml.py
#   _containai_resolve_volume     - Resolve data volume with precedence
#   _containai_resolve_excludes   - Resolve cumulative excludes from config
#   _containai_validate_volume_name - Validate Docker volume name
#
# Usage: source lib/config.sh
# ==============================================================================

# Require bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/config.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Default volume name
_CONTAINAI_DEFAULT_VOLUME="${_CONTAINAI_DEFAULT_VOLUME:-sandbox-agent-data}"

# ==============================================================================
# Volume name validation
# ==============================================================================

# Validate Docker volume name pattern
# Pattern: ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$
# Length: 1-255 characters
# Returns: 0=valid, 1=invalid
_containai_validate_volume_name() {
    local name="$1"

    # Check length
    if [[ -z "$name" ]] || [[ ${#name} -gt 255 ]]; then
        return 1
    fi

    # Check pattern: must start with alphanumeric, followed by alphanumeric, underscore, dot, or dash
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        return 1
    fi

    return 0
}

# ==============================================================================
# Config discovery
# ==============================================================================

# Find config file by walking up from workspace path
# Checks: .containai/config.toml then falls back to XDG_CONFIG_HOME
# Arguments: $1 = workspace path (default: $PWD)
# Outputs: config file path (or empty if not found)
_containai_find_config() {
    local workspace="${1:-$PWD}"
    local dir config_file git_root_found

    # Resolve workspace to absolute path
    dir=$(cd "$workspace" 2>/dev/null && pwd) || dir="$PWD"
    git_root_found=false

    # Walk up directory tree looking for .containai/config.toml
    while [[ "$dir" != "/" ]]; do
        config_file="$dir/.containai/config.toml"
        if [[ -f "$config_file" ]]; then
            printf '%s' "$config_file"
            return 0
        fi

        # Check for git root (stop walking up after git root)
        # Use -e to handle both .git directory and .git file (worktrees/submodules)
        if [[ -e "$dir/.git" ]]; then
            git_root_found=true
            break
        fi

        dir=$(dirname "$dir")
    done

    # Only check root directory if we actually walked to / (no git root found)
    if [[ "$git_root_found" == "false" && -f "/.containai/config.toml" ]]; then
        printf '%s' "/.containai/config.toml"
        return 0
    fi

    # Fall back to XDG_CONFIG_HOME
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    config_file="$xdg_config/containai/config.toml"
    if [[ -f "$config_file" ]]; then
        printf '%s' "$config_file"
        return 0
    fi

    # Not found
    return 0
}

# ==============================================================================
# Config parsing
# ==============================================================================

# Parse config file for workspace matching
# Calls parse-toml.py with config and workspace path
# Arguments: $1 = config file, $2 = workspace path, $3 = strict mode (optional)
# Outputs: JSON with data_volume and excludes
# Returns: 0 on success, 1 on parse error
# When strict=true, errors cause hard failure. When false, errors warn and return empty.
_containai_parse_config() {
    local config_file="$1"
    local workspace="$2"
    local strict="${3:-false}"
    local script_dir json_result parse_stderr

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        if [[ "$strict" == "true" ]]; then
            echo "[ERROR] Python not found, cannot parse config: $config_file" >&2
            return 1
        fi
        echo "[WARN] Python not found, cannot parse config. Using default." >&2
        return 0
    fi

    # Determine script directory (where parse-toml.py lives)
    # Handle both sourced and direct execution contexts
    if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    else
        script_dir="$(cd "$(dirname "$0")/.." && pwd)"
    fi

    # Call parse-toml.py - outputs JSON: {"data_volume": "...", "excludes": [...]}
    parse_stderr=$(mktemp)
    if ! json_result=$(python3 "$script_dir/parse-toml.py" "$config_file" "$workspace" 2>"$parse_stderr"); then
        if [[ "$strict" == "true" ]]; then
            echo "[ERROR] Failed to parse config file: $config_file" >&2
            if [[ -s "$parse_stderr" ]]; then
                cat "$parse_stderr" >&2
            fi
            rm -f "$parse_stderr"
            return 1
        fi
        echo "[WARN] Failed to parse config file: $config_file" >&2
        if [[ -s "$parse_stderr" ]]; then
            cat "$parse_stderr" >&2
        fi
        rm -f "$parse_stderr"
        return 0  # Fall back to default, don't fail hard
    fi

    rm -f "$parse_stderr"
    printf '%s' "$json_result"
}

# Extract data_volume from JSON output (without jq dependency)
# Arguments: $1 = JSON string
# Outputs: data_volume value
_containai_extract_volume_from_json() {
    local json="$1"
    local data_volume

    # Use parameter expansion to extract value between quotes after "data_volume":
    data_volume="${json#*\"data_volume\":\"}"
    data_volume="${data_volume%%\"*}"

    printf '%s' "$data_volume"
}

# Extract excludes array from JSON output (without jq dependency)
# Arguments: $1 = JSON string
# Outputs: excludes array (newline-separated)
_containai_extract_excludes_from_json() {
    local json="$1"
    local excludes_json item

    # Extract the excludes array portion
    excludes_json="${json#*\"excludes\":\[}"
    excludes_json="${excludes_json%%\]*}"

    # If empty array, return nothing
    if [[ -z "$excludes_json" ]]; then
        return 0
    fi

    # Parse comma-separated quoted strings
    # Remove leading/trailing whitespace and split on ","
    local IFS=','
    local items
    read -ra items <<< "$excludes_json"

    for item in "${items[@]}"; do
        # Remove quotes and whitespace
        item="${item#\"}"
        item="${item%\"}"
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        if [[ -n "$item" ]]; then
            printf '%s\n' "$item"
        fi
    done
}

# ==============================================================================
# Volume resolution
# ==============================================================================

# Main volume resolver - determines the data volume to use
# Arguments: $1 = CLI --data-volume value (optional)
#            $2 = workspace path (default: $PWD)
#            $3 = explicit config path (optional)
# Outputs: volume name
# Precedence:
#   1. --data-volume CLI flag (skips config parsing entirely)
#   2. CONTAINAI_DATA_VOLUME env var (skips config parsing entirely)
#   3. Config file [workspace.<path>] section matching workspace
#   4. Config file [agent].data_volume
#   5. Default: sandbox-agent-data
_containai_resolve_volume() {
    local cli_volume="${1:-}"
    local workspace="${2:-$PWD}"
    local explicit_config="${3:-}"
    local config_file json_result volume

    # 1. CLI flag always wins - SKIP all config parsing
    if [[ -n "$cli_volume" ]]; then
        # Validate volume name
        if ! _containai_validate_volume_name "$cli_volume"; then
            echo "[ERROR] Invalid volume name: $cli_volume" >&2
            return 1
        fi
        printf '%s' "$cli_volume"
        return 0
    fi

    # 2. Environment variable always wins - SKIP all config parsing
    if [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
        # Validate volume name
        if ! _containai_validate_volume_name "$CONTAINAI_DATA_VOLUME"; then
            echo "[ERROR] Invalid volume name in CONTAINAI_DATA_VOLUME: $CONTAINAI_DATA_VOLUME" >&2
            return 1
        fi
        printf '%s' "$CONTAINAI_DATA_VOLUME"
        return 0
    fi

    # 3. Resolve workspace to absolute path
    workspace=$(cd "$workspace" 2>/dev/null && pwd) || workspace="$PWD"

    # 4. Find config file
    local strict_mode="false"
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
        strict_mode="true"  # Explicit config: fail hard on parse errors
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    # 5. Parse config with workspace matching
    if [[ -n "$config_file" ]]; then
        if ! json_result=$(_containai_parse_config "$config_file" "$workspace" "$strict_mode"); then
            # Strict mode already printed error
            return 1
        fi
        if [[ -n "$json_result" ]]; then
            volume=$(_containai_extract_volume_from_json "$json_result")
            if [[ -n "$volume" ]]; then
                # Validate volume name from config
                if ! _containai_validate_volume_name "$volume"; then
                    echo "[ERROR] Invalid volume name in config: $volume" >&2
                    return 1
                fi
                printf '%s' "$volume"
                return 0
            fi
        fi
    fi

    # 6. Default
    printf '%s' "$_CONTAINAI_DEFAULT_VOLUME"
}

# ==============================================================================
# Excludes resolution
# ==============================================================================

# Resolve excludes from config
# Arguments: $1 = workspace path (default: $PWD)
#            $2 = explicit config path (optional)
# Outputs: excludes array (newline-separated)
# Returns: 0 on success, 1 on error
# Note: Returns cumulative excludes (default_excludes + workspace excludes)
_containai_resolve_excludes() {
    local workspace="${1:-$PWD}"
    local explicit_config="${2:-}"
    local config_file json_result

    # Resolve workspace to absolute path
    workspace=$(cd "$workspace" 2>/dev/null && pwd) || workspace="$PWD"

    # Find config file
    local strict_mode="false"
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
        strict_mode="true"  # Explicit config: fail hard on parse errors
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    # If no config found, return empty (no excludes)
    if [[ -z "$config_file" ]]; then
        return 0
    fi

    # Parse config
    if ! json_result=$(_containai_parse_config "$config_file" "$workspace" "$strict_mode"); then
        # Strict mode already printed error
        return 1
    fi

    # Extract and output excludes
    if [[ -n "$json_result" ]]; then
        _containai_extract_excludes_from_json "$json_result"
    fi
}

# Return 0 when sourced
return 0 2>/dev/null || true
