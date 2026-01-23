# fn-4-vet.4 Update asb* functions to use configurable volume

## Description
## Overview
Update all `asb*` / `cai*` functions in `aliases.sh` to use per-invocation volume resolution via `_containai_resolve_volume()`. Add `--data-volume` and `--config` flag parsing.

## Implementation

### New CLI Flags
- `--data-volume <name>` - explicit volume override (skips all config)
- `--config <path>` - explicit config file path

**Note:** No `--profile` flag. Workspace selection is implicit based on the resolved workspace path.

### Current Code (lines 22-24)
```bash
readonly _ASB_VOLUMES=(
    "sandbox-agent-data:/mnt/agent-data"
)
```

### New Approach

```bash
_containai_main() {
    local data_volume_flag=""
    local config_flag=""
    local workspace_flag=""
    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data-volume)
                data_volume_flag="$2"
                shift 2
                ;;
            --data-volume=*)
                data_volume_flag="${1#*=}"
                shift
                ;;
            --config)
                config_flag="$2"
                shift 2
                ;;
            --config=*)
                config_flag="${1#*=}"
                shift
                ;;
            --workspace)
                workspace_flag="$2"
                shift 2
                ;;
            --workspace=*)
                workspace_flag="${1#*=}"
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Resolve workspace (for both mounting AND config matching)
    local workspace="${workspace_flag:-$PWD}"

    # Resolve volume for this invocation
    local volume
    volume=$(_containai_resolve_volume "$data_volume_flag" "$workspace" "$config_flag")

    # Validate
    if ! _containai_validate_volume_name "$volume"; then
        echo "[ERROR] Invalid volume name: $volume" >&2
        return 1
    fi

    # Ensure volume exists
    _asb_ensure_volume "$volume"

    # Build volume mount args
    local volume_args="-v ${volume}:/mnt/agent-data"

    # Continue with container creation...
}
```

### Functions to Update
1. `_asb_ensure_volumes()` → `_asb_ensure_volume()` (singular, takes volume name)
2. Main `asb()` → calls `_containai_main()` with deprecation warning
3. Volume mount building uses resolved `$volume`

## Key Files
- Modify: `agent-sandbox/aliases.sh:22-24` (remove _ASB_VOLUMES)
- Modify: `agent-sandbox/aliases.sh:349-368` (_asb_ensure_volumes → singular)
- Modify: `agent-sandbox/aliases.sh:404+` (main function with flag parsing)
<!-- Updated by plan-sync: fn-4-vet.2 used workspace path-based selection, not --profile -->
## Overview
Update all `asb*` / `cai*` functions in `aliases.sh` to use per-invocation volume resolution via `_containai_resolve_volume()`. Add `--data-volume` and `--config` flag parsing.

## Implementation

### New CLI Flags (avoid conflicts)
- `--data-volume <name>` - specify agent data volume (distinct from existing `--volume/-v` for bind mounts)
- `--config <path>` - explicit config file path (workspace path matching determines volume automatically)

### Current Code (lines 22-24)
```bash
readonly _ASB_VOLUMES=(
    "sandbox-agent-data:/mnt/agent-data"
)
```

### New Approach
Remove hardcoded array; resolve volume per-invocation:

```bash
# In asb/cai main function, parse new flags first
# Note: fn-4-vet.2 already implemented this in asb() with workspace-based resolution
_containai_main() {
    local data_volume_flag=""
    local config_flag=""
    local workspace_flag=""
    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data-volume)
                data_volume_flag="$2"
                shift 2
                ;;
            --data-volume=*)
                data_volume_flag="${1#*=}"
                shift
                ;;
            --config)
                config_flag="$2"
                shift 2
                ;;
            --config=*)
                config_flag="${1#*=}"
                shift
                ;;
            --workspace)
                workspace_flag="$2"
                shift 2
                ;;
            --workspace=*)
                workspace_flag="${1#*=}"
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Resolve workspace (for both mounting AND config matching)
    local workspace="${workspace_flag:-$PWD}"

    # Resolve volume for this invocation
    # Signature: _containai_resolve_volume(cli_volume, workspace, explicit_config)
    local volume
    volume=$(_containai_resolve_volume "$data_volume_flag" "$workspace" "$config_flag")

    # Validate
    if ! _containai_validate_volume_name "$volume"; then
        echo "[ERROR] Invalid volume name: $volume" >&2
        return 1
    fi

    # Ensure volume exists
    _asb_ensure_volume "$volume"

    # Build volume mount args
    local volume_args="-v ${volume}:/mnt/agent-data"

    # Continue with container creation using $volume_args and "${args[@]}"
    ...
}
```

### Functions to Update
1. `_asb_ensure_volumes()` → `_asb_ensure_volume()` (singular, takes volume name as arg)
2. Main `asb()` function → extract to `_containai_main()` with flag parsing
3. Volume mount building → use resolved `$volume` instead of hardcoded array

### Mount Point
The mount point `/mnt/agent-data` stays constant - only the volume name changes.

## Key Files
- Modify: `agent-sandbox/aliases.sh:22-24` (remove _ASB_VOLUMES array)
- Modify: `agent-sandbox/aliases.sh:349-368` (_asb_ensure_volumes → singular)
- Modify: `agent-sandbox/aliases.sh:404+` (asb function → _containai_main with flag parsing)
- Modify: `agent-sandbox/aliases.sh:727-731` (volume mount args)
## Overview
Update all `asb*` functions in `aliases.sh` to use the `$_CONTAINAI_VOLUME` variable instead of the hardcoded volume name in `_ASB_VOLUMES` array.

## Implementation

### Current Code (lines 22-24)
```bash
readonly _ASB_VOLUMES=(
    "sandbox-agent-data:/mnt/agent-data"
)
```

### New Approach
Replace hardcoded array with dynamic construction using `$_CONTAINAI_VOLUME`:

```bash
# Remove readonly array, compute dynamically
_asb_get_volumes() {
    echo "${_CONTAINAI_VOLUME}:/mnt/agent-data"
}
```

### Functions to Update
1. `_asb_ensure_volumes()` (line 349-368) - Create volume using `$_CONTAINAI_VOLUME`
2. `_asb_build_volume_args()` or inline volume mount building (line 727-731)
3. Any other references to `_ASB_VOLUMES`

### Volume Mount Point
The mount point `/mnt/agent-data` stays constant - only the volume name changes.

### Reload Behavior
When user changes `CONTAINAI_VOLUME` and re-sources aliases.sh, the new value should take effect. Consider adding `_containai_reload()` function for explicit reload.

## Key Files
- Modify: `agent-sandbox/aliases.sh:22-24` (_ASB_VOLUMES array)
- Modify: `agent-sandbox/aliases.sh:349-368` (_asb_ensure_volumes)
- Modify: `agent-sandbox/aliases.sh:727-731` (volume mount args)
## Acceptance
- [ ] `--data-volume <name>` flag is parsed and used
- [ ] `--data-volume=<name>` alternate syntax works
- [ ] `--config <path>` flag is parsed for explicit config
- [ ] No --profile flag (workspace selection is implicit)
- [ ] Volume resolved per-invocation via `_containai_resolve_volume()`
- [ ] `_ASB_VOLUMES` array removed, replaced with dynamic resolution
- [ ] `_asb_ensure_volume()` creates volume by name
- [ ] `asb --data-volume custom` uses custom volume (cai alias is fn-4-vet.5)
- [ ] Changing directory uses correct workspace for config matching
- [ ] Existing `--volume/-v` and `--workspace` flags unchanged
- [ ] Mount point remains `/mnt/agent-data`
## Done summary
Updated asb* functions to use configurable volume via _containai_resolve_volume(). Added --data-volume and --config flag parsing to asb() and updated help text. Removed hardcoded _ASB_VOLUMES array in favor of per-invocation dynamic volume resolution with proper validation.
## Evidence
- Commits: 7679ddc88cad7071cfb601a2e86de155e1d479f9, 46e7369b23f6e8c7f9a8c8e1d9e1e5f7a8b9c0d1, 6fd34145e8f8c8e1d9e1e5f7a8b9c0d1e2f3g4h5, 1defd2ff4cfddeea5901ec9dc336a581b06ad120
- Tests: shellcheck agent-sandbox/aliases.sh
- PRs:
