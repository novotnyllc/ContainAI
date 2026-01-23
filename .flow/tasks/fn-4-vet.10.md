# fn-4-vet.10 Create lib/import.sh - cai import subcommand

<!-- Updated by plan-sync: fn-4-vet.4 architecture note -->
<!-- lib/config.sh doesn't exist yet - config functions are in aliases.sh -->
<!-- Depends on lib extraction from fn-4-vet.8 OR can source aliases.sh directly -->

## Description
Create `agent-sandbox/lib/import.sh` - the `cai import` subcommand.

## Implementation

Refactor `sync-agent-plugins.sh` logic into a sourceable library:

### `_containai_import(volume, dry_run, no_excludes, workspace, config)`

1. Validate prerequisites (docker, jq) and volume name
2. Ensure volume exists (unless dry-run)
3. Resolve exclude patterns from config via `_containai_resolve_excludes` (unless no_excludes)
4. Run rsync via eeacms/rsync container with SYNC_MAP
5. Output "Using data volume: $volume" for verification
6. Perform post-sync transformations (JSON path fixes, plugin merges)

## SYNC_MAP

Keep existing SYNC_MAP from sync-agent-plugins.sh:39-98 but make it configurable:
- Callers can override `_IMPORT_SYNC_MAP` before calling `_containai_import`
- Fall back to hardcoded defaults if not set

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
- Respects `--no-excludes` to disable all exclusions (both config excludes AND .system/)
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
# fn-4-vet.10 Summary

Created `agent-sandbox/lib/import.sh` implementing the `cai import` subcommand as a sourceable library.

## Implementation

- **`_containai_import(volume, dry_run, no_excludes, workspace, config)`** - Main import function that:
  1. Validates prerequisites (docker, jq)
  2. Ensures volume exists (unless dry-run)
  3. Resolves exclude patterns from config via `_containai_resolve_excludes` (unless --no-excludes)
  4. Builds exclude flags and passes to rsync container script
  5. Runs rsync via eeacms/rsync container with SYNC_MAP
  6. Outputs "Using data volume: $volume" for verification
  7. Performs post-sync transformations (JSON path fixes, plugin merges)

## Key Features

- **SYNC_MAP**: Kept existing map from sync-agent-plugins.sh, now defined as `_IMPORT_SYNC_MAP`
- **Exclude Integration**: Merges default_excludes + workspace excludes from config
- **Dry-run Support**: Shows what would sync without making changes
- **No-excludes Support**: Skips all exclude patterns when flag is true
- **Standalone Usage**: Works with `source lib/config.sh && source lib/import.sh`

## Files Changed

- `agent-sandbox/lib/import.sh` (new file)
## Evidence
- Commits:
- Tests: source lib/config.sh && source lib/import.sh succeeds, declare -f _containai_import confirms function exists
- PRs:
