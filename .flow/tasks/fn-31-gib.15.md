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
Implemented test_cai_sync() test scenario verifying in-container cai sync moves files to volume and creates symlinks correctly, plus verifies sync fails without /mnt/agent-data mounted.
## Evidence
- Commits: 7d2c675, 5f33dcf, ff9229a, 5a69f7f, 358d11e, ad6f570
- Tests: shellcheck -x tests/integration/test-sync-integration.sh
- PRs:
