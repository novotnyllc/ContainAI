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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
