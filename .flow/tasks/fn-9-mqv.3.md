# fn-9-mqv.3 Implement tgz restore function

## Description
Implement function to restore volume from tgz archive (idempotent).

**Size:** M
**Files:** `agent-sandbox/lib/import.sh`

## Approach

- Add `_import_restore_from_tgz()` function
- Follow export pattern at `lib/export.sh:233-243` for docker tar operations
- Use `alpine:3.20` container (same as export) for consistency
- Steps:
  1. Validate archive with `tar -tzf` (detect corrupt files early)
  2. Clear volume contents (for idempotency)
  3. Extract archive to volume via docker run
- Use `--network=none` for isolation (matches existing pattern)

## Key context

- tgz archives have volume layout (`./claude/...`) not host layout
- This bypasses SYNC_MAP - direct extraction, no transforms
- Clear before extract ensures idempotency (no orphaned files)
- Pattern for docker tar: `docker run --rm -v vol:/data alpine tar -xzf - -C /data < archive.tgz`
## Acceptance
- [ ] `_import_restore_from_tgz volume /path/to.tgz` extracts archive
- [ ] Corrupt tgz file produces clear error (not silent failure)
- [ ] Running twice produces identical volume state (idempotent)
- [ ] Volume contents cleared before extraction
- [ ] Uses `--network=none` for container isolation
- [ ] Uses `alpine:3.20` image (matches export)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
