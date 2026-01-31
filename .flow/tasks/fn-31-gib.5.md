# fn-31-gib.5 Create import test infrastructure

## Description
Extend existing `tests/integration/test-sync-integration.sh` framework with helpers for import scenarios. Use labels + name prefixes for safe cleanup.

## Acceptance
- [ ] Test helper function `create_test_container()` accepts name and applies `containai.test=1` label
- [ ] Test helper function `create_test_volume()` accepts name and applies `containai.test=1` label
- [ ] Cleanup function `cleanup_test_resources()` removes by label first, name prefix as fallback
- [ ] Fixture creation helper `create_claude_fixture()` populates standard Claude config
- [ ] All test resources use `test-` prefix AND `containai.test=1` label
- [ ] Helper functions documented in script header or README

## Done summary
Added import test infrastructure with labeled resources for safe parallel cleanup. Implemented create_test_container(), create_test_volume(), cleanup_test_resources(), and create_claude_fixture() helpers with run-scoped labels and proper input validation.
## Evidence
- Commits: e5e4a09, 8a52198
- Tests: bash -n tests/integration/test-sync-integration.sh, shellcheck -x tests/integration/test-sync-integration.sh
- PRs:
