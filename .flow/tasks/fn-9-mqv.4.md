# fn-9-mqv.4 Support directory source in import

## Description
Support importing from arbitrary directory (not just `$HOME`).

**Size:** M
**Files:** `agent-sandbox/lib/import.sh`

## Approach

- Modify `_containai_import()` signature to accept source path parameter
- Replace hardcoded `$HOME` bind mount at line 517-521
- Keep existing SYNC_MAP and rsync mechanism
- Run post-transforms reading from source directory (not `$HOME`)
- Default to `$HOME` when no source specified (backward compatible)

## Key context

- SYNC_MAP paths use `/source/...` - this maps to the bind mount
- Post-transform at line 559-606 reads `$HOME/.claude/plugins/` - needs to read from source dir instead
- Directory layout matches host layout (unlike tgz which has volume layout)
- Must validate source directory exists and is readable
## Acceptance
- [ ] `_containai_import vol --from /other/dir` syncs from that directory
- [ ] SYNC_MAP paths resolve against specified source directory
- [ ] Post-transforms read from source directory (not hardcoded $HOME)
- [ ] Missing source directory produces clear error
- [ ] No `--from` defaults to `$HOME` (backward compatible)
- [ ] Dry-run mode works with custom source
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
