# fn-6-aaz.6 Add integration tests for env import

## Description
Add integration tests for env var import feature covering all acceptance criteria including context handling and edge cases.

**Size:** M  
**Files:** `agent-sandbox/test-sync-integration.sh` (extend existing)

## Approach

- Follow test patterns at `test-sync-integration.sh:170-300`
- Create test volume with unique name: `containai-test-env-${TEST_RUN_ID}`
- Test all 18 acceptance criteria from epic spec
- Use `env -u` to clear external vars for hermetic tests
- Cleanup test volumes after tests
- Test context-aware behavior if multiple contexts available
## Approach

- Follow test patterns at `test-sync-integration.sh:170-300`
- Create test volume with unique name: `containai-test-env-${TEST_RUN_ID}`
- Test all acceptance criteria from epic spec
- Use `env -u` to clear external vars for hermetic tests
- Cleanup test volumes after tests
## Approach

- Follow test patterns at `test-sync-integration.sh:170-300`
- Create test volume with unique name: `containai-test-env-${TEST_RUN_ID}`
- Test cases: basic import, from_host flag, env_file source, missing vars, multiline skip
- Use `env -u` to clear external vars for hermetic tests
- Cleanup test volumes after tests
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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
