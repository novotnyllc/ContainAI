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
- [ ] `cai stop --export` runs export with `--container` flag only
- [ ] Export resolves context internally (no --context passed)
- [ ] `--export` and `--all` are mutually exclusive (error if both)
- [ ] Export failures prevent stop (unless `--force`)
- [ ] Order: export → session check → stop
