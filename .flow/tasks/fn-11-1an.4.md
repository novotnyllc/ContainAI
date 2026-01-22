# fn-11-1an.4 Add integration tests for symlink relinking

## Description
Add integration tests validating symlink relinking behavior during import.

**Size:** M
**Files:** `tests/integration/test-sync-integration.sh`

## Approach

Follow existing test patterns in `test-sync-integration.sh`:
- Use `populate_fixture()` pattern (line 180)
- Use hermetic test volumes with `TEST_RUN_ID` (line 72-73)
- Use `run_in_rsync()` helper (line 126-143)

Add test cases:
1. Basic relinking - symlink within same dir, target also imported
2. Relative symlink - stays relative after relink
3. Absolute symlink - becomes container-absolute
4. External symlink - preserved with warning
5. Broken symlink - preserved as-is
6. Circular symlink - no infinite loop
7. Directory symlink - handled correctly
## Acceptance
- [ ] Test: symlink within import tree is relinked correctly
- [ ] Test: relative symlink remains relative
- [ ] Test: absolute symlink converted to container path
- [ ] Test: external symlink preserved (not relinked)
- [ ] Test: broken symlink does not cause error
- [ ] Test: circular symlinks do not hang
- [ ] Test: directory symlinks work (ln -sfn pitfall handled)
- [ ] All existing tests continue to pass
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
