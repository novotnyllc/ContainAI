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
    local dir config_file

    # Require workspace argument
    if [[ -z "$workspace" ]]; then
        workspace="$PWD"
    fi

    # Resolve workspace to absolute path - warn if invalid
    if ! dir=$(cd -- "$workspace" 2>/dev/null && pwd); then
        echo "[WARN] Invalid workspace path, using \$PWD: $workspace" >&2
        dir="$PWD"
    fi

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
# Workspace matching
# ==============================================================================

# Find the best matching workspace section from config JSON
# Arguments: stdin = config JSON, $1 = workspace path (absolute)
# Outputs: workspace key that matches (empty if none)
# Matches workspace paths using longest path prefix (segment boundary)
_containai_find_matching_workspace() {
    local workspace="$1"

    python3 -c "
import json
import sys
from pathlib import Path

config = json.load(sys.stdin)
workspace = Path(sys.argv[1]).resolve()

workspaces = config.get('workspace', {})
if not isinstance(workspaces, dict):
    sys.exit(0)

best_match = None
best_segments = 0

for path_str, section in workspaces.items():
    if not isinstance(section, dict):
        continue

    cfg_path = Path(path_str)

    # Skip relative paths (absolute only)
    if not cfg_path.is_absolute():
        continue

    cfg_path = cfg_path.resolve()

    # Check if workspace is under cfg_path
    try:
        workspace.relative_to(cfg_path)
        num_segments = len(cfg_path.parts)
        if num_segments > best_segments:
            best_match = path_str
            best_segments = num_segments
    except ValueError:
        pass

if best_match:
    print(best_match)
" "$workspace"
}

# ==============================================================================
# Config parsing
# ==============================================================================

# Parse config file for workspace matching
# Calls parse-toml.py and handles workspace section matching
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
    local script_dir config_json parse_stderr ws_key line

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

    # Create temp file for stderr capture with cleanup trap
    if ! parse_stderr=$(mktemp 2>/dev/null); then
        echo "[WARN] Failed to create temp file, cannot capture parse errors" >&2
        parse_stderr=""
    fi

    # Cleanup function for temp file
    _cleanup_parse_stderr() {
        [[ -n "$parse_stderr" ]] && rm -f "$parse_stderr"
    }

    # Call parse-toml.py --json to get full config (compact JSON for shell safety)
    if [[ -n "$parse_stderr" ]]; then
        if ! config_json=$(python3 "$script_dir/parse-toml.py" --file "$config_file" --json 2>"$parse_stderr"); then
            if [[ "$strict" == "strict" ]]; then
                echo "[ERROR] Failed to parse config file: $config_file" >&2
            else
                echo "[WARN] Failed to parse config file: $config_file" >&2
            fi
            if [[ -s "$parse_stderr" ]]; then
                cat "$parse_stderr" >&2
            fi
            _cleanup_parse_stderr
            if [[ "$strict" == "strict" ]]; then
                return 1
            fi
            return 0  # Graceful fallback in non-strict mode
        fi

        # Show any warnings from parse-toml.py
        if [[ -s "$parse_stderr" ]]; then
            cat "$parse_stderr" >&2
        fi
        _cleanup_parse_stderr
    else
        # No temp file available, stderr goes to parent stderr
        if ! config_json=$(python3 "$script_dir/parse-toml.py" --file "$config_file" --json 2>&1); then
            if [[ "$strict" == "strict" ]]; then
                echo "[ERROR] Failed to parse config file: $config_file" >&2
                return 1
            fi
            echo "[WARN] Failed to parse config file: $config_file" >&2
            return 0
        fi
    fi

    # Find matching workspace section (pass JSON via stdin to avoid argv exposure)
    ws_key=$(printf '%s' "$config_json" | _containai_find_matching_workspace "$workspace")

    # Extract data_volume with fallback chain (pass JSON via stdin):
    # 1. workspace.<key>.data_volume (if workspace matches)
    # 2. agent.data_volume
    # 3. (leave empty, caller uses default)
    local vol=""
    if [[ -n "$ws_key" ]]; then
        vol=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
ws = config.get('workspace', {}).get(sys.argv[1], {})
print(ws.get('data_volume', ''))
" "$ws_key")
    fi
    if [[ -z "$vol" ]]; then
        vol=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
print(config.get('agent', {}).get('data_volume', ''))
")
    fi
    _CAI_VOLUME="$vol"

    # Extract excludes with cumulative merge (pass JSON via stdin):
    # default_excludes + workspace.<key>.excludes (deduped)
    local excludes_output
    excludes_output=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
ws_key = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else ''

default_excludes = config.get('default_excludes', [])
if not isinstance(default_excludes, list):
    default_excludes = []

ws_excludes = []
if ws_key:
    ws = config.get('workspace', {}).get(ws_key, {})
    ws_excludes = ws.get('excludes', [])
    if not isinstance(ws_excludes, list):
        ws_excludes = []

# Dedupe preserving order
seen = {}
for item in default_excludes + ws_excludes:
    if isinstance(item, str) and item not in seen:
        # Skip multi-line values (security/safety)
        if '\n' not in item and '\r' not in item:
            seen[item] = True
            print(item)
" "$ws_key")

    # Parse excludes into array
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            _CAI_EXCLUDES+=("$line")
        fi
    done <<< "$excludes_output"

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
