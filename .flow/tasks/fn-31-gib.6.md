# fn-31-gib.6 Implement new-volume test scenario

## Description
Test fresh container + fresh volume + import workflow. This validates the initial setup path.

## Acceptance
- [ ] Test function `test_new_volume()` in test suite
- [ ] Creates container named `test-new-volume-XXXX` with `containai.test=1` label
- [ ] Creates volume named `test-new-volume-data-XXXX` with label
- [ ] Runs `cai import` to sync host configs to volume
- [ ] Asserts: expected files present in volume via `docker exec ls /mnt/agent-data/claude`
- [ ] Asserts: symlinks valid via `docker exec readlink ~/.claude`
- [ ] Cleans up container and volume on success and failure (trap)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
