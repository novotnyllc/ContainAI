# fn-4-vet.2 Add config loading function to aliases.sh

## Description
## Overview
Add config loading functions to `aliases.sh` that discover and load configuration from TOML files. Volume selection is **implicit based on workspace path** - no --profile flag needed.

## Implementation

### Config Discovery Order (only used when no higher-priority volume)
1. Project config: `.containai/config.toml` (walk up from resolution root to git root or `/`)
2. User config: `$XDG_CONFIG_HOME/containai/config.toml` (default: `~/.config/containai/`)

**Resolution root:** `--workspace <path>` if provided, otherwise `$PWD`.

### Value Precedence
1. `--data-volume <name>` CLI flag → **skips config parsing entirely**
2. `CONTAINAI_DATA_VOLUME` env var → **skips config parsing entirely**
3. Config file `[workspace.<path>]` section matching current workspace
4. Config file `[agent]` section (default)
5. Hardcoded default: `sandbox-agent-data`

### Key Design: Workspace Path-Based Selection

```bash
_containai_resolve_volume() {
    local cli_volume="${1:-}"
    local workspace="${2:-$PWD}"
    local explicit_config="${3:-}"

    # 1. CLI flag always wins - SKIP all config parsing
    if [[ -n "$cli_volume" ]]; then
        echo "$cli_volume"
        return 0
    fi

    # 2. Environment variable always wins - SKIP all config parsing
    if [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
        echo "$CONTAINAI_DATA_VOLUME"
        return 0
    fi

    # 3. Resolve workspace to absolute path
    workspace=$(cd "$workspace" 2>/dev/null && pwd) || workspace="$PWD"

    # 4. Find config file
    local config_file=""
    local config_dir=""
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
        config_dir=$(dirname "$config_file")
    else
        config_file=$(_containai_find_config "$workspace")
        [[ -n "$config_file" ]] && config_dir=$(dirname "$config_file")
    fi

    # 5. Parse config with workspace matching
    if [[ -n "$config_file" ]]; then
        local volume
        volume=$(_containai_parse_config_for_workspace "$config_file" "$workspace" "$config_dir")
        if [[ -n "$volume" ]]; then
            echo "$volume"
            return 0
        fi
    fi

    # 6. Default
    echo "sandbox-agent-data"
}

_containai_parse_config_for_workspace() {
    local config_file="$1"
    local workspace="$2"
    local config_dir="$3"

    if ! command -v python3 >/dev/null 2>&1; then
        echo "[WARN] Python not found, cannot parse config. Using default." >&2
        return 0
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$script_dir/parse-toml.py" "$config_file" --workspace "$workspace" --config-dir "$config_dir" 2>/dev/null
}
```

### Helper Functions
- `_containai_find_config()` - walks up from workspace path, checks XDG
- `_containai_parse_config_for_workspace()` - calls Python with workspace matching
- `_containai_validate_volume_name()` - validates Docker volume name
- `_containai_resolve_volume()` - main resolver

## Key Files
- Modify: `agent-sandbox/aliases.sh` (add new functions)
- Reference: `agent-sandbox/parse-toml.py` (from task fn-4-vet.1)
## Overview
Add config loading functions to `aliases.sh` that discover and load configuration from TOML files, environment variables, and CLI flags. **Volume is resolved per-invocation**. When `--data-volume` or `CONTAINAI_DATA_VOLUME` is set, config parsing is skipped entirely.

## Implementation

### Config Discovery Order (only used when no higher-priority volume)
1. Project config: `.containai/config.toml` (walk up from resolution root to git root or `/`)
2. User config: `$XDG_CONFIG_HOME/containai/config.toml` (default: `~/.config/containai/`)

**Resolution root:** `--workspace <path>` if provided, otherwise `$PWD`.

### Value Precedence (highest to lowest)
1. `--data-volume <name>` CLI flag → **skips config parsing entirely**
2. `CONTAINAI_DATA_VOLUME` env var → **skips config parsing entirely**
3. Config file value (profile key if `--profile`, else `agent.data_volume`)
4. Default: `sandbox-agent-data`

### Key Design: Skip Config When Volume Already Set

```bash
_containai_resolve_volume() {
    local cli_volume="${1:-}"
    local profile="${2:-}"
    local workspace="${3:-$PWD}"
    local explicit_config="${4:-}"

    # 1. CLI flag always wins - SKIP all config parsing
    if [[ -n "$cli_volume" ]]; then
        if [[ -n "$profile" ]]; then
            echo "[WARN] --profile ignored because --data-volume was specified" >&2
        fi
        echo "$cli_volume"
        return 0
    fi

    # 2. Environment variable always wins - SKIP all config parsing
    if [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
        if [[ -n "$profile" ]]; then
            echo "[WARN] --profile ignored because CONTAINAI_DATA_VOLUME is set" >&2
        fi
        echo "$CONTAINAI_DATA_VOLUME"
        return 0
    fi

    # 3. Config file resolution (only reached if no higher-priority volume)
    local config_file=""
    if [[ -n "$explicit_config" ]]; then
        config_file="$explicit_config"
        if [[ ! -f "$config_file" ]]; then
            echo "[ERROR] Config file not found: $config_file" >&2
            return 1
        fi
    else
        config_file=$(_containai_find_config "$workspace")
    fi

    if [[ -n "$config_file" ]]; then
        local volume
        volume=$(_containai_parse_config "$config_file" "$profile")
        if [[ -n "$volume" ]]; then
            echo "$volume"
            return 0
        fi
    fi

    # 4. Default
    echo "sandbox-agent-data"
}
```

### Python Optional - No Error When Volume Already Set

```bash
_containai_parse_config() {
    local config_file="$1"
    local profile="${2:-}"
    local key="agent.data_volume"

    [[ -n "$profile" ]] && key="profile.${profile}.data_volume"

    if ! command -v python3 >/dev/null 2>&1; then
        if [[ -n "$profile" ]]; then
            echo "[ERROR] --profile requires Python to parse config. Install Python 3.11+ or use CONTAINAI_DATA_VOLUME." >&2
            return 1
        fi
        echo "[WARN] Python not found, cannot parse config. Using default." >&2
        return 0
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local result
    result=$(python3 "$script_dir/parse-toml.py" "$config_file" "$key" 2>/dev/null)

    # Profile fallback
    if [[ -z "$result" ]] && [[ -n "$profile" ]]; then
        echo "[WARN] Profile '$profile' not found, using [agent] defaults" >&2
        result=$(python3 "$script_dir/parse-toml.py" "$config_file" "agent.data_volume" 2>/dev/null)
    fi

    echo "$result"
}
```

### Helper Functions
- `_containai_find_config()` - walks up from resolution root, checks XDG
- `_containai_parse_config()` - parses TOML, handles profile fallback
- `_containai_validate_volume_name()` - validates Docker volume name
- `_containai_resolve_volume()` - main resolver with skip-on-volume logic

## Key Files
- Modify: `agent-sandbox/aliases.sh` (add new functions)
- Reference: `agent-sandbox/parse-toml.py` (from task fn-4-vet.1)
## Overview
Add config loading functions to `aliases.sh` that discover and load configuration from TOML files, environment variables, and CLI flags. **Volume is resolved per-invocation** based on resolution root (--workspace path if provided, else $PWD).

## Implementation

### Config Discovery Order
1. Project config: `.containai/config.toml` (walk up from resolution root to git root or `/`)
2. User config: `$XDG_CONFIG_HOME/containai/config.toml` (default: `~/.config/containai/`)

**Resolution root:** `--workspace <path>` if provided (resolved to absolute), otherwise current `$PWD`.

### Value Precedence (highest to lowest)
1. `--data-volume <name>` CLI flag (always wins)
2. `CONTAINAI_DATA_VOLUME` env var (always wins over config)
3. Config file value (profile key if `--profile`, else `agent.data_volume`)
4. Default: `sandbox-agent-data`

### Key Design: Per-Invocation Resolution with Workspace Support

```bash
# Called by cai/containai on each invocation
# Arguments: $1=--data-volume, $2=--profile, $3=--workspace (resolved to absolute)
_containai_resolve_volume() {
    local cli_volume="${1:-}"
    local profile="${2:-}"
    local workspace="${3:-$PWD}"

    # 1. CLI flag always wins
    if [[ -n "$cli_volume" ]]; then
        echo "$cli_volume"
        return 0
    fi

    # 2. Environment variable always wins over config
    if [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
        echo "$CONTAINAI_DATA_VOLUME"
        return 0
    fi

    # 3. Config file discovery (from workspace root)
    local config_file
    config_file=$(_containai_find_config "$workspace")
    if [[ -n "$config_file" ]]; then
        local volume
        volume=$(_containai_parse_config "$config_file" "$profile")
        if [[ -n "$volume" ]]; then
            echo "$volume"
            return 0
        fi
    fi

    # 4. Default
    echo "sandbox-agent-data"
}
```

### Python Optional with Profile Failure

```bash
_containai_parse_config() {
    local config_file="$1"
    local profile="${2:-}"
    local key="agent.data_volume"

    [[ -n "$profile" ]] && key="profile.${profile}.data_volume"

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        if [[ -n "$profile" ]]; then
            # FAIL if --profile requested but can't parse
            echo "[ERROR] --profile requires Python to parse config. Install Python 3.11+ or use CONTAINAI_DATA_VOLUME env var." >&2
            return 1
        fi
        # Warn but continue without profile
        echo "[WARN] Python not found, cannot parse config file. Using env/CLI/default." >&2
        return 0
    fi

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$script_dir/parse-toml.py" "$config_file" "$key" 2>/dev/null
}
```

### Helper Functions Needed
- `_containai_find_config()` - walks up from resolution root, checks XDG
- `_containai_parse_config()` - wrapper around parse-toml.py, handles Python missing
- `_containai_validate_volume_name()` - validates Docker volume name pattern
- `_containai_resolve_volume()` - main resolver called per invocation

### Volume Name Validation
- Pattern: `^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`
- Min length: 1 character
- Max length: 255 characters

## Key Files
- Modify: `agent-sandbox/aliases.sh` (add new functions)
- Reference: `agent-sandbox/parse-toml.py` (from task fn-4-vet.1)
## Overview
Add config loading functions to `aliases.sh` that discover and load configuration from TOML files, environment variables, and CLI flags. **Volume is resolved per-invocation** (not cached) to support changing directories between projects.

## Implementation

### Config Discovery Order (highest to lowest priority)
1. CLI flag: `--data-volume <name>` or `--config <path>` (explicit path disables discovery)
2. Environment: `CONTAINAI_DATA_VOLUME` or `CONTAINAI_CONFIG` (explicit path disables discovery)
3. Project config: `.containai/config.toml` (walk up from cwd to git root or `/`)
4. User config: `$XDG_CONFIG_HOME/containai/config.toml` (default: `~/.config/containai/`)
5. Default: `sandbox-agent-data`

### Key Design: Per-Invocation Resolution
**Critical:** Do NOT cache volume name globally. Each command invocation resolves from current `$PWD`:

```bash
# Called by cai/containai on each invocation
# Arguments: $1 = CLI --data-volume value (if provided), $2 = --profile value (if provided)
_containai_resolve_volume() {
    local cli_volume="${1:-}"
    local profile="${2:-}"
    local data_volume=""

    # 1. CLI flag takes precedence
    if [[ -n "$cli_volume" ]]; then
        echo "$cli_volume"
        return 0
    fi

    # 2. Environment variable
    if [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
        echo "$CONTAINAI_DATA_VOLUME"
        return 0
    fi

    # 3. Config file discovery
    local config_file
    config_file=$(_containai_find_config)
    if [[ -n "$config_file" ]]; then
        data_volume=$(_containai_parse_toml "$config_file" "$profile")
        if [[ -n "$data_volume" ]]; then
            echo "$data_volume"
            return 0
        fi
    fi

    # 4. Default
    echo "sandbox-agent-data"
}
```

### Python Optional with Graceful Fallback
```bash
_containai_parse_toml() {
    local config_file="$1"
    local profile="${2:-}"
    local key="agent.data_volume"

    # Use profile-specific key if profile specified
    [[ -n "$profile" ]] && key="profile.${profile}.data_volume"

    # Check if Python available
    if ! command -v python3 >/dev/null 2>&1; then
        echo "[WARN] Python not found, cannot parse config file. Using env/CLI only." >&2
        return 1
    fi

    # Try parsing
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$script_dir/parse-toml.py" "$config_file" "$key" 2>/dev/null
}
```

### Helper Functions Needed
- `_containai_find_config()` - walks up directory tree from $PWD, checks XDG
- `_containai_parse_toml()` - wrapper around parse-toml.py with Python check
- `_containai_validate_volume_name()` - validates Docker volume name pattern
- `_containai_resolve_volume()` - main resolver called per invocation

### Volume Name Validation
- Pattern: `^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`
- Min length: 2 characters
- Max length: 255 characters

## Key Files
- Modify: `agent-sandbox/aliases.sh` (add new functions)
- Reference: `agent-sandbox/parse-toml.py` (from task fn-4-vet.1)
## Overview
Add a `_containai_load_config()` function to `aliases.sh` that discovers and loads configuration from TOML files, environment variables, and CLI flags. Sets the `_CONTAINAI_VOLUME` variable used by all other functions.

## Implementation

### Config Discovery Order (highest to lowest priority)
1. `CONTAINAI_VOLUME` environment variable
2. `.containai/config.toml` in current directory (walk up to git root or `/`)
3. `.devcontainer/containai.toml` in project root
4. `$XDG_CONFIG_HOME/containai/config.toml` (default: `~/.config/containai/`)
5. Default: `sandbox-agent-data`

### Function Design
```bash
# Called automatically when aliases.sh is sourced
# Sets _CONTAINAI_VOLUME global variable

_containai_load_config() {
    local config_file volume

    # 1. Check environment variable first
    if [[ -n "${CONTAINAI_VOLUME:-}" ]]; then
        _CONTAINAI_VOLUME="$CONTAINAI_VOLUME"
        return 0
    fi

    # 2. Find config file
    config_file=$(_containai_find_config)

    # 3. Parse if found
    if [[ -n "$config_file" ]]; then
        volume=$(_containai_parse_toml "$config_file" "agent.volume")
        if [[ -n "$volume" ]]; then
            _CONTAINAI_VOLUME="$volume"
            return 0
        fi
    fi

    # 4. Default
    _CONTAINAI_VOLUME="sandbox-agent-data"
}
```

### Helper Functions Needed
- `_containai_find_config()` - walks up directory tree, checks XDG
- `_containai_parse_toml()` - wrapper around parse-toml.py with Python check
- `_containai_validate_volume_name()` - validates Docker volume name pattern

### Volume Name Validation
Pattern: `^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`
Max length: 255 characters

## Key Files
- Modify: `agent-sandbox/aliases.sh:17-24` (constants block)
- Reference: `agent-sandbox/parse-toml.py` (from task fn-4-vet.1)
## Acceptance
- [ ] `--data-volume` skips config parsing entirely (no Python needed)
- [ ] `CONTAINAI_DATA_VOLUME` skips config parsing entirely
- [ ] Workspace path is resolved to absolute before matching
- [ ] `[workspace.<path>]` sections matched against workspace
- [ ] Relative paths in config resolved from config file directory
- [ ] Longest match wins when multiple workspace sections match
- [ ] Falls back to `[agent].data_volume` when no workspace match
- [ ] Falls back to `sandbox-agent-data` when no config
- [ ] Missing Python warns and uses default
- [ ] All variables declared `local` to prevent shell pollution
- [ ] `cai --workspace /path` uses /path for both workspace AND config matching
## Done summary
Added config loading functions to aliases.sh with full integration: _containai_validate_volume_name, _containai_find_config, _containai_parse_config_for_workspace, and _containai_resolve_volume. Wired into asb with --data-volume flag support.
## Evidence
- Commits: 33085e1, 6c89b6e, 8e1a22d
- Tests: bash -n aliases.sh, python3 -m py_compile parse-toml.py, manual function tests
- PRs:
