# fn-34-fk5.11: Update shell completion

## Dependencies
- fn-34-fk5.5 (Add `--force` flag to cai stop)
- fn-34-fk5.6 (Implement cai status command)
- fn-34-fk5.8 (Add `--export` flag to cai stop)
- fn-34-fk5.9 (Implement cai gc command)

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
Updated shell completion functions in `src/containai.sh` for new commands (`status`, `gc`) and updated flags (`--force`, `--export` for `stop`).

**Bash completion changes:**
- Added `status` and `gc` to subcommands list
- Added `status_flags="--json --workspace --container --verbose -h --help"`
- Added `gc_flags="--dry-run --force --age --images --verbose -h --help"`
- Updated `stop_flags` to include `--force` and `--export`
- Added case statements for `status` and `gc` in completion switch

**Zsh completion changes:**
- Added `status:Show container status and resource usage` to subcommands
- Added `gc:Garbage collection for stale containers and images` to subcommands
- Added complete _arguments block for `status` with --json, --workspace, --container, --verbose
- Added complete _arguments block for `gc` with --dry-run, --force, --age, --images, --verbose
- Updated `stop` case to include `--force` and `--export` flags
## Evidence
- Commits:
- Tests: shellcheck src/containai.sh - passed
- PRs:
