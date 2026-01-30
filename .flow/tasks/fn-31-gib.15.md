# fn-31-gib.15 Implement cai sync test scenario

## Description
Test in-container cai sync moves files and creates symlinks correctly.

## Acceptance
- [ ] Test function `test_cai_sync()` in test suite
- [ ] Starts container where optional entry (e.g., ~/.testconfig) is real directory (not symlink)
- [ ] Runs `docker exec test-container cai sync`
- [ ] Asserts: directory moved to `/mnt/agent-data/testconfig`
- [ ] Asserts: symlink created at `~/.testconfig` pointing to `/mnt/agent-data/testconfig`
- [ ] Asserts: files accessible via symlink (content matches)
- [ ] Test also verifies `cai sync` on host fails with appropriate error

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
