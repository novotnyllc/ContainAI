# fn-34-fk5.8: Add --export flag to cai stop

## Goal
Add option to run export before stopping container for work preservation.

## Order of Operations
1. Parse `--export` flag
2. Run export (if `--export`)
3. Check sessions (if not `--force`)
4. Stop container

## Constraints
- `--export` is mutually exclusive with `--all`
- When stopping interactively selected container, export that container

## Implementation
In `_containai_stop_cmd`:

```bash
# Add to flag parsing:
--export) export_first=true ;;

# Add mutual exclusivity check:
if [[ "$export_first" == "true" && "$stop_all" == "true" ]]; then
    _cai_error "--export and --all are mutually exclusive"
    return 1
fi

# After resolving container_name, before session check:
if [[ "$export_first" == "true" ]]; then
    _cai_info "Exporting data volume..."
    # Use --container flag only; export resolves context internally
    if ! _containai_export_cmd --container "$container_name"; then
        if [[ "$force_flag" != "true" ]]; then
            _cai_error "Export failed. Use --force to stop anyway."
            return 1
        fi
        _cai_warn "Export failed, continuing due to --force"
    fi
fi
```

## Files
- `src/containai.sh`: `_containai_stop_cmd` function

## Acceptance
- [x] `cai stop --export` runs export with `--container` flag only
- [x] Export resolves context internally (no --context passed)
- [x] `--export` and `--all` are mutually exclusive (error if both)
- [x] Export failures prevent stop (unless `--force`)
- [x] Order: export → session check → stop

## Done summary
# Implementation Summary: fn-34-fk5.8 - Add --export flag to cai stop

## Changes Made

1. **Updated `_containai_stop_help()`** (src/containai.sh:375-413)
   - Added `--export` flag to options list with description
   - Updated `--all` description to note mutual exclusivity with `--export`
   - Added note about `--force` continuing after export failure
   - Added "Export Before Stop" section explaining order of operations
   - Added example: `cai stop --export` and `cai stop --export --force`

2. **Updated `_containai_stop_cmd()`** (src/containai.sh:1483-1790)
   - Added `local export_first=false` variable initialization
   - Added `--export` case in flag parsing to set `export_first=true`
   - Added mutual exclusivity check between `--export` and `--all`
   - Added `--export` to known flags in Pass 3 validation
   - Added export logic in `--container` branch before session check
   - Added export logic in workspace-resolved branch before session check

## Order of Operations (as specified)
1. Parse `--export` flag
2. Run export (if `--export`)
3. Check sessions (if not `--force`)
4. Stop container

## Key Behaviors
- `--export` and `--all` are mutually exclusive (returns error if both)
- Export uses `--container` flag only; export resolves context internally
- Export failures prevent stop unless `--force` is used
- When `--force` is used and export fails, a warning is emitted and stop continues
## Evidence
- Commits:
- Tests: help_output, mutual_exclusivity, shellcheck
- PRs:
