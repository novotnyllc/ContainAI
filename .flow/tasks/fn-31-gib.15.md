# fn-31-gib.15 Implement cai sync test scenario

## Description
Test in-container cai sync moves files and creates symlinks correctly.

## Acceptance
- [ ] Test function `test_cai_sync()` in test suite
- [ ] Starts container where optional entry `~/.cursor/rules` is real directory (not symlink)
- [ ] Runs `docker exec test-container cai sync`
- [ ] Asserts: directory moved to `/mnt/agent-data/cursor/rules`
- [ ] Asserts: symlink created at `~/.cursor/rules` pointing to `/mnt/agent-data/cursor/rules`
- [ ] Asserts: files accessible via symlink (content matches)
- [ ] Test also verifies `cai sync` fails when run in container without `/mnt/agent-data` mounted

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
