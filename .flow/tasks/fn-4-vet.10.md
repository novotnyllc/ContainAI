# fn-4-vet.10 Create lib/import.sh - cai import subcommand

## Description
Create `agent-sandbox/lib/import.sh` - the `cai import` subcommand.

## Implementation

Refactor `sync-agent-plugins.sh` logic into a sourceable library:

### `_containai_import(volume, excludes_array, dry_run)`

1. Validate prerequisites (docker, jq)
2. Ensure volume exists (unless dry-run)
3. Build exclude flags from `excludes_array`
4. Run rsync via eeacms/rsync container with SYNC_MAP
5. Output "Using data volume: $volume" for verification

## SYNC_MAP

Keep existing SYNC_MAP from sync-agent-plugins.sh:39-98 but make it configurable:
- Load from config if present
- Fall back to hardcoded defaults

## Exclude Integration

```bash
# Merge default_excludes + workspace excludes from config
# Pass each as --exclude to rsync in container script
for pattern in "${excludes[@]}"; do
    rsync_opts+=(--exclude "$pattern")
done
```

## Key Points
- Must work standalone: `source lib/config.sh && source lib/import.sh`
- Respects `--dry-run` flag
- Respects `--no-excludes` to disable all exclusions
- Prints resolved volume name for verification
## Acceptance
- [ ] File exists at `agent-sandbox/lib/import.sh`
- [ ] `_containai_import` function works correctly
- [ ] Exclude patterns passed to rsync
- [ ] `--dry-run` shows what would sync without changes
- [ ] `--no-excludes` ignores all exclude patterns
- [ ] Outputs "Using data volume: <name>" 
- [ ] Can be sourced with lib/config.sh
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
