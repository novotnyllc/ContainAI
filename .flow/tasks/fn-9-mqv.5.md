# fn-9-mqv.5 Add import source integration tests

## Description
Add integration tests for import source functionality.

**Size:** M
**Files:** `agent-sandbox/test-sync-integration.sh` (or new test file)

## Approach

- Follow test patterns in `test-sync-integration.sh:35-96`
- Use unique volume IDs with `TEST_RUN_ID` pattern
- Cleanup with trap on EXIT
- Test cases:
  1. Export then import from tgz - verify idempotency
  2. Import from directory - verify sync works
  3. Invalid tgz - verify error handling
  4. Missing source - verify error handling

## Key context

- Existing tests use `run_in_rsync()` helper to inspect volumes
- Use `pass()`/`fail()`/`info()` helpers for output
- Need temp directory for test tgz files
- Test idempotency by importing twice and comparing checksums
## Acceptance
- [ ] Test: export volume, import from tgz, volume matches
- [ ] Test: import from tgz twice produces identical result
- [ ] Test: import from directory syncs files
- [ ] Test: invalid tgz produces error exit code
- [ ] Test: missing source produces error exit code
- [ ] Tests clean up volumes on exit
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
