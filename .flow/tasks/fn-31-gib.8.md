# fn-31-gib.8 Implement hot-reload test scenario

## Description
Test running container + import (live reload). Changes should be visible inside container without restart.

## Acceptance
- [ ] Test function `test_hot_reload()` in test suite
- [ ] Test container named `test-hot-reload-XXXX` with `containai.test=1` label
- [ ] Test volume named `test-hot-reload-data-XXXX` with `containai.test=1` label
- [ ] Starts container with initial volume data
- [ ] Modifies host config while container is running
- [ ] Runs `cai import` to sync changes
- [ ] Asserts: changes visible inside container via `docker exec cat` without restart
- [ ] Asserts: no file corruption (compare checksums)
- [ ] Asserts: container process still running after import
- [ ] Cleans up on success/failure (trap)

## Done summary
## Summary

Implemented `test_hot_reload()` function in `tests/integration/test-sync-integration.sh` (Test 65) that validates live config import while a container is running. The test verifies that host config changes sync to a running container without restart and without file corruption.

## Changes

- Added `test_hot_reload()` function (lines 4831-5057) that:
  1. Creates test volume `test-hot-reload-data-XXXX` with `containai.test=1` label
  2. Creates test container `test-hot-reload-XXXX` with `containai.test=1` label
  3. Populates volume with initial config and starts container
  4. Modifies host config files while container is running
  5. Runs `cai import` to sync changes (hot-reload)
  6. Asserts changes visible inside container via `docker exec cat`
  7. Asserts no file corruption via checksum comparison
  8. Asserts container process still running after import
  9. Cleans up via RETURN trap on success/failure

- Updated test header comment to include Test 65
- Added `test_hot_reload` call to main test runner

## Test Coverage

The test covers all acceptance criteria:
- Container and volume naming convention with labels
- Live import while container running
- Change visibility without restart
- File integrity (checksums + JSON validation)
- Container process continuity
- Proper cleanup on all exit paths
## Evidence
- Commits:
- Tests: tests/integration/test-sync-integration.sh::test_hot_reload
- PRs:
