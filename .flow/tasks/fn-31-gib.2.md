# fn-31-gib.2 Fix missing Codex skills and symlinks

## Description
Create minimal repro for Codex skills not appearing, then fix the specific failure point. Current state: `.codex/skills` exists in `src/sync-manifest.toml` with `flags = "dxR"`, and symlinks are generated in `src/container/generated/symlinks.sh`.

**Investigation needed:**
1. Document exact host layout that fails
2. Identify failure point: (a) host→volume sync, (b) container symlink creation, (c) runtime link repair

## Acceptance
- [ ] Documented repro scenario in task summary (exact host `~/.codex/skills` layout that fails)
- [ ] Root cause identified and documented (which code path fails)
- [ ] Fix applied to `src/lib/import.sh`, `gen-dockerfile-symlinks.sh`, or `containai-init.sh` as appropriate
- [ ] Test case: `docker exec test-container ls -la ~/.codex/skills` shows valid symlink to `/mnt/agent-data/codex/skills`
- [ ] Test case: Skills in `~/.codex/skills/` are accessible and functional

## Done summary

**Repro scenario (failing host layout):**
- Host has `~/.codex` directory but NOT `~/.codex/skills` subdirectory
- Host has `~/.claude` directory but NOT `~/.claude/skills` subdirectory
- Manifest entries exist with `flags = "dxR"` (directory, exclude .system/, remove existing)

**Root cause (failure point a: host→volume sync):**
In `src/lib/import.sh:1760-1768`, the `copy()` function's missing-source handler only called `ensure()` for entries with `j` (JSON init) or `s` (secret) flags. Directory entries with just `d` flag were silently skipped when the host source didn't exist. This left `/data/codex/skills` and `/data/claude/skills` non-existent on the volume, causing the container symlinks (`~/.codex/skills -> /mnt/agent-data/codex/skills`) to point to non-existent targets.

**Fix applied:** Added `*d*` to the case pattern in `copy()` so directory entries call `ensure()` even when the host source is missing. This creates empty directories on the volume for symlinks to target.

**Tests added:**
- Volume directory existence: `/data/codex/skills` and `/data/claude/skills` in `test_full_sync`
- Symlink verification: `~/.codex/skills` and `~/.claude/skills` point to correct volume paths
- Symlink accessibility: `ls` on symlinked directories succeeds (functional check)

## Evidence
- Commits: 598d3e5e68bd996749856a951ae31b510d3445be
- Tests: shellcheck -x src/lib/import.sh, shellcheck -x tests/integration/test-sync-integration.sh
- PRs:
