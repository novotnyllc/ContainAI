# fn-6-aaz.6 Add integration tests for env import

## Description
Add integration tests for env var import feature covering all acceptance criteria including context handling and edge cases.

**Size:** M
**Files:** `agent-sandbox/test-sync-integration.sh` (extend existing)

## Approach

- Follow test patterns at `test-sync-integration.sh:170-300`
- Create test volume with unique name: `containai-test-env-${TEST_RUN_ID}`
- Test all acceptance criteria from epic spec (24 test cases)
- Use `env -u` to clear external vars for hermetic tests
- Cleanup test volumes after tests via trap
- Test context-aware behavior if multiple contexts available
## Acceptance
- [ ] Test: basic allowlist import from host env
- [ ] Test: `from_host=false` prevents host env reading
- [ ] Test: source .env file parsed correctly
- [ ] Test: merge precedence (host > file)
- [ ] Test: missing vars produce warning (key only), not error
- [ ] Test: multiline values skipped with warning (line number + key)
- [ ] Test: empty allowlist skips with INFO
- [ ] Test: .env file has correct permissions (0600)
- [ ] Test: invalid var names skipped with warning
- [ ] Test: duplicate allowlist keys deduplicated
- [ ] Test: `export KEY=VALUE` format accepted
- [ ] Test: values with spaces preserved
- [ ] Test: CRLF line endings handled
- [ ] Test: entrypoint only sets vars not in environment
- [ ] Test: runtime `-e` flags take precedence (empty string = present)
- [ ] Test: dry-run prints keys only, no volume write
- [ ] Test: symlink source .env rejected
- [ ] Test: TOCTOU protection (symlink checks on mount/target/temp)
- [ ] Test: log hygiene - values never printed in warnings
- [ ] Test: env_file absolute path rejected
- [ ] Test: env_file outside workspace rejected
- [ ] Test: entrypoint loads after ownership fix
- [ ] Test: unreadable .env warns, continues
- [ ] Tests use hermetic env (env -u)
- [ ] Test volumes cleaned up
## Done summary
Added 24 integration tests (Tests 16-39) for env var import feature covering all acceptance criteria including allowlist import, from_host behavior, env_file parsing, merge precedence, multiline handling, permissions, TOCTOU protections, log hygiene, and entrypoint loading semantics.
## Evidence
- Commits: 1beadcd, e87742b, ba5b875, a4048a3, aa2c321
- Tests: agent-sandbox/test-sync-integration.sh (Tests 16-39)
- PRs:
