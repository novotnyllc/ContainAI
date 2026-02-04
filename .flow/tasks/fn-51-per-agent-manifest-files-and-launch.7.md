# Task fn-51.7: Update check-manifest-consistency.sh for new structure

**Status:** pending
**Depends on:** fn-51.1, fn-51.3, fn-51.6

## Objective

Update consistency checker to work with per-agent manifests directory.

## Context

Current `scripts/check-manifest-consistency.sh`:
- Reads entries from `src/sync-manifest.toml`
- Compares against `_IMPORT_SYNC_MAP` in `src/lib/import.sh`
- CI enforces this check

New structure:
- Source of truth is `src/manifests/*.toml`
- No intermediate file
- Import map must still match

Note: User manifests (`~/.config/containai/manifests/`) are runtime-only and don't need CI consistency checks.

## Implementation

1. Update consistency check to:
   - Read from `src/manifests/*.toml` directly
   - Compare against `_IMPORT_SYNC_MAP` in import.sh
   - Report which source file contains mismatches

2. Add validation for per-agent files:
   - Valid TOML syntax
   - Required fields present (source, target, flags)
   - `[agent]` section has required fields if present

3. Update error messages to show source file:
```
MISMATCH in claude.toml:
  Entry: .claude/settings.json
  Manifest flags: fj
  Import map flags: f
```

## Acceptance Criteria

- [ ] Consistency check reads from `src/manifests/` directory
- [ ] Error messages show source manifest file
- [ ] TOML syntax validation added
- [ ] `[agent]` section validation added
- [ ] CI continues to enforce consistency
- [ ] Existing mismatches still caught

## Notes

- Remove references to `sync-manifest.toml`
- Use `parse-manifest.sh` with directory mode
- User manifests are runtime-only, not checked by CI
