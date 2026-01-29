# fn-36-rb7.5 Implement human-readable container naming

## Description
Replace hash-based naming with `containai-{repo}-{branch}` format. Keep `_containai_container_name` as a pure function; collision handling remains in `_cai_resolve_container_name`.

## Acceptance
- [ ] Format: `containai-{repo}-{branch}`, max 63 chars
- [ ] Repo = directory name (last path component)
- [ ] Branch from `git rev-parse --abbrev-ref HEAD`
- [ ] Non-git: use `nogit`
- [ ] Detached HEAD: use 7-char short SHA
- [ ] Sanitization: lowercase, `/` → `-`, remove non-alphanum except `-`
- [ ] Truncate base name to 59 chars (reserve 4 for suffix)
- [ ] `_containai_container_name` has no docker calls or collision logic

## Verification
- [ ] Test naming in git repo, non-git dir, detached HEAD, and long names

## Done summary
## Summary

Implemented human-readable container naming that generates `containai-{repo}-{branch}` format:

- Repo name extracted from workspace path (last component)
- Branch from `git rev-parse --abbrev-ref HEAD`
- Non-git directories use `nogit`
- Detached HEAD uses 7-char short SHA
- Sanitization: lowercase, `/` → `-`, removes non-alphanumeric except `-`, collapses multiple dashes
- Truncates repo/branch separately to guarantee both segments remain (max 59 chars total)
- Pure function with no docker calls; collision handling remains in `_cai_resolve_container_name`
- Updated callers to use `_cai_find_workspace_container` for backward compatibility with legacy containers
- Added collision suffix cap at 999 to ensure max 63 chars

## Files Changed

- `src/lib/container.sh`: Rewrote `_containai_container_name()` function, updated comments
- `src/containai.sh`: Updated fallback to use `_cai_find_workspace_container`
- `src/lib/links.sh`: Updated fallback to use `_cai_find_workspace_container`, updated comments

## Tests

All 32 unit tests pass, shellcheck passes, comprehensive acceptance tests pass.
## Evidence
- Commits:
- Tests: Unit tests: tests/unit/test-container-naming.sh - 5/5 passed, Unit tests: tests/unit/test-exclude-rewrite.sh - 16/16 passed, Unit tests: tests/unit/test-workspace-state.sh - 11/11 passed, Shellcheck: src/lib/container.sh, src/containai.sh, src/lib/links.sh - no errors, Acceptance: 8/8 criteria verified
- PRs:
