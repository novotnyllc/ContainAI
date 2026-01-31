# fn-31-gib.14 Implement no-pollution test scenario

## Description
Test import with partial agent configs creates no empty directories for agents user doesn't have.

## Acceptance
- [ ] Test function `test_no_pollution()` in test suite
- [ ] Test host has ONLY Claude config (no ~/.cursor, ~/.kiro, ~/.aider, etc.)
- [ ] Runs import successfully
- [ ] Asserts: container has `~/.claude` symlink (expected)
- [ ] Asserts: container does NOT have `~/.cursor` directory or symlink
- [ ] Asserts: container does NOT have `~/.kiro` directory or symlink
- [ ] Asserts: only configured agents have symlinks (ls -la ~ shows expected set)

## Done summary
Implemented test_no_pollution() to verify import with partial agent configs does not create empty directories for unused agents. Test creates source with only Claude config, imports to volume, and asserts optional agent paths (cursor, kiro, aider, continue, copilot, gemini) do not exist in container.
## Evidence
- Commits: 32ec3e4, a0fd55f
- Tests: shellcheck -x tests/integration/test-sync-integration.sh
- PRs:
