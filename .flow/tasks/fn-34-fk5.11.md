# fn-34-fk5.11: Update shell completion

## Dependencies
- fn-34-fk5.5 (Add `--force` flag to cai stop)
- fn-34-fk5.6 (Implement cai status command)
- fn-34-fk5.8 (Add `--export` flag to cai stop)
- fn-34-fk5.9 (Implement cai gc command)

## Blocked

This task is blocked pending completion of dependencies. Shell completions cannot advertise commands/flags that don't exist yet. See `.flow/memory/pitfalls.md` for documented pitfall.

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

## Done summary
Blocked:
# Block Reason: fn-34-fk5.11

This task is blocked pending completion of its dependencies:

- **fn-34-fk5.5** (Add `--force` flag to cai stop) - status: todo
- **fn-34-fk5.6** (Implement cai status command) - status: todo
- **fn-34-fk5.8** (Add `--export` flag to cai stop) - status: todo
- **fn-34-fk5.9** (Implement cai gc command) - status: todo

The shell completions for this task would advertise:
1. `cai status --json --workspace --container` - command doesn't exist
2. `cai gc --dry-run --force --age --images` - command doesn't exist
3. `cai stop --force` - flag not implemented
4. `cai stop --export` - flag not implemented

Shell completions cannot advertise commands/flags that don't exist yet.
## Evidence
- Commits:
- Tests:
- PRs:
