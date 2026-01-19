# fn-4-vet.3 Parameterize volume name in sync-agent-plugins.sh

## Description
## Overview
Update `sync-agent-plugins.sh` to accept configurable volume names with same precedence as cai. **Must print resolved volume name** for verification.

## Implementation

### Precedence
1. `--volume <name>` CLI flag → skips config parsing
2. `CONTAINAI_DATA_VOLUME` env var → skips config parsing
3. Config file (from `$PWD` discovery)
4. Default: `sandbox-agent-data`

### Required Output
The script MUST print the resolved volume name:
```bash
info "Using data volume: $DATA_VOLUME"
```
This enables verification in quick commands and tests.

### Current Code (line 20)
```bash
readonly DATA_VOLUME="sandbox-agent-data"
```

### New Behavior
```bash
DATA_VOLUME=""
EXPLICIT_CONFIG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --volume) DATA_VOLUME="$2"; shift 2 ;;
        --volume=*) DATA_VOLUME="${1#*=}"; shift ;;
        --config) EXPLICIT_CONFIG="$2"; shift 2 ;;
        --config=*) EXPLICIT_CONFIG="${1#*=}"; shift ;;
        *) # existing flags...
    esac
done

# Skip config if CLI volume set
if [[ -z "$DATA_VOLUME" ]]; then
    if [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
        DATA_VOLUME="$CONTAINAI_DATA_VOLUME"
    else
        DATA_VOLUME=$(_sync_resolve_config_volume "$EXPLICIT_CONFIG")
    fi
fi

DATA_VOLUME="${DATA_VOLUME:-sandbox-agent-data}"
readonly DATA_VOLUME

# Print resolved volume (required for verification)
info "Using data volume: $DATA_VOLUME"
```

## Key Files
- Modify: `agent-sandbox/sync-agent-plugins.sh`
## Overview
Update `sync-agent-plugins.sh` to accept configurable volume names with the same precedence as cai/containai. Resolution root is always `$PWD` (no --workspace support).

## Implementation

### Precedence (same as cai)
1. `--volume <name>` CLI flag → **skips config parsing entirely**
2. `CONTAINAI_DATA_VOLUME` env var → **skips config parsing entirely**
3. Config file value (from `$PWD` discovery)
4. Default: `sandbox-agent-data`

### Current Code (line 20)
```bash
readonly DATA_VOLUME="sandbox-agent-data"
```

### New Behavior
```bash
DATA_VOLUME=""
EXPLICIT_CONFIG=""

# Parse CLI flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --volume)
            DATA_VOLUME="$2"
            shift 2
            ;;
        --volume=*)
            DATA_VOLUME="${1#*=}"
            shift
            ;;
        --config)
            EXPLICIT_CONFIG="$2"
            shift 2
            ;;
        --config=*)
            EXPLICIT_CONFIG="${1#*=}"
            shift
            ;;
        *)
            # ... existing flag handling ...
            ;;
    esac
done

# If CLI volume set, skip all config resolution
if [[ -z "$DATA_VOLUME" ]]; then
    # Check env var
    if [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
        DATA_VOLUME="$CONTAINAI_DATA_VOLUME"
    else
        # Try config discovery from $PWD
        DATA_VOLUME=$(_sync_resolve_config_volume "$EXPLICIT_CONFIG")
    fi
fi

DATA_VOLUME="${DATA_VOLUME:-sandbox-agent-data}"

# Validate
if ! _sync_validate_volume_name "$DATA_VOLUME"; then
    echo "[ERROR] Invalid volume name: $DATA_VOLUME" >&2
    exit 1
fi

readonly DATA_VOLUME
```

### Config Resolution
```bash
_sync_resolve_config_volume() {
    local explicit_config="${1:-}"
    local config_file=""
    
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
    else
        config_file=$(_sync_find_config)  # Walks up from $PWD
    fi
    
    [[ -z "$config_file" ]] && return 0
    
    if command -v python3 >/dev/null 2>&1; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        python3 "$script_dir/parse-toml.py" "$config_file" "agent.data_volume" 2>/dev/null
    else
        echo "[WARN] Python not found, cannot parse config. Using default." >&2
    fi
}
```

### Help Text
```
Usage: sync-agent-plugins.sh [OPTIONS]

Options:
  --volume <name>    Docker volume name for agent data (default: sandbox-agent-data)
  --config <path>    Explicit config file path (disables discovery)
  --dry-run          Show what would be synced without executing
  --help             Show this help message

Environment:
  CONTAINAI_DATA_VOLUME    Volume name (overridden by --volume)
  CONTAINAI_CONFIG         Config file path (overridden by --config)

Note: Config discovery uses current directory ($PWD) as root.
```

## Key Files
- Modify: `agent-sandbox/sync-agent-plugins.sh:20` (DATA_VOLUME)
- Modify: `agent-sandbox/sync-agent-plugins.sh` (argument parsing)
- Modify: `agent-sandbox/sync-agent-plugins.sh` (help text)
- Reference: `agent-sandbox/parse-toml.py` (from task fn-4-vet.1)
## Overview
Update `sync-agent-plugins.sh` to accept configurable volume names with the same precedence as cai/containai: `--volume` > `CONTAINAI_DATA_VOLUME` > config file > default.

## Implementation

### Current Code (line 20)
```bash
readonly DATA_VOLUME="sandbox-agent-data"
```

### New Behavior
```bash
# Parse command line first
DATA_VOLUME=""
EXPLICIT_CONFIG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --volume)
            DATA_VOLUME="$2"
            shift 2
            ;;
        --volume=*)
            DATA_VOLUME="${1#*=}"
            shift
            ;;
        --config)
            EXPLICIT_CONFIG="$2"
            shift 2
            ;;
        --config=*)
            EXPLICIT_CONFIG="${1#*=}"
            shift
            ;;
        # ... existing flags ...
    esac
done

# If no CLI volume, check environment
if [[ -z "$DATA_VOLUME" ]] && [[ -n "${CONTAINAI_DATA_VOLUME:-}" ]]; then
    DATA_VOLUME="$CONTAINAI_DATA_VOLUME"
fi

# If still no volume, try config discovery
if [[ -z "$DATA_VOLUME" ]]; then
    DATA_VOLUME=$(_sync_resolve_config_volume "$EXPLICIT_CONFIG")
fi

# Final fallback
DATA_VOLUME="${DATA_VOLUME:-sandbox-agent-data}"

# Validate
if ! _sync_validate_volume_name "$DATA_VOLUME"; then
    echo "[ERROR] Invalid volume name: $DATA_VOLUME" >&2
    exit 1
fi

readonly DATA_VOLUME
```

### Config Resolution (simplified for standalone script)
```bash
_sync_resolve_config_volume() {
    local explicit_config="${1:-}"
    local config_file=""
    
    # Explicit path?
    if [[ -n "$explicit_config" ]]; then
        if [[ ! -f "$explicit_config" ]]; then
            echo "[ERROR] Config file not found: $explicit_config" >&2
            return 1
        fi
        config_file="$explicit_config"
    else
        # Walk up from $PWD
        config_file=$(_sync_find_config)
    fi
    
    if [[ -z "$config_file" ]]; then
        return 0  # No config, use default
    fi
    
    # Parse with Python if available
    if command -v python3 >/dev/null 2>&1; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        python3 "$script_dir/parse-toml.py" "$config_file" "agent.data_volume" 2>/dev/null
    else
        echo "[WARN] Python not found, cannot parse config. Using default volume." >&2
    fi
}
```

### Help Text Update
```
Usage: sync-agent-plugins.sh [OPTIONS]

Options:
  --volume <name>    Docker volume name for agent data (default: sandbox-agent-data)
  --config <path>    Explicit config file path (disables discovery)
  --dry-run          Show what would be synced without executing
  --help             Show this help message

Environment:
  CONTAINAI_DATA_VOLUME    Volume name (overridden by --volume)
  CONTAINAI_CONFIG         Config file path (overridden by --config)
```

## Key Files
- Modify: `agent-sandbox/sync-agent-plugins.sh:20` (DATA_VOLUME)
- Modify: `agent-sandbox/sync-agent-plugins.sh` (argument parsing)
- Modify: `agent-sandbox/sync-agent-plugins.sh` (help text)
- Reference: `agent-sandbox/parse-toml.py` (from task fn-4-vet.1)
## Overview
Update `sync-agent-plugins.sh` to accept a `--volume` parameter for the agent data volume name. This script has no existing `--volume` flag, so there's no conflict.

## Implementation

### Current Code (line 20)
```bash
readonly DATA_VOLUME="sandbox-agent-data"
```

### New Behavior
```bash
# Initialize from environment if set
DATA_VOLUME="${CONTAINAI_DATA_VOLUME:-}"

# Parse command line for --volume flag
while [[ $# -gt 0 ]]; do
    case "$1" in
        --volume)
            DATA_VOLUME="$2"
            shift 2
            ;;
        --volume=*)
            DATA_VOLUME="${1#*=}"
            shift
            ;;
        # ... existing flags ...
    esac
done

# If still empty, try config discovery (optional, can use parse-toml.py)
if [[ -z "$DATA_VOLUME" ]]; then
    DATA_VOLUME=$(_sync_discover_volume)
fi

# Final fallback to default
DATA_VOLUME="${DATA_VOLUME:-sandbox-agent-data}"

# Validate
if ! _sync_validate_volume_name "$DATA_VOLUME"; then
    echo "[ERROR] Invalid volume name: $DATA_VOLUME" >&2
    exit 1
fi

readonly DATA_VOLUME
```

### Config Discovery (simplified for standalone script)
Since sync-agent-plugins.sh runs standalone, implement minimal config discovery:
1. Check explicit `CONTAINAI_CONFIG` env var
2. Walk up from `$PWD` looking for `.containai/config.toml`
3. Check `~/.config/containai/config.toml`
4. Parse with parse-toml.py if available

### Help Text Update
```
Usage: sync-agent-plugins.sh [OPTIONS]

Options:
  --volume <name>    Docker volume name for agent data (default: sandbox-agent-data)
  --dry-run          Show what would be synced without executing
  --help             Show this help message
```

## Key Files
- Modify: `agent-sandbox/sync-agent-plugins.sh:20` (DATA_VOLUME assignment)
- Modify: `agent-sandbox/sync-agent-plugins.sh` (argument parsing, near top)
- Modify: `agent-sandbox/sync-agent-plugins.sh` (help text)
- Reference: `agent-sandbox/parse-toml.py` (from task fn-4-vet.1)
## Overview
Update `sync-agent-plugins.sh` to accept a volume name parameter instead of using the hardcoded `sandbox-agent-data`. Support CLI flag, environment variable, and config file discovery.

## Implementation

### Current Code (line 20)
```bash
readonly DATA_VOLUME="sandbox-agent-data"
```

### New Behavior
```bash
# Parse --volume flag or use CONTAINAI_VOLUME env var or discover from config
DATA_VOLUME="${CONTAINAI_VOLUME:-}"

# Parse command line for --volume flag
while [[ $# -gt 0 ]]; do
    case "$1" in
        --volume)
            DATA_VOLUME="$2"
            shift 2
            ;;
        --volume=*)
            DATA_VOLUME="${1#*=}"
            shift
            ;;
        # ... existing flags ...
    esac
done

# If still empty, try config discovery
if [[ -z "$DATA_VOLUME" ]]; then
    DATA_VOLUME=$(_sync_discover_volume)
fi

# Final fallback to default
DATA_VOLUME="${DATA_VOLUME:-sandbox-agent-data}"
readonly DATA_VOLUME
```

### Config Discovery
Since sync-agent-plugins.sh runs on the host (not in container), it needs its own config discovery logic. Can either:
1. Source the helper functions from aliases.sh
2. Duplicate minimal discovery logic
3. Call parse-toml.py directly

Recommend option 3 for simplicity - direct call to parse-toml.py with same search order.

### Update Help Text
Add `--volume <name>` to usage output.

## Key Files
- Modify: `agent-sandbox/sync-agent-plugins.sh:20` (DATA_VOLUME constant)
- Modify: `agent-sandbox/sync-agent-plugins.sh` (argument parsing section)
- Reference: `agent-sandbox/parse-toml.py` (from task fn-4-vet.1)
## Acceptance
- [ ] `--volume <name>` skips config parsing
- [ ] `CONTAINAI_DATA_VOLUME` env var works
- [ ] Config file discovery from $PWD
- [ ] Precedence: --volume > env > config > default
- [ ] **Prints "Using data volume: <name>"** in output
- [ ] Default `sandbox-agent-data` used when no config
- [ ] Explicit --config with missing file fails
- [ ] `--dry-run --volume test-vol` output includes "Using data volume: test-vol"
- [ ] `CONTAINAI_DATA_VOLUME=x ./sync-agent-plugins.sh --dry-run` includes "Using data volume: x"
## Done summary
# fn-4-vet.3 Done Summary

## Changes Made
1. Updated header comment in sync-agent-plugins.sh with complete usage documentation including --volume, --config flags and environment variables
2. Fixed temp file cleanup in _sync_resolve_config_volume() by replacing trap with explicit rm -f on both exit paths (consistent with aliases.sh pattern)
3. Added comprehensive tests for volume parameterization to test-sync-integration.sh

## Acceptance Criteria Verified
All 9 acceptance criteria pass:
- [x] --volume <name> skips config parsing
- [x] CONTAINAI_DATA_VOLUME env var works
- [x] Config file discovery from $PWD
- [x] Precedence: --volume > env > config > default
- [x] Prints "Using data volume: <name>" in output
- [x] Default sandbox-agent-data used when no config
- [x] Explicit --config with missing file fails
- [x] --dry-run --volume test-vol output includes volume name
- [x] CONTAINAI_DATA_VOLUME=x --dry-run includes volume name
## Evidence
- Commits: 6f1c67b
- Tests: ./agent-sandbox/test-sync-integration.sh
- PRs: