# fn-9-mqv.4 Support directory source in import

## Description
Support importing from arbitrary directory (not just `$HOME`).

**Size:** M
**Files:** `agent-sandbox/lib/import.sh`

## Approach

<!-- Updated by plan-sync: fn-9-mqv.1 already added from_source as 7th parameter -->
- Use existing `from_source` (7th parameter) in `_containai_import()` - already added by fn-9-mqv.1
- Replace hardcoded `$HOME` bind mount at line 517-521 with `$from_source` when set
- Keep existing SYNC_MAP and rsync mechanism
- Run post-transforms reading from source directory (not `$HOME`)
- Default to `$HOME` when `from_source` is empty (backward compatible)

## Key context

- SYNC_MAP paths use `/source/...` - this maps to the bind mount
- Post-transform at line 559-606 reads `$HOME/.claude/plugins/` - needs to read from source dir instead
- Directory layout matches host layout (unlike tgz which has volume layout)
- Must validate source directory exists and is readable
## Acceptance
- [x] `_containai_import vol --from /other/dir` syncs from that directory
- [x] SYNC_MAP paths resolve against specified source directory
- [x] Post-transforms read from source directory (not hardcoded $HOME)
- [x] Missing source directory produces clear error
- [x] No `--from` defaults to `$HOME` (backward compatible)
- [x] Dry-run mode works with custom source

## Done summary
Implemented directory source support for `cai import --from <dir>`. When --from points to a directory, syncs from that directory instead of $HOME. Post-transforms read source files from the specified directory and perform best-effort path rewriting for both $HOME and source_root prefixes.

## Evidence
- Commits: 4db0a37, 495af13, 3d0384a, c0b6eb7
- Tests: manual verification of acceptance criteria
- PRs:
