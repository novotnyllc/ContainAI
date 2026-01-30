# fn-31-gib.7 Implement existing-volume test scenario

## Description
Test new container attaching to existing data volume. Validates data persistence across container recreation.

## Acceptance
- [ ] Test function `test_existing_volume()` in test suite
- [ ] Test container named `test-existing-volume-XXXX` with `containai.test=1` label
- [ ] Test volume named `test-existing-volume-data-XXXX` with `containai.test=1` label
- [ ] Pre-populates volume with known test data (marker file, config)
- [ ] Creates NEW container attaching to existing volume
- [ ] Asserts: marker file still present via `docker exec cat /mnt/agent-data/marker.txt`
- [ ] Asserts: symlinks valid and point to volume data
- [ ] Asserts: configs accessible via symlinks
- [ ] Cleans up on success/failure (trap)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
