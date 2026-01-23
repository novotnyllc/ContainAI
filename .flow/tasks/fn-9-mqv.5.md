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
Added integration tests for import source functionality: export-import round-trip verification, tgz import idempotency, invalid/corrupt tgz error handling, and missing source error handling.
## Evidence
- Commits: c65d5fed0d53a4a7a0e1ec86488fdb1bf9cdcdac, ca9eaee429c4044617da4ff2bd18b2c18ca3e38a
- Tests: bash -n agent-sandbox/test-sync-integration.sh
- PRs:
