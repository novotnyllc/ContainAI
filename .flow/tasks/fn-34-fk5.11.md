# fn-34-fk5.11: Update shell completion

## Goal
Update shell completion functions for new commands and flags.

## New Completions
1. `cai status`: `--json`, `--workspace`, `--container`
2. `cai gc`: `--dry-run`, `--force`, `--age`, `--images`
3. `cai stop --force`: Add to existing stop completions
4. `cai stop --export`: Add to existing stop completions

## Implementation
Update `_containai_completions_*` functions in `src/containai.sh`:

```bash
# Add to completion flag lists
local status_flags="--json --workspace --container -h --help"
local gc_flags="--dry-run --force --age --images -h --help"

# Update stop_flags to include --force --export
local stop_flags="--container --all --remove --force --export -h --help"
```

## Files
- `src/containai.sh`: `_containai_completions_*` functions

## Acceptance
- [ ] `cai status --` completes flags
- [ ] `cai gc --` completes flags
- [ ] `cai stop --force` completes
- [ ] `cai stop --export` completes
