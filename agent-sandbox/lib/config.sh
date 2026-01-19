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
# Global variables set by _containai_parse_config:
#   _CAI_VOLUME  - Resolved data volume name
#   _CAI_EXCLUDES - Bash array of exclude patterns
#
# Usage: source lib/config.sh
# ==============================================================================

# Detect direct execution (must be sourced, not executed)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[ERROR] lib/config.sh must be sourced, not executed directly" >&2
    echo "Usage: source lib/config.sh" >&2
    exit 1
fi

# Require bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "[ERROR] lib/config.sh requires bash" >&2
    return 1
fi

# Default volume name (read-only constant)
readonly _CONTAINAI_DEFAULT_VOLUME="sandbox-agent-data"

# Global variables for parsed config (set by _containai_parse_config)
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
# Arguments: $1 = workspace path (required, must be valid directory)
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
    if ! dir=$(cd "$workspace" 2>/dev/null && pwd); then
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
# JSON parsing helpers
# ==============================================================================

# Parse JSON using Python (fallback when jq not available)
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

# Parse JSON to extract data_volume
# Arguments: $1 = JSON string
# Outputs: data_volume value
_containai_extract_volume() {
    local json="$1"

    # Try jq first (faster, more robust)
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r '.data_volume // empty'
        return
    fi

    # Fall back to Python (already required for parse-toml.py)
    _containai_parse_json_python "$json" "volume"
}

# Parse JSON to extract excludes array
# Arguments: $1 = JSON string
# Outputs: excludes (newline-separated)
_containai_extract_excludes() {
    local json="$1"

    # Try jq first (faster, more robust)
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$json" | jq -r '.excludes[]? // empty'
        return
    fi

    # Fall back to Python (already required for parse-toml.py)
    _containai_parse_json_python "$json" "excludes"
}

# ==============================================================================
# Config parsing
# ==============================================================================

# Parse config file for workspace matching
# Calls parse-toml.py and captures JSON output
# Arguments: $1 = config file, $2 = workspace path
# Sets globals: _CAI_VOLUME, _CAI_EXCLUDES
# Returns: 0 on success (or graceful fallback), 1 only if config file missing
#
# Behavior:
# - If Python unavailable: warn and return 0 (use defaults)
# - If parse fails: warn and return 0 (use defaults)
# - Only hard fail (return 1) if config file doesn't exist when caller expects it
_containai_parse_config() {
    local config_file="$1"
    local workspace="$2"
    local script_dir json_result line

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
        echo "[WARN] Python not found, cannot parse config. Using defaults." >&2
        return 0
    fi

    # Determine script directory (where parse-toml.py lives)
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Call parse-toml.py - outputs JSON: {"data_volume": "...", "excludes": [...]}
    if ! json_result=$(python3 "$script_dir/parse-toml.py" "$config_file" "$workspace" 2>&1); then
        echo "[WARN] Failed to parse config file: $config_file" >&2
        echo "$json_result" >&2
        return 0  # Graceful fallback
    fi

    # Extract volume from JSON
    _CAI_VOLUME=$(_containai_extract_volume "$json_result")

    # Extract excludes from JSON into array
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            _CAI_EXCLUDES+=("$line")
        fi
    done < <(_containai_extract_excludes "$json_result")

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
    if ! workspace=$(cd "$workspace" 2>/dev/null && pwd); then
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
    # Note: _containai_parse_config only fails if file missing (which we checked above)
    # Python errors or parse errors result in graceful fallback (return 0, empty _CAI_VOLUME)
    if [[ -n "$config_file" ]]; then
        _containai_parse_config "$config_file" "$workspace"
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
# Returns: 0 on success, 1 only if explicit config file missing
# Note: Returns cumulative excludes (default_excludes + workspace excludes)
_containai_resolve_excludes() {
    local workspace="${1:-$PWD}"
    local explicit_config="${2:-}"
    local config_file

    # Resolve workspace to absolute path
    if ! workspace=$(cd "$workspace" 2>/dev/null && pwd); then
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
    _containai_parse_config "$config_file" "$workspace"

    # Output excludes (newline-separated)
    local exclude
    for exclude in "${_CAI_EXCLUDES[@]}"; do
        printf '%s\n' "$exclude"
    done
}

return 0
