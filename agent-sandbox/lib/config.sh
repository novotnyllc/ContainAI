#!/usr/bin/env bash
# ==============================================================================
# ContainAI Config Loading & Volume Resolution
# ==============================================================================
# This file must be sourced, not executed directly.
#
# Provides configuration resolution for ContainAI with workspace overrides
# and exclude pattern support.
#
# Provides:
#   _containai_find_config        - Find config file by walking up from workspace
#   _containai_parse_config       - Parse config file via parse-toml.py
#   _containai_resolve_volume     - Resolve data volume with precedence
#   _containai_resolve_excludes   - Resolve cumulative excludes from config
#   _containai_validate_volume_name - Validate Docker volume name
#
# Global variables set by _containai_parse_config:
#   _CAI_VOLUME  - Resolved data volume name
#   _CAI_EXCLUDES - Bash array of exclude patterns
#
# Usage: source lib/config.sh
# ==============================================================================

# Require bash first (before using BASH_SOURCE)
if [ -z "${BASH_VERSION:-}" ]; then
    echo "[ERROR] lib/config.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/config.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/config.sh" >&2
    exit 1
fi

# Guard against re-sourcing side effects
if [[ -n "${_CAI_CONFIG_LOADED:-}" ]]; then
    return 0
fi
_CAI_CONFIG_LOADED=1

# Default volume name
: "${_CONTAINAI_DEFAULT_VOLUME:=sandbox-agent-data}"

# Global variables for parsed config (set by _containai_parse_config)
# Only initialize once (guarded above)
_CAI_VOLUME=""
_CAI_EXCLUDES=()

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
# Arguments: $1 = workspace path (default: $PWD, warns if invalid)
# Outputs: config file path (or empty if not found)
# Returns: 0 always (empty output = not found)
_containai_find_config() {
    local workspace="$1"
    local dir config_file git_root_found

    # Require workspace argument
    if [[ -z "$workspace" ]]; then
        workspace="$PWD"
    fi

    # Resolve workspace to absolute path - warn if invalid
    if ! dir=$(cd -- "$workspace" 2>/dev/null && pwd); then
        echo "[WARN] Invalid workspace path, using \$PWD: $workspace" >&2
        dir="$PWD"
    fi
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

    # Note: Do NOT check root filesystem (/.containai/config.toml) - security concern
    # Only repo-local and user-local configs are valid discovery targets

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
# JSON parsing helpers
# ==============================================================================

# Parse JSON using Python
# Arguments: $1 = JSON string, $2 = field to extract ("volume" or "excludes")
# Outputs: extracted value(s)
_containai_parse_json_python() {
    local json="$1"
    local field="$2"

    python3 -c "
import json, sys
data = json.loads(sys.argv[1])
if sys.argv[2] == 'volume':
    print(data.get('data_volume', ''))
elif sys.argv[2] == 'excludes':
    for exc in data.get('excludes', []):
        print(exc)
" "$json" "$field"
}

# Parse JSON to extract data_volume using Python
# Arguments: $1 = JSON string
# Outputs: data_volume value
_containai_extract_volume() {
    local json="$1"

    # Use Python for reliable JSON parsing (already required for parse-toml.py)
    _containai_parse_json_python "$json" "volume"
}

# Parse JSON to extract excludes array using Python
# Arguments: $1 = JSON string
# Outputs: excludes (newline-separated)
_containai_extract_excludes() {
    local json="$1"

    # Use Python for reliable JSON array parsing (already required for parse-toml.py)
    _containai_parse_json_python "$json" "excludes"
}

# ==============================================================================
# Config parsing
# ==============================================================================

# Parse config file for workspace matching
# Calls parse-toml.py and captures JSON output
# Arguments: $1 = config file, $2 = workspace path, $3 = strict mode (optional, "strict")
# Sets globals: _CAI_VOLUME, _CAI_EXCLUDES
# Returns: 0 on success, 1 on failure
#
# Behavior in normal mode:
# - If Python unavailable: warn and return 0 (use defaults)
# - If parse fails: warn and return 0 (use defaults)
# - Only hard fail (return 1) if config file doesn't exist
#
# Behavior in strict mode (explicit config):
# - If Python unavailable: error and return 1
# - If parse fails: error and return 1
# - Hard fail on any error (no graceful fallback)
_containai_parse_config() {
    local config_file="$1"
    local workspace="$2"
    local strict="${3:-}"
    local script_dir json_result line parse_stderr

    # Reset globals
    _CAI_VOLUME=""
    _CAI_EXCLUDES=()

    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        echo "[ERROR] Config file not found: $config_file" >&2
        return 1
    fi

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        if [[ "$strict" == "strict" ]]; then
            echo "[ERROR] Python required to parse config: $config_file" >&2
            return 1
        fi
        echo "[WARN] Python not found, cannot parse config. Using defaults." >&2
        return 0
    fi

    # Determine script directory (where parse-toml.py lives)
    script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Call parse-toml.py - outputs JSON: {"data_volume": "...", "excludes": [...]}
    # Capture stderr separately to avoid corrupting JSON output
    parse_stderr=$(mktemp)

    if ! json_result=$(python3 "$script_dir/parse-toml.py" "$config_file" "$workspace" 2>"$parse_stderr"); then
        if [[ "$strict" == "strict" ]]; then
            echo "[ERROR] Failed to parse config file: $config_file" >&2
        else
            echo "[WARN] Failed to parse config file: $config_file" >&2
        fi
        if [[ -s "$parse_stderr" ]]; then
            cat "$parse_stderr" >&2
        fi
        rm -f "$parse_stderr"
        if [[ "$strict" == "strict" ]]; then
            return 1
        fi
        return 0  # Graceful fallback in non-strict mode
    fi

    # Show any warnings from parse-toml.py (e.g., "skipping exclude with newline")
    if [[ -s "$parse_stderr" ]]; then
        cat "$parse_stderr" >&2
    fi
    rm -f "$parse_stderr"

    # Extract volume from JSON - guard against Python failures
    local extract_vol extract_exc
    if ! extract_vol=$(_containai_extract_volume "$json_result"); then
        if [[ "$strict" == "strict" ]]; then
            echo "[ERROR] Failed to extract volume from config JSON" >&2
            return 1
        fi
        echo "[WARN] Failed to extract volume from config JSON" >&2
        return 0
    fi
    _CAI_VOLUME="$extract_vol"

    # Extract excludes from JSON into array - guard against Python failures
    if ! extract_exc=$(_containai_extract_excludes "$json_result"); then
        if [[ "$strict" == "strict" ]]; then
            echo "[ERROR] Failed to extract excludes from config JSON" >&2
            return 1
        fi
        echo "[WARN] Failed to extract excludes from config JSON" >&2
        return 0
    fi

    # Parse excludes into array (empty lines are valid empty-string excludes per parse-toml.py,
    # but we skip them as they have no meaning for rsync --exclude)
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            _CAI_EXCLUDES+=("$line")
        fi
    done <<< "$extract_exc"

    return 0
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
    local config_file

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
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        echo "[WARN] Invalid workspace path, using \$PWD: $workspace" >&2
        workspace="$PWD"
    fi

    # 4. Find config file
    if [[ -n "$explicit_config" ]]; then
        # Explicit config: must exist
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    # 5. Parse config with workspace matching
    # Use strict mode for explicit config (fail on parse errors)
    # Use normal mode for discovered config (graceful fallback)
    if [[ -n "$config_file" ]]; then
        local strict_mode=""
        if [[ -n "$explicit_config" ]]; then
            strict_mode="strict"
        fi
        if ! _containai_parse_config "$config_file" "$workspace" "$strict_mode"; then
            # In strict mode, parse failure is fatal
            return 1
        fi
        if [[ -n "$_CAI_VOLUME" ]]; then
            # Validate volume name from config
            if ! _containai_validate_volume_name "$_CAI_VOLUME"; then
                echo "[ERROR] Invalid volume name in config: $_CAI_VOLUME" >&2
                return 1
            fi
            printf '%s' "$_CAI_VOLUME"
            return 0
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
# Returns: 0 on success, 1 on failure (explicit config missing or parse error)
# Note: Returns cumulative excludes (default_excludes + workspace excludes)
_containai_resolve_excludes() {
    local workspace="${1:-$PWD}"
    local explicit_config="${2:-}"
    local config_file

    # Resolve workspace to absolute path
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        echo "[WARN] Invalid workspace path, using \$PWD: $workspace" >&2
        workspace="$PWD"
    fi

    # Find config file
    if [[ -n "$explicit_config" ]]; then
        # Explicit config: must exist
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    # If no config found, return empty (no excludes)
    if [[ -z "$config_file" ]]; then
        return 0
    fi

    # Parse config - sets _CAI_EXCLUDES array
    # Use strict mode for explicit config (fail on parse errors)
    local strict_mode=""
    if [[ -n "$explicit_config" ]]; then
        strict_mode="strict"
    fi
    if ! _containai_parse_config "$config_file" "$workspace" "$strict_mode"; then
        # In strict mode, parse failure is fatal
        return 1
    fi

    # Output excludes (newline-separated)
    local exclude
    for exclude in "${_CAI_EXCLUDES[@]}"; do
        printf '%s\n' "$exclude"
    done
}

return 0
