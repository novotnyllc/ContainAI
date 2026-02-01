# fn-42-cli-ux-fixes-hostname-reset-wait-help.9 Implement short container naming (max 24 chars)

## Description
Changed container naming from `containai-{repo}-{branch}` (max 59 chars) to `{repo}-{branch_leaf}` (max 24 chars).

Key changes:
- Removed `containai-` prefix
- Extract branch leaf (last segment of `/`-separated branch path)
  - `feature/oauth` → `oauth`
  - `bugfix/login-fix` → `login-fix`
  - `feat/ui/button` → `button`
  - `main` → `main`
- Truncate to fit 24 chars (alternating between repo and branch when too long)

## Acceptance
- [x] New containers max 24 chars
- [x] Format: `{repo}-{branch_leaf}`, no prefix, no hashes
- [x] Branch uses last segment of `/` path
- [x] Unit tests updated and passing

## Done summary
Implemented short container naming in `_containai_container_name()`:
1. Changed format from `containai-{repo}-{branch}` to `{repo}-{branch_leaf}`
2. Added branch leaf extraction: `branch_leaf="${branch_name##*/}"`
3. Updated max length from 59 to 24 chars
4. Replaced detached HEAD SHA with "detached" token (no hashes per spec)
5. Updated collision handling to truncate base name before adding suffix
6. Updated all unit tests to reflect new naming scheme
7. Added new tests for multi-segment branch leaf extraction
## Evidence
- Commits:
- Tests: tests/unit/test-container-naming.sh (7/7 passing)
- PRs:
