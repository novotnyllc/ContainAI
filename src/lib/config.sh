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
#   _containai_resolve_agent      - Resolve agent from config
#   _containai_resolve_credentials - Resolve credentials mode from config
#   _containai_resolve_secure_engine_context - Resolve secure engine context from config
#   _containai_resolve_env_config - Resolve env config for allowlist-based env var import
#   _containai_resolve_import_additional_paths - Resolve [import].additional_paths from config
#   _containai_validate_volume_name - Validate Docker volume name
#
# Global variables set by _containai_parse_config:
#   _CAI_VOLUME   - Resolved data volume name
#   _CAI_EXCLUDES - Bash array of exclude patterns
#   _CAI_AGENT    - Default agent name
#   _CAI_CREDENTIALS - Credentials mode
#   _CAI_SECURE_ENGINE_CONTEXT - Secure engine context name override
#   _CAI_SSH_PORT_RANGE_START - SSH port range start (from [ssh] section)
#   _CAI_SSH_PORT_RANGE_END   - SSH port range end (from [ssh] section)
#   _CAI_SSH_FORWARD_AGENT    - ForwardAgent setting (from [ssh] section, "true" or empty)
#   _CAI_SSH_LOCAL_FORWARDS   - Bash array of LocalForward entries (from [ssh] section)
#   _CAI_CONTAINER_MEMORY     - Memory limit (from [container] section, e.g., "4g")
#   _CAI_CONTAINER_CPUS       - CPU limit (from [container] section, e.g., 2)
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
_CAI_SECURE_ENGINE_CONTEXT=""
_CAI_DANGER_ALLOW_HOST_CREDENTIALS=""
_CAI_DANGER_ALLOW_HOST_DOCKER_SOCKET=""
_CAI_SSH_PORT_RANGE_START=""
_CAI_SSH_PORT_RANGE_END=""
_CAI_SSH_FORWARD_AGENT=""
_CAI_SSH_LOCAL_FORWARDS=()
_CAI_CONTAINER_MEMORY=""
_CAI_CONTAINER_CPUS=""

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
    _CAI_AGENT=""
    _CAI_CREDENTIALS=""
    _CAI_SECURE_ENGINE_CONTEXT=""
    _CAI_DANGER_ALLOW_HOST_CREDENTIALS=""
    _CAI_DANGER_ALLOW_HOST_DOCKER_SOCKET=""
    _CAI_SSH_PORT_RANGE_START=""
    _CAI_SSH_PORT_RANGE_END=""
    _CAI_SSH_FORWARD_AGENT=""
    _CAI_SSH_LOCAL_FORWARDS=()
    _CAI_CONTAINER_MEMORY=""
    _CAI_CONTAINER_CPUS=""

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
            return 0 # Graceful fallback in non-strict mode
        fi

        # Show any warnings from parse-toml.py
        if [[ -s "$parse_stderr" ]]; then
            cat "$parse_stderr" >&2
        fi
        _cleanup_parse_stderr
    else
        # No temp file available, let stderr pass through to parent stderr
        # DO NOT use 2>&1 - that would capture stderr into config_json and corrupt JSON
        if ! config_json=$(python3 "$script_dir/parse-toml.py" --file "$config_file" --json); then
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

    # Extract agent default from config (agent.default or just 'agent' if string)
    local agent_default=""
    agent_default=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
agent_section = config.get('agent', {})
if isinstance(agent_section, dict):
    print(agent_section.get('default', ''))
")
    _CAI_AGENT="$agent_default"

    # Extract credentials.mode from config
    local creds_mode=""
    creds_mode=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
creds = config.get('credentials', {})
if isinstance(creds, dict):
    print(creds.get('mode', ''))
")
    _CAI_CREDENTIALS="$creds_mode"

    # Extract secure_engine.context_name from config
    # Validate: must be single-line string with safe characters for Docker context name
    local secure_engine_context=""
    secure_engine_context=$(printf '%s' "$config_json" | python3 -c "
import json, sys, re
config = json.load(sys.stdin)
se = config.get('secure_engine', {})
if isinstance(se, dict):
    ctx = se.get('context_name', '')
    if isinstance(ctx, str):
        # Reject multi-line or control characters
        if '\n' in ctx or '\r' in ctx or '\t' in ctx:
            print('[WARN] secure_engine.context_name contains control characters, ignoring', file=sys.stderr)
        # Docker context names: alphanumeric, underscore, dash (conservative set)
        elif not re.match(r'^[a-zA-Z0-9_-]*$', ctx):
            print('[WARN] secure_engine.context_name contains invalid characters, ignoring', file=sys.stderr)
        elif len(ctx) > 64:
            print('[WARN] secure_engine.context_name too long (>64 chars), ignoring', file=sys.stderr)
        else:
            print(ctx)
")
    _CAI_SECURE_ENGINE_CONTEXT="$secure_engine_context"

    # Extract [danger] section for unsafe opt-ins
    # These flags pre-enable features but CLI ack flags are still required for audit trail
    local danger_creds danger_socket
    danger_creds=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
danger = config.get('danger', {})
if isinstance(danger, dict):
    val = danger.get('allow_host_credentials', False)
    if val is True or str(val).lower() == 'true':
        print('true')
")
    danger_socket=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
danger = config.get('danger', {})
if isinstance(danger, dict):
    val = danger.get('allow_host_docker_socket', False)
    if val is True or str(val).lower() == 'true':
        print('true')
")
    _CAI_DANGER_ALLOW_HOST_CREDENTIALS="$danger_creds"
    _CAI_DANGER_ALLOW_HOST_DOCKER_SOCKET="$danger_socket"

    # Extract [ssh] section for port range configuration
    local ssh_port_start ssh_port_end
    ssh_port_start=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
ssh = config.get('ssh', {})
if isinstance(ssh, dict):
    val = ssh.get('port_range_start', '')
    if isinstance(val, int) and 1024 <= val <= 65535:
        print(val)
")
    ssh_port_end=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
ssh = config.get('ssh', {})
if isinstance(ssh, dict):
    val = ssh.get('port_range_end', '')
    if isinstance(val, int) and 1024 <= val <= 65535:
        print(val)
")
    _CAI_SSH_PORT_RANGE_START="$ssh_port_start"
    _CAI_SSH_PORT_RANGE_END="$ssh_port_end"

    # Extract [ssh] section for agent forwarding and local port forwards
    local ssh_forward_agent ssh_local_forwards_output
    ssh_forward_agent=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
ssh = config.get('ssh', {})
if isinstance(ssh, dict):
    val = ssh.get('forward_agent', False)
    if val is True or (isinstance(val, str) and val.lower() == 'true'):
        print('true')
")
    _CAI_SSH_FORWARD_AGENT="$ssh_forward_agent"

    # Extract local_forward array from [ssh] section
    # Format: 'localport:remotehost:remoteport' (e.g., '8080:localhost:8080')
    # Security: validates format, port ranges, rejects multi-line values
    ssh_local_forwards_output=$(printf '%s' "$config_json" | python3 -c "
import json, sys, re
config = json.load(sys.stdin)
ssh = config.get('ssh', {})
if not isinstance(ssh, dict):
    sys.exit(0)

local_forwards = ssh.get('local_forward', [])
if not isinstance(local_forwards, list):
    print('[WARN] [ssh].local_forward must be a list, ignoring', file=sys.stderr)
    sys.exit(0)

# Pattern for LocalForward: localport:remotehost:remoteport
# remotehost: hostname with alphanumeric, dots, underscores, dashes
# Note: Does NOT support bind_address:port:host:port or IPv6 formats
pattern = re.compile(r'^([0-9]+):([a-zA-Z0-9._-]+):([0-9]+)$')

for i, item in enumerate(local_forwards):
    if not isinstance(item, str):
        print(f'[WARN] [ssh].local_forward[{i}] must be a string, skipping', file=sys.stderr)
        continue
    # Reject multi-line values (security)
    if '\n' in item or '\r' in item:
        print(f'[WARN] [ssh].local_forward[{i}] contains newlines, skipping', file=sys.stderr)
        continue
    # Validate format
    match = pattern.match(item)
    if not match:
        print(f'[WARN] [ssh].local_forward[{i}] invalid format \"{item}\", expected localport:host:port, skipping', file=sys.stderr)
        continue
    # Validate port ranges (1-65535)
    local_port = int(match.group(1))
    remote_port = int(match.group(3))
    if not (1 <= local_port <= 65535):
        print(f'[WARN] [ssh].local_forward[{i}] local port {local_port} out of range (1-65535), skipping', file=sys.stderr)
        continue
    if not (1 <= remote_port <= 65535):
        print(f'[WARN] [ssh].local_forward[{i}] remote port {remote_port} out of range (1-65535), skipping', file=sys.stderr)
        continue
    print(item)
")
    # Parse local_forward entries into array
    local line
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            _CAI_SSH_LOCAL_FORWARDS+=("$line")
        fi
    done <<<"$ssh_local_forwards_output"

    # Extract [container] section for resource limits
    local container_memory container_cpus
    container_memory=$(printf '%s' "$config_json" | python3 -c "
import json, sys, re
config = json.load(sys.stdin)
container = config.get('container', {})
if isinstance(container, dict):
    val = container.get('memory', '')
    if isinstance(val, str) and val:
        # Validate memory format: number followed by unit (k, m, g, t)
        if re.match(r'^[0-9]+(\.[0-9]+)?[kmgtKMGT]?$', val):
            print(val)
        else:
            print('[WARN] container.memory invalid format, ignoring', file=sys.stderr)
")
    container_cpus=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
container = config.get('container', {})
if isinstance(container, dict):
    val = container.get('cpus', '')
    # Accept int or float, must be positive
    if isinstance(val, (int, float)) and val > 0:
        print(val)
    elif isinstance(val, str) and val:
        print('[WARN] container.cpus should be a number, not a string', file=sys.stderr)
")
    _CAI_CONTAINER_MEMORY="$container_memory"
    _CAI_CONTAINER_CPUS="$container_cpus"

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
    done <<<"$excludes_output"

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

# ==============================================================================
# Agent resolution
# ==============================================================================

# Resolve agent from CLI or config
# Arguments: $1 = CLI --agent value (optional)
#            $2 = workspace path (default: $PWD)
#            $3 = explicit config path (optional)
# Outputs: agent name (claude, gemini, etc.)
# Precedence:
#   1. --agent CLI flag
#   2. CONTAINAI_AGENT env var
#   3. Config file [agent].default
#   4. Default: claude
_containai_resolve_agent() {
    local cli_agent="${1:-}"
    local workspace="${2:-$PWD}"
    local explicit_config="${3:-}"
    local config_file

    # 1. CLI flag always wins
    if [[ -n "$cli_agent" ]]; then
        printf '%s' "$cli_agent"
        return 0
    fi

    # 2. Environment variable
    if [[ -n "${CONTAINAI_AGENT:-}" ]]; then
        printf '%s' "$CONTAINAI_AGENT"
        return 0
    fi

    # 3. Resolve workspace to absolute path
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        workspace="$PWD"
    fi

    # 4. Find and parse config file
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            # Config not found, fall through to default
            printf '%s' "claude"
            return 0
        fi
        config_file="$explicit_config"
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    if [[ -n "$config_file" ]]; then
        local strict_mode=""
        if [[ -n "$explicit_config" ]]; then
            strict_mode="strict"
        fi
        if _containai_parse_config "$config_file" "$workspace" "$strict_mode"; then
            if [[ -n "$_CAI_AGENT" ]]; then
                printf '%s' "$_CAI_AGENT"
                return 0
            fi
        fi
    fi

    # 5. Default
    printf '%s' "claude"
}

# ==============================================================================
# Credentials resolution
# ==============================================================================

# Resolve credentials mode from CLI or config
# Arguments: $1 = CLI --credentials value (optional)
#            $2 = workspace path (default: $PWD)
#            $3 = explicit config path (optional)
#            $4 = unused (kept for API compatibility)
# Outputs: credentials mode (none, host)
# Precedence:
#   1. --credentials CLI flag
#   2. CONTAINAI_CREDENTIALS env var
#   3. Config file [credentials].mode (but NEVER returns 'host' from config)
#   4. Default: none
# SECURITY: Config credentials.mode=host is ALWAYS ignored. Users must explicitly
#           pass --credentials=host on the CLI to use host credentials. This ensures
#           config files cannot escalate privileges without explicit user action.
_containai_resolve_credentials() {
    local cli_credentials="${1:-}"
    local workspace="${2:-$PWD}"
    local explicit_config="${3:-}"
    # $4 is unused but kept for API compatibility
    local config_file

    # 1. CLI flag always wins (validation happens in caller)
    if [[ -n "$cli_credentials" ]]; then
        printf '%s' "$cli_credentials"
        return 0
    fi

    # 2. Environment variable
    if [[ -n "${CONTAINAI_CREDENTIALS:-}" ]]; then
        printf '%s' "$CONTAINAI_CREDENTIALS"
        return 0
    fi

    # 3. Resolve workspace to absolute path
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        workspace="$PWD"
    fi

    # 4. Find and parse config file
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            # Config not found, fall through to default
            printf '%s' "none"
            return 0
        fi
        config_file="$explicit_config"
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    if [[ -n "$config_file" ]]; then
        local strict_mode=""
        if [[ -n "$explicit_config" ]]; then
            strict_mode="strict"
        fi
        if _containai_parse_config "$config_file" "$workspace" "$strict_mode"; then
            if [[ -n "$_CAI_CREDENTIALS" ]]; then
                # SECURITY: NEVER allow config to set credentials=host
                # Host credentials require explicit --credentials=host on CLI
                if [[ "$_CAI_CREDENTIALS" == "host" ]]; then
                    # Silently ignore host from config - use default instead
                    printf '%s' "none"
                    return 0
                fi
                printf '%s' "$_CAI_CREDENTIALS"
                return 0
            fi
        fi
    fi

    # 5. Default
    printf '%s' "none"
}

# ==============================================================================
# Secure Engine context resolution
# ==============================================================================

# Validate secure engine context name
# Arguments: $1 = context name
# Returns: 0=valid, 1=invalid
# Outputs: warning to stderr if invalid
_containai_validate_context_name() {
    local ctx="$1"

    # Empty is valid (means use default)
    if [[ -z "$ctx" ]]; then
        return 0
    fi

    # Check for control characters
    if [[ "$ctx" == *$'\n'* ]] || [[ "$ctx" == *$'\r'* ]] || [[ "$ctx" == *$'\t'* ]]; then
        echo "[WARN] Context name contains control characters" >&2
        return 1
    fi

    # Docker context names: alphanumeric, underscore, dash
    if [[ ! "$ctx" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "[WARN] Context name contains invalid characters" >&2
        return 1
    fi

    # Length check
    if [[ ${#ctx} -gt 64 ]]; then
        echo "[WARN] Context name too long (>64 chars)" >&2
        return 1
    fi

    return 0
}

# Resolve secure engine context name from config
# Arguments: $1 = workspace path (default: $PWD)
#            $2 = explicit config path (optional)
# Outputs: context name (empty if not configured)
# Returns: 0 on success, 1 on failure (strict mode parse error)
# Precedence:
#   1. CONTAINAI_SECURE_ENGINE_CONTEXT env var
#   2. Config file [secure_engine].context_name
#   3. Default: "" (empty, let caller decide)
_containai_resolve_secure_engine_context() {
    local workspace="${1:-$PWD}"
    local explicit_config="${2:-}"
    local config_file

    # 1. Environment variable (with validation)
    if [[ -n "${CONTAINAI_SECURE_ENGINE_CONTEXT:-}" ]]; then
        if _containai_validate_context_name "$CONTAINAI_SECURE_ENGINE_CONTEXT"; then
            printf '%s' "$CONTAINAI_SECURE_ENGINE_CONTEXT"
            return 0
        else
            echo "[WARN] Ignoring invalid CONTAINAI_SECURE_ENGINE_CONTEXT" >&2
            # Fall through to config/default
        fi
    fi

    # 2. Resolve workspace to absolute path
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        workspace="$PWD"
    fi

    # 3. Find and parse config file
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    if [[ -n "$config_file" ]]; then
        local strict_mode=""
        if [[ -n "$explicit_config" ]]; then
            strict_mode="strict"
        fi
        if ! _containai_parse_config "$config_file" "$workspace" "$strict_mode"; then
            # Parse failed - in strict mode this is fatal
            if [[ "$strict_mode" == "strict" ]]; then
                return 1
            fi
            # Non-strict: fall through to default
        elif [[ -n "$_CAI_SECURE_ENGINE_CONTEXT" ]]; then
            printf '%s' "$_CAI_SECURE_ENGINE_CONTEXT"
            return 0
        fi
    fi

    # 4. Default: empty (let caller decide)
    return 0
}

# ==============================================================================
# Env config resolution (for allowlist-based env var import)
# ==============================================================================

# Resolve env config from config file for env var import
# This is INDEPENDENT of volume/excludes resolution (runs even with --data-volume or --no-excludes)
#
# Arguments: $1 = workspace path (default: $PWD)
#            $2 = explicit config path (optional)
# Outputs: JSON with keys: import (array), from_host (bool), env_file (string or null)
#          Returns default JSON if [env] section missing or Python unavailable
# Returns: 0 on success, 1 on fatal error (explicit config missing or strict parse error)
#
# Behavior:
# - Missing [env] section: returns defaults (import=[], from_host=false, env_file=null)
# - [env] exists but import missing/invalid: returns import=[] with [WARN] (from parse-toml.py)
# - Python unavailable (discovered config): returns defaults with [WARN]
# - Python unavailable (explicit config): return 1 (fail fast, matches epic spec)
# - Env config is global-only (no workspace-specific overrides per spec)
_containai_resolve_env_config() {
    local workspace="${1:-$PWD}"
    local explicit_config="${2:-}"
    local config_file script_dir env_json

    # Default JSON output (for missing config or Python unavailable)
    # _section_present=false indicates [env] section is missing (silent skip)
    local default_json='{"import":[],"from_host":false,"env_file":null,"_section_present":false}'

    # Resolve workspace to absolute path (preserve original for warning message)
    local workspace_input="$workspace"
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        printf '%s\n' "[WARN] Invalid workspace path, using \$PWD: $workspace_input" >&2
        workspace="$PWD"
    fi

    # Find config file
    if [[ -n "$explicit_config" ]]; then
        # Explicit config: must exist
        if [[ ! -f "$explicit_config" ]]; then
            printf '%s\n' "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    # If no config found, return defaults
    if [[ -z "$config_file" ]]; then
        printf '%s' "$default_json"
        return 0
    fi

    # Check if config file exists (for discovered config)
    if [[ ! -f "$config_file" ]]; then
        printf '%s' "$default_json"
        return 0
    fi

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        if [[ -n "$explicit_config" ]]; then
            printf '%s\n' "[ERROR] Python required to parse config: $config_file" >&2
            return 1
        fi
        printf '%s\n' "[WARN] Python not found, cannot parse config. Using defaults." >&2
        printf '%s' "$default_json"
        return 0
    fi

    # Determine script directory (where parse-toml.py lives)
    # Guard with if/else for set -e safety; fail fast in strict mode
    if ! script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; then
        if [[ -n "$explicit_config" ]]; then
            printf '%s\n' "[ERROR] Failed to determine script directory" >&2
            return 1
        fi
        printf '%s\n' "[WARN] Failed to determine script directory. Using defaults." >&2
        printf '%s' "$default_json"
        return 0
    fi

    # Call parse-toml.py --env to extract and validate [env] section
    # The script handles validation and returns JSON (or null if [env] missing)
    # IMPORTANT: Do NOT use 2>&1 - that would capture stderr into env_json and corrupt JSON
    # Let stderr from parse-toml.py (warnings) pass through to parent stderr
    if ! env_json=$(python3 "$script_dir/parse-toml.py" --file "$config_file" --env); then
        # Parse failed - check if strict mode applies
        if [[ -n "$explicit_config" ]]; then
            printf '%s\n' "[ERROR] Failed to parse config file: $config_file" >&2
            return 1
        fi
        printf '%s\n' "[WARN] Failed to parse config file: $config_file" >&2
        printf '%s' "$default_json"
        return 0
    fi

    # parse-toml.py --env returns "null" (JSON null) if [env] section is missing
    # Convert null to defaults
    if [[ "$env_json" == "null" ]]; then
        printf '%s' "$default_json"
        return 0
    fi

    # parse-toml.py may not include env_file key if not present - ensure consistent output
    # Use Python to normalize the output with all expected keys
    # _section_present=true indicates [env] section exists (for proper logging behavior)
    local normalized_json
    if ! normalized_json=$(printf '%s' "$env_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Ensure all keys present with defaults
# _section_present=true since we only reach here if [env] section exists
result = {
    'import': data.get('import', []),
    'from_host': data.get('from_host', False),
    'env_file': data.get('env_file', None),
    '_section_present': True
}
print(json.dumps(result, separators=(',', ':')))
"); then
        # Fail fast in strict mode; graceful fallback otherwise
        if [[ -n "$explicit_config" ]]; then
            printf '%s\n' "[ERROR] Failed to normalize env config JSON" >&2
            return 1
        fi
        printf '%s\n' "[WARN] Failed to normalize env config JSON" >&2
        printf '%s' "$default_json"
        return 0
    fi

    printf '%s' "$normalized_json"
    return 0
}

# ==============================================================================
# Import config resolution (for additional_paths)
# ==============================================================================

# Resolve [import].additional_paths from config
# Validates paths and outputs newline-delimited list of validated paths
#
# Arguments: $1 = workspace path (default: $PWD)
#            $2 = explicit config path (optional)
# Outputs: Validated paths (newline-separated), each as absolute path under $HOME
# Returns: 0 on success, 1 on fatal error (explicit config missing or strict parse error)
#
# Path validation rules (per spec):
# - Must start with ~/ or be absolute under $HOME
# - No path traversal (/../ or /.. segments)
# - Paths are resolved to absolute form for output
#
# Behavior:
# - Missing [import] section: returns empty (silent)
# - Missing additional_paths key: returns empty (silent)
# - Invalid additional_paths type: returns empty with [WARN]
# - Invalid path entries: skipped with [WARN]
# - Python unavailable (discovered config): returns empty with [WARN]
# - Python unavailable (explicit config): return 1 (fail fast)
_containai_resolve_import_additional_paths() {
    local workspace="${1:-$PWD}"
    local explicit_config="${2:-}"
    local config_file script_dir paths_output

    # Resolve workspace to absolute path (preserve original for warning message)
    local workspace_input="$workspace"
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        printf '%s\n' "[WARN] Invalid workspace path, using \$PWD: $workspace_input" >&2
        workspace="$PWD"
    fi

    # Find config file
    if [[ -n "$explicit_config" ]]; then
        # Explicit config: must exist
        if [[ ! -f "$explicit_config" ]]; then
            printf '%s\n' "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    # If no config found, return empty (no additional paths)
    if [[ -z "$config_file" ]]; then
        return 0
    fi

    # Check if config file exists (for discovered config)
    if [[ ! -f "$config_file" ]]; then
        return 0
    fi

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        if [[ -n "$explicit_config" ]]; then
            printf '%s\n' "[ERROR] Python required to parse config: $config_file" >&2
            return 1
        fi
        printf '%s\n' "[WARN] Python not found, cannot parse config. Skipping additional paths." >&2
        return 0
    fi

    # Determine script directory (where parse-toml.py lives)
    if ! script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; then
        if [[ -n "$explicit_config" ]]; then
            printf '%s\n' "[ERROR] Failed to determine script directory" >&2
            return 1
        fi
        printf '%s\n' "[WARN] Failed to determine script directory. Skipping additional paths." >&2
        return 0
    fi

    # Call parse-toml.py --json to get full config, then extract and validate [import].additional_paths
    # Python handles validation: must be under $HOME, no traversal
    # Let stderr through for explicit config (useful diagnostics), suppress for discovered
    local config_json parse_stderr
    if [[ -n "$explicit_config" ]]; then
        # Explicit config: let parse errors through to stderr
        if ! config_json=$(python3 "$script_dir/parse-toml.py" --file "$config_file" --json); then
            printf '%s\n' "[ERROR] Failed to parse config file: $config_file" >&2
            return 1
        fi
    else
        # Discovered config: suppress stderr, warn on failure
        if ! config_json=$(python3 "$script_dir/parse-toml.py" --file "$config_file" --json 2>/dev/null); then
            printf '%s\n' "[WARN] Failed to parse config file: $config_file" >&2
            return 0
        fi
    fi

    # Extract and validate additional_paths using Python
    # Pass HOME for tilde expansion and validation
    # SECURITY: Do NOT use Path.resolve() as it follows symlinks
    # Use os.path.abspath + normpath for lexical normalization only
    if ! paths_output=$(printf '%s' "$config_json" | python3 -c "
import json
import sys
import os

config = json.load(sys.stdin)
home = os.environ.get('HOME', '')
if not home:
    sys.exit(0)

# Normalize HOME without following symlinks
home_normalized = os.path.normpath(os.path.abspath(home))

import_section = config.get('import', {})
if not isinstance(import_section, dict):
    # [import] exists but is not a table - warn and treat as empty
    if 'import' in config:
        print('[WARN] [import] section must be a table, treating as empty', file=sys.stderr)
    sys.exit(0)

additional_paths = import_section.get('additional_paths', [])
if not isinstance(additional_paths, list):
    print('[WARN] [import].additional_paths must be a list, skipping', file=sys.stderr)
    sys.exit(0)

for i, path_str in enumerate(additional_paths):
    if not isinstance(path_str, str):
        print(f'[WARN] [import].additional_paths[{i}] must be a string, skipping', file=sys.stderr)
        continue

    # Skip empty paths
    if not path_str.strip():
        print(f'[WARN] [import].additional_paths[{i}] is empty, skipping', file=sys.stderr)
        continue

    # Reject multi-line values (security)
    if '\n' in path_str or '\r' in path_str:
        print(f'[WARN] [import].additional_paths[{i}] contains newlines, skipping', file=sys.stderr)
        continue

    # SECURITY: Reject colons - they corrupt the sync map format (src:dst:flags)
    if ':' in path_str:
        print(f'[WARN] [import].additional_paths[{i}] \"{path_str}\" contains colon (invalid for sync map), skipping', file=sys.stderr)
        continue

    # SECURITY: Reject null bytes
    if '\0' in path_str:
        print(f'[WARN] [import].additional_paths[{i}] contains null byte, skipping', file=sys.stderr)
        continue

    # Paths must start with ~/ or be absolute
    if path_str.startswith('~/'):
        # Expand ~ to HOME
        expanded = home + path_str[1:]
    elif path_str.startswith('~'):
        # Reject ~user syntax (other users' homes)
        print(f'[WARN] [import].additional_paths[{i}] \"{path_str}\" references another user home, skipping', file=sys.stderr)
        continue
    elif path_str.startswith('/'):
        # Absolute path - allowed if under HOME
        expanded = path_str
    else:
        # Reject relative paths (spec requires ~/ or absolute under HOME)
        print(f'[WARN] [import].additional_paths[{i}] \"{path_str}\" is relative (must start with ~/ or be absolute), skipping', file=sys.stderr)
        continue

    # Normalize path WITHOUT following symlinks (use abspath + normpath, NOT realpath/resolve)
    # This does lexical normalization only
    try:
        normalized = os.path.normpath(os.path.abspath(expanded))
    except (OSError, ValueError) as e:
        print(f'[WARN] [import].additional_paths[{i}] \"{path_str}\" cannot be normalized: {e}, skipping', file=sys.stderr)
        continue

    # Check for path traversal AFTER normalization (reject any remaining .. segments)
    # normpath should collapse valid .., but we reject any remaining for safety
    path_parts = normalized.split(os.sep)
    if '..' in path_parts:
        print(f'[WARN] [import].additional_paths[{i}] \"{path_str}\" contains path traversal after normalization, skipping', file=sys.stderr)
        continue

    # Validate path is under HOME using commonpath (lexical check, no symlink following)
    try:
        common = os.path.commonpath([home_normalized, normalized])
        if common != home_normalized:
            raise ValueError('not under HOME')
    except ValueError:
        print(f'[WARN] [import].additional_paths[{i}] \"{path_str}\" is not under HOME, skipping', file=sys.stderr)
        continue

    # Output the validated absolute path (normalized, no symlink resolution)
    print(normalized)
"); then
        # Python script failed
        if [[ -n "$explicit_config" ]]; then
            printf '%s\n' "[ERROR] Failed to extract additional_paths from config" >&2
            return 1
        fi
        printf '%s\n' "[WARN] Failed to extract additional_paths from config" >&2
        return 0
    fi

    # Output validated paths
    printf '%s' "$paths_output"
    return 0
}

# ==============================================================================
# Danger section resolution
# ==============================================================================

# Resolve danger.allow_host_credentials from config
# Arguments: $1 = workspace path (default: $PWD)
#            $2 = explicit config path (optional)
# Outputs: "true" if enabled in config, empty otherwise
# Note: Config enables the feature but CLI ack flag is still required
_containai_resolve_danger_allow_host_credentials() {
    local workspace="${1:-$PWD}"
    local explicit_config="${2:-}"
    local config_file

    # Resolve workspace to absolute path
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        workspace="$PWD"
    fi

    # Find config file
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            return 0
        fi
        config_file="$explicit_config"
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    if [[ -n "$config_file" ]]; then
        local strict_mode=""
        if [[ -n "$explicit_config" ]]; then
            strict_mode="strict"
        fi
        if _containai_parse_config "$config_file" "$workspace" "$strict_mode"; then
            if [[ "$_CAI_DANGER_ALLOW_HOST_CREDENTIALS" == "true" ]]; then
                printf '%s' "true"
                return 0
            fi
        fi
    fi

    return 0
}

# Resolve danger.allow_host_docker_socket from config
# Arguments: $1 = workspace path (default: $PWD)
#            $2 = explicit config path (optional)
# Outputs: "true" if enabled in config, empty otherwise
# Note: Config enables the feature but CLI ack flag is still required
_containai_resolve_danger_allow_host_docker_socket() {
    local workspace="${1:-$PWD}"
    local explicit_config="${2:-}"
    local config_file

    # Resolve workspace to absolute path
    if ! workspace=$(cd -- "$workspace" 2>/dev/null && pwd); then
        workspace="$PWD"
    fi

    # Find config file
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            return 0
        fi
        config_file="$explicit_config"
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    if [[ -n "$config_file" ]]; then
        local strict_mode=""
        if [[ -n "$explicit_config" ]]; then
            strict_mode="strict"
        fi
        if _containai_parse_config "$config_file" "$workspace" "$strict_mode"; then
            if [[ "$_CAI_DANGER_ALLOW_HOST_DOCKER_SOCKET" == "true" ]]; then
                printf '%s' "true"
                return 0
            fi
        fi
    fi

    return 0
}

# ==============================================================================
# Workspace state persistence (user config)
# ==============================================================================

# Get user config file path
# Returns: path to user config file (~/.config/containai/config.toml)
_containai_user_config_path() {
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    printf '%s' "$xdg_config/containai/config.toml"
}

# Read workspace state from user config
# Arguments: $1 = workspace path (will be normalized)
# Outputs: JSON with workspace state keys (data_volume, container_name, agent, created_at)
#          or empty JSON object {} if not found or parse error
# Returns: 0 on success (including graceful degradation on parse errors)
#          1 on error (missing workspace argument, non-absolute path, Python unavailable)
#
# This function ALWAYS reads from user config (~/.config/containai/config.toml),
# independent of repo-local config. This is the key difference from _containai_parse_config.
_containai_read_workspace_state() {
    local workspace="$1"
    local script_dir user_config normalized_path

    # Require workspace argument
    if [[ -z "$workspace" ]]; then
        printf '%s\n' "[ERROR] _containai_read_workspace_state requires workspace path" >&2
        return 1
    fi

    # Normalize the workspace path using platform-aware helper
    # This ensures consistent keys across lookups
    normalized_path=$(_cai_normalize_path "$workspace")

    # Validate normalized path is absolute (must start with /)
    # This also prevents argument injection since paths starting with - would fail
    if [[ "$normalized_path" != /* ]]; then
        printf '%s\n' "[ERROR] Workspace path must be absolute: $normalized_path" >&2
        return 1
    fi

    # Get user config path
    user_config=$(_containai_user_config_path)

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] Python required to read workspace state" >&2
        return 1
    fi

    # Determine script directory (where parse-toml.py lives)
    if ! script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; then
        printf '%s\n' "[ERROR] Failed to determine script directory" >&2
        return 1
    fi

    # Call parse-toml.py --get-workspace
    # This returns {} for missing file or missing workspace (not an error)
    local ws_json
    if ! ws_json=$(python3 "$script_dir/parse-toml.py" --file "$user_config" --get-workspace "$normalized_path" 2>/dev/null); then
        # Parse error - return empty (graceful degradation)
        printf '%s' "{}"
        return 0
    fi

    printf '%s' "$ws_json"
    return 0
}

# Write a key to workspace state in user config
# Arguments: $1 = workspace path (will be normalized)
#            $2 = key name (data_volume, container_name, agent, created_at)
#            $3 = value (string)
# Returns: 0 on success, 1 on error
#
# This function ALWAYS writes to user config (~/.config/containai/config.toml).
# Uses atomic write (temp file + rename) to prevent corruption.
# Creates config file with 0600 and directory with 0700 if missing.
_containai_write_workspace_state() {
    local workspace="$1"
    local key="$2"
    local value="$3"
    local script_dir user_config normalized_path

    # Require workspace and key arguments (value can be empty string)
    if [[ -z "$workspace" ]] || [[ -z "$key" ]]; then
        printf '%s\n' "[ERROR] _containai_write_workspace_state requires workspace and key" >&2
        return 1
    fi

    # Normalize the workspace path using platform-aware helper
    normalized_path=$(_cai_normalize_path "$workspace")

    # Validate normalized path is absolute (must start with /)
    # This also prevents argument injection since paths starting with - would fail
    if [[ "$normalized_path" != /* ]]; then
        printf '%s\n' "[ERROR] Workspace path must be absolute: $normalized_path" >&2
        return 1
    fi

    # Get user config path
    user_config=$(_containai_user_config_path)

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] Python required to write workspace state" >&2
        return 1
    fi

    # Determine script directory (where parse-toml.py lives)
    if ! script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; then
        printf '%s\n' "[ERROR] Failed to determine script directory" >&2
        return 1
    fi

    # Call parse-toml.py --set-workspace-key
    # This creates the file and directory if needed
    if ! python3 "$script_dir/parse-toml.py" --file "$user_config" --set-workspace-key "$normalized_path" "$key" "$value"; then
        printf '%s\n' "[ERROR] Failed to write workspace state" >&2
        return 1
    fi

    return 0
}

# Read a specific key from workspace state
# Arguments: $1 = workspace path (will be normalized)
#            $2 = key name (data_volume, container_name, agent, created_at)
# Outputs: value (string) or empty if not found
# Returns: 0 always (empty output = not found)
#
# Convenience wrapper around _containai_read_workspace_state for single key access.
_containai_read_workspace_key() {
    local workspace="$1"
    local key="$2"
    local ws_json value

    # Read full workspace state
    if ! ws_json=$(_containai_read_workspace_state "$workspace"); then
        return 0  # Graceful degradation
    fi

    # Extract the specific key using Python
    if ! value=$(printf '%s' "$ws_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
val = data.get(sys.argv[1], '')
if val is not None:
    print(val, end='')
" "$key" 2>/dev/null); then
        return 0  # Graceful degradation
    fi

    printf '%s' "$value"
    return 0
}

# ==============================================================================
# Volume name generation (for --reset)
# ==============================================================================

# Generate a unique data volume name for workspace
# Format: {repo}-{branch}-{timestamp}
# Arguments: $1 = workspace path (required, should be normalized)
# Outputs: volume name via stdout
# Returns: 0 on success, 1 on error
#
# Rules:
# - repo: directory name (last path component), sanitized
# - branch: from git, sanitized; "nogit" if not a git repo
# - timestamp: Unix timestamp for uniqueness
# - Sanitization: lowercase, replace non-alphanumeric with dash, collapse multiple dashes
# - Max 255 chars (Docker volume name limit)
#
# This function is used by --reset to generate a NEW unique volume name.
# It NEVER falls back to the default sandbox-agent-data volume.
_containai_generate_volume_name() {
    local workspace="$1"
    local repo_name branch_name timestamp sanitized_repo sanitized_branch volume_name

    if [[ -z "$workspace" ]]; then
        printf '%s\n' "[ERROR] _containai_generate_volume_name requires workspace path" >&2
        return 1
    fi

    # Extract repo name (last path component)
    repo_name=$(basename "$workspace")
    if [[ -z "$repo_name" || "$repo_name" == "/" ]]; then
        repo_name="workspace"
    fi

    # Get git branch (or "nogit" if not a git repo)
    if command -v git >/dev/null 2>&1 && (cd -- "$workspace" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
        # Try to get branch name
        if branch_name=$(cd -- "$workspace" && git rev-parse --abbrev-ref HEAD 2>/dev/null); then
            # Handle detached HEAD
            if [[ "$branch_name" == "HEAD" ]]; then
                # Use short SHA instead
                branch_name=$(cd -- "$workspace" && git rev-parse --short HEAD 2>/dev/null) || branch_name="detached"
            fi
        else
            branch_name="nogit"
        fi
    else
        branch_name="nogit"
    fi

    # Get Unix timestamp for uniqueness
    # Try nanosecond precision first (GNU date), fall back to seconds + random
    # This ensures uniqueness even for rapid consecutive --reset calls
    # Note: BSD/macOS date +%s%N yields literal "N" (e.g., "1700000000N"), not nanoseconds
    # Must validate result is all digits AND length > 10 to detect this
    if timestamp=$(date +%s%N 2>/dev/null) && [[ "$timestamp" =~ ^[0-9]+$ ]] && [[ ${#timestamp} -gt 10 ]]; then
        # Got nanoseconds - use full precision for uniqueness
        : # timestamp already set
    else
        # Fallback: seconds + 4-digit random for systems without %N
        local base_ts random_part
        base_ts=$(date +%s)
        if [[ -r /dev/urandom ]]; then
            random_part=$(head -c 2 /dev/urandom | od -An -tu2 | tr -d ' ')
            random_part=$((random_part % 10000))
        else
            random_part=$((RANDOM % 10000))
        fi
        timestamp="${base_ts}$(printf '%04d' "$random_part")"
    fi

    # Sanitize repo name: lowercase, replace non-alphanumeric with dash, collapse dashes
    # Note: use POSIX BRE 's/--*/-/g' instead of GNU ERE 's/-\+/-/g' for portability
    sanitized_repo=$(printf '%s' "$repo_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    if [[ -z "$sanitized_repo" ]]; then
        sanitized_repo="workspace"
    fi

    # Sanitize branch name: lowercase, replace non-alphanumeric with dash, collapse dashes
    # Note: use POSIX BRE 's/--*/-/g' instead of GNU ERE 's/-\+/-/g' for portability
    sanitized_branch=$(printf '%s' "$branch_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    if [[ -z "$sanitized_branch" ]]; then
        sanitized_branch="unknown"
    fi

    # Combine into volume name: {repo}-{branch}-{timestamp}
    # Format matches spec exactly; uniqueness via high-resolution timestamp
    volume_name="${sanitized_repo}-${sanitized_branch}-${timestamp}"

    # Truncate to 255 chars (Docker volume name limit)
    if [[ ${#volume_name} -gt 255 ]]; then
        volume_name="${volume_name:0:255}"
    fi

    # Validate volume name format (Docker requirements)
    # Must start with alphanumeric, contain only alphanumeric, underscore, dot, dash
    if ! _containai_validate_volume_name "$volume_name"; then
        # Fallback: still match documented {repo}-{branch}-{timestamp} format
        volume_name="${sanitized_repo:-workspace}-${sanitized_branch:-nogit}-${timestamp}"
    fi

    printf '%s' "$volume_name"
    return 0
}

# ==============================================================================
# Config resolution with source tracking
# ==============================================================================

# List of known config keys with their scopes
# Workspace-scoped keys: data_volume (runtime reads this from workspace state)
# NOTE: container_name is internal state (written by cai up/create, not user-settable)
# NOTE: "agent" as standalone key is an alias for agent.default (global)
# Global-scoped keys: agent.default, ssh.forward_agent, ssh.port_range_start, ssh.port_range_end, import.auto_prompt
_CAI_WORKSPACE_KEYS="data_volume"
_CAI_GLOBAL_KEYS="agent.default ssh.forward_agent ssh.port_range_start ssh.port_range_end import.auto_prompt"

# Resolve a config key and return value with source
# Arguments: $1 = key name
#            $2 = workspace path (optional, default: $PWD)
#            $3 = CLI value override (optional)
#            $4 = explicit config path (optional)
# Outputs: value<TAB>source (tab-separated)
#          Source is one of: cli, env, workspace:<path>, repo-local, user-global, default
# Returns: 0 always (empty value = not found)
#
# Resolution precedence:
# 1. CLI flags ($3)
# 2. Environment variables (CONTAINAI_<KEY>)
# 3. Workspace state (user config [workspace."path"] section)
# 4. Repo-local config (.containai/config.toml)
# 5. User global config (~/.config/containai/config.toml top-level)
# 6. Built-in defaults
_containai_resolve_with_source() {
    local key="$1"
    local workspace="${2:-$PWD}"
    local cli_value="${3:-}"
    local env_var_name env_value repo_config_file user_config_file
    local script_dir config_json value normalized_path ws_json

    # Treat "agent" as alias for "agent.default" (runtime only reads agent.default)
    if [[ "$key" == "agent" ]]; then
        key="agent.default"
    fi

    # Normalize workspace path
    if ! normalized_path=$(_cai_normalize_path "$workspace"); then
        normalized_path="$PWD"
    fi

    # 1. CLI flag always wins
    if [[ -n "$cli_value" ]]; then
        printf '%s\t%s' "$cli_value" "cli"
        return 0
    fi

    # 2. Environment variable (only for keys that runtime actually reads from env)
    # Only specific keys have env var support in runtime:
    # - CONTAINAI_DATA_VOLUME (for data_volume)
    # - CONTAINAI_AGENT (for agent, agent.default)
    # - CONTAINAI_CREDENTIALS (for credentials)
    # - CONTAINAI_SECURE_ENGINE_CONTEXT (for secure_engine.context_name)
    local env_var_name=""
    case "$key" in
        data_volume)
            env_var_name="CONTAINAI_DATA_VOLUME"
            ;;
        agent.default)
            env_var_name="CONTAINAI_AGENT"
            ;;
        credentials|credentials.mode)
            env_var_name="CONTAINAI_CREDENTIALS"
            ;;
        secure_engine.context_name)
            env_var_name="CONTAINAI_SECURE_ENGINE_CONTEXT"
            ;;
    esac
    if [[ -n "$env_var_name" ]] && [[ -n "${!env_var_name:-}" ]]; then
        printf '%s\t%s' "${!env_var_name}" "env"
        return 0
    fi

    # Check if this is a workspace-scoped key (needed for precedence logic)
    local is_workspace_key=""
    local k
    for k in $_CAI_WORKSPACE_KEYS; do
        if [[ "$key" == "$k" ]]; then
            is_workspace_key="true"
            break
        fi
    done

    # Check if Python available (needed for config file sources)
    # If Python unavailable, skip to built-in defaults (don't return empty)
    local python_available=""
    if command -v python3 >/dev/null 2>&1; then
        python_available="true"
        # Get script directory for parse-toml.py
        if ! script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; then
            python_available=""
        fi
    fi

    # 3. Workspace state (for workspace-scoped keys only)
    # Use longest-prefix matching (same as _containai_find_matching_workspace) for nested detection
    if [[ "$python_available" == "true" ]] && [[ "$is_workspace_key" == "true" ]]; then
        # Read from user config workspace section with longest-prefix matching
        user_config_file=$(_containai_user_config_path)
        if [[ -f "$user_config_file" ]]; then
            if config_json=$(python3 "$script_dir/parse-toml.py" --file "$user_config_file" --json 2>/dev/null); then
                # Find best matching workspace and get the key value
                local ws_result
                ws_result=$(printf '%s' "$config_json" | python3 -c "
import json, sys
from pathlib import Path

config = json.load(sys.stdin)
workspace = sys.argv[1]
key = sys.argv[2]

workspaces = config.get('workspace', {})
if not isinstance(workspaces, dict):
    sys.exit(0)

# Find longest-prefix matching workspace
best_match_path = None
best_match_value = None
best_segments = 0
ws_path = Path(workspace)

for path_str, section in workspaces.items():
    if not isinstance(section, dict):
        continue
    try:
        cfg_path = Path(path_str)
        if not cfg_path.is_absolute():
            continue
        ws_path.relative_to(cfg_path)
        num_segments = len(cfg_path.parts)
        if num_segments > best_segments:
            val = section.get(key, '')
            if val is not None and val != '':
                best_match_path = path_str
                best_match_value = val
                best_segments = num_segments
    except ValueError:
        pass

if best_match_value:
    # Output: value<TAB>path
    print(f'{best_match_value}\t{best_match_path}', end='')
" "$normalized_path" "$key" 2>/dev/null)
                if [[ -n "$ws_result" ]]; then
                    value="${ws_result%%	*}"
                    local matched_path="${ws_result#*	}"
                    printf '%s\t%s' "$value" "workspace:$matched_path"
                    return 0
                fi
            fi
        fi
    fi

    # 4. Repo-local config (.containai/config.toml)
    # Walk up from workspace looking for .containai/config.toml
    # Track whether repo-local was found (affects whether we consult user-global)
    local repo_local_found="false"
    if [[ "$python_available" == "true" ]]; then
        local dir="$normalized_path"
        while [[ "$dir" != "/" ]]; do
            repo_config_file="$dir/.containai/config.toml"
            if [[ -f "$repo_config_file" ]]; then
                repo_local_found="true"
                if config_json=$(python3 "$script_dir/parse-toml.py" --file "$repo_config_file" --json 2>/dev/null); then
                    # For data_volume, check workspace section and agent.data_volume
                    # (matches _containai_parse_config fallback chain)
                    if [[ "$key" == "data_volume" ]]; then
                        value=$(printf '%s' "$config_json" | python3 -c "
import json, sys
from pathlib import Path
config = json.load(sys.stdin)
workspace = sys.argv[1]

# 1. Try workspace.<path>.data_volume (longest prefix match)
workspaces = config.get('workspace', {})
best_match = None
best_segments = 0
if isinstance(workspaces, dict):
    ws_path = Path(workspace)
    for path_str, section in workspaces.items():
        if not isinstance(section, dict):
            continue
        try:
            cfg_path = Path(path_str)
            if not cfg_path.is_absolute():
                continue
            ws_path.relative_to(cfg_path)
            num_segments = len(cfg_path.parts)
            if num_segments > best_segments:
                vol = section.get('data_volume', '')
                if vol:
                    best_match = vol
                    best_segments = num_segments
        except ValueError:
            pass
if best_match:
    print(best_match, end='')
    sys.exit(0)

# 2. Try agent.data_volume
agent = config.get('agent', {})
if isinstance(agent, dict):
    vol = agent.get('data_volume', '')
    if vol:
        print(vol, end='')
" "$normalized_path" 2>/dev/null)
                    else
                        # Standard key lookup
                        value=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
key = sys.argv[1]
parts = key.split('.')
current = config
for part in parts:
    if not isinstance(current, dict) or part not in current:
        sys.exit(0)
    current = current[part]
# Reject dict/list values - we only want scalars
if isinstance(current, (dict, list)):
    sys.exit(0)
if current is not None and current != '':
    if isinstance(current, bool):
        print('true' if current else 'false', end='')
    else:
        print(current, end='')
" "$key" 2>/dev/null)
                    fi
                    if [[ -n "$value" ]]; then
                        printf '%s\t%s' "$value" "repo-local"
                        return 0
                    fi
                fi
                break
            fi
            # Stop at git root
            if [[ -e "$dir/.git" ]]; then
                break
            fi
            dir=$(dirname "$dir")
        done
    fi

    # 5. User global config (~/.config/containai/config.toml top-level)
    # For non-workspace-scoped keys, skip user-global if repo-local config exists
    # (matches runtime behavior where _containai_find_config returns ONE config)
    # Workspace-scoped keys always check workspace state (step 3), and user-global
    # is only for top-level global settings
    if [[ "$python_available" == "true" ]]; then
        if [[ "$repo_local_found" == "true" ]] && [[ "$is_workspace_key" != "true" ]]; then
            # Repo-local exists but doesn't have this key - go straight to defaults
            # (matches runtime: once repo-local found, user-global is not consulted)
            :
        else
            user_config_file=$(_containai_user_config_path)
            if [[ -f "$user_config_file" ]]; then
                if config_json=$(python3 "$script_dir/parse-toml.py" --file "$user_config_file" --json 2>/dev/null); then
                    # For data_volume, also check agent.data_volume (matches _containai_parse_config)
                    if [[ "$key" == "data_volume" ]]; then
                        value=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
# Try agent.data_volume
agent = config.get('agent', {})
if isinstance(agent, dict):
    vol = agent.get('data_volume', '')
    if vol:
        print(vol, end='')
" 2>/dev/null)
                    else
                        value=$(printf '%s' "$config_json" | python3 -c "
import json, sys
config = json.load(sys.stdin)
key = sys.argv[1]
parts = key.split('.')
current = config
for part in parts:
    if not isinstance(current, dict) or part not in current:
        sys.exit(0)
    current = current[part]
# Skip workspace section (that's handled separately)
if len(parts) == 1 and parts[0] == 'workspace':
    sys.exit(0)
# Reject dict/list values - we only want scalars
if isinstance(current, (dict, list)):
    sys.exit(0)
if current is not None and current != '':
    if isinstance(current, bool):
        print('true' if current else 'false', end='')
    else:
        print(current, end='')
" "$key" 2>/dev/null)
                    fi
                    if [[ -n "$value" ]]; then
                        printf '%s\t%s' "$value" "user-global"
                        return 0
                    fi
                fi
            fi
        fi
    fi

    # 6. Built-in defaults
    # NOTE: These must match the actual defaults used in the respective modules
    # SSH defaults match _CAI_SSH_PORT_RANGE_START_DEFAULT/_END_DEFAULT in ssh.sh
    # data_volume default matches _CONTAINAI_DEFAULT_VOLUME
    local default_value=""
    case "$key" in
        data_volume)
            default_value="$_CONTAINAI_DEFAULT_VOLUME"
            ;;
        agent.default)
            default_value="claude"
            ;;
        ssh.port_range_start)
            default_value="2300"
            ;;
        ssh.port_range_end)
            default_value="2500"
            ;;
        ssh.forward_agent)
            default_value="false"
            ;;
        import.auto_prompt)
            default_value="true"
            ;;
        # container_name has no default (generated per workspace)
    esac

    if [[ -n "$default_value" ]]; then
        printf '%s\t%s' "$default_value" "default"
    else
        printf '%s\t%s' "" "default"
    fi
    return 0
}

# List all known config keys with their values and sources
# Arguments: $1 = workspace path (optional, default: $PWD)
# Outputs: Lines of KEY<TAB>VALUE<TAB>SOURCE
# Returns: 0 always
_containai_list_all_config() {
    local workspace="${1:-$PWD}"
    local key result value source

    # List workspace-scoped keys
    for key in $_CAI_WORKSPACE_KEYS; do
        result=$(_containai_resolve_with_source "$key" "$workspace")
        value="${result%%	*}"
        source="${result#*	}"
        if [[ -n "$value" ]]; then
            printf '%s\t%s\t%s\n' "$key" "$value" "$source"
        fi
    done

    # List global-scoped keys
    for key in $_CAI_GLOBAL_KEYS; do
        result=$(_containai_resolve_with_source "$key" "$workspace")
        value="${result%%	*}"
        source="${result#*	}"
        if [[ -n "$value" ]]; then
            printf '%s\t%s\t%s\n' "$key" "$value" "$source"
        fi
    done
}

# Unset a key from workspace state
# Arguments: $1 = workspace path (will be normalized)
#            $2 = key name
# Returns: 0 on success, 1 on error
_containai_unset_workspace_key() {
    local workspace="$1"
    local key="$2"
    local script_dir user_config normalized_path

    if [[ -z "$workspace" ]] || [[ -z "$key" ]]; then
        printf '%s\n' "[ERROR] _containai_unset_workspace_key requires workspace and key" >&2
        return 1
    fi

    # Normalize workspace path
    normalized_path=$(_cai_normalize_path "$workspace")
    if [[ "$normalized_path" != /* ]]; then
        printf '%s\n' "[ERROR] Workspace path must be absolute: $normalized_path" >&2
        return 1
    fi

    # Get user config path
    user_config=$(_containai_user_config_path)

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] Python required to unset workspace key" >&2
        return 1
    fi

    # Get script directory
    if ! script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; then
        printf '%s\n' "[ERROR] Failed to determine script directory" >&2
        return 1
    fi

    # Call parse-toml.py --unset-workspace-key
    if ! python3 "$script_dir/parse-toml.py" --file "$user_config" --unset-workspace-key "$normalized_path" "$key"; then
        printf '%s\n' "[ERROR] Failed to unset workspace key" >&2
        return 1
    fi

    return 0
}

# Unset a global key from user config
# Arguments: $1 = key name (dot notation, e.g., agent.default)
# Returns: 0 on success, 1 on error
_containai_unset_global_key() {
    local key="$1"
    local script_dir user_config

    if [[ -z "$key" ]]; then
        printf '%s\n' "[ERROR] _containai_unset_global_key requires key" >&2
        return 1
    fi

    # Get user config path
    user_config=$(_containai_user_config_path)

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] Python required to unset global key" >&2
        return 1
    fi

    # Get script directory
    if ! script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; then
        printf '%s\n' "[ERROR] Failed to determine script directory" >&2
        return 1
    fi

    # Call parse-toml.py --unset-key
    if ! python3 "$script_dir/parse-toml.py" --file "$user_config" --unset-key "$key"; then
        printf '%s\n' "[ERROR] Failed to unset global key" >&2
        return 1
    fi

    return 0
}

# Set a global key in user config
# Arguments: $1 = key name (dot notation, e.g., agent.default)
#            $2 = value
# Returns: 0 on success, 1 on error
_containai_set_global_key() {
    local key="$1"
    local value="$2"
    local script_dir user_config

    if [[ -z "$key" ]]; then
        printf '%s\n' "[ERROR] _containai_set_global_key requires key" >&2
        return 1
    fi

    # Get user config path
    user_config=$(_containai_user_config_path)

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] Python required to set global key" >&2
        return 1
    fi

    # Get script directory
    if ! script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; then
        printf '%s\n' "[ERROR] Failed to determine script directory" >&2
        return 1
    fi

    # Call parse-toml.py --set-key
    if ! python3 "$script_dir/parse-toml.py" --file "$user_config" --set-key "$key" "$value"; then
        printf '%s\n' "[ERROR] Failed to set global key" >&2
        return 1
    fi

    return 0
}

return 0
