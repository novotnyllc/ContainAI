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
Implemented test_existing_volume() to validate data persistence across container recreation. The test pre-populates a volume with marker file and configs, creates a new container attaching to the existing volume, then verifies data persistence via marker file, symlink validity pointing to volume data, and config accessibility through symlinks with realpath validation.
## Evidence
- Commits: be3de4a, e35ffe9, 67f4f27
- Tests: shellcheck -x tests/integration/test-sync-integration.sh, bash -n tests/integration/test-sync-integration.sh
- PRs:
