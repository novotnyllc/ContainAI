# fn-39-ua0.1 Test infrastructure setup

## Description
Create test harness for sync E2E tests: mock HOME setup, container management, test helpers.

**Size:** M
**Files:** `tests/integration/test-sync-e2e.sh`, `tests/integration/sync-test-helpers.sh`

## Approach

### Mock HOME Setup
```bash
setup_mock_home() {
    TEST_HOME=$(mktemp -d)
    # Create directory structure for all agents
    mkdir -p "$TEST_HOME/.claude" "$TEST_HOME/.gemini" "$TEST_HOME/.codex" ...
    # Create mock config files with test content
    echo '{"test": true}' > "$TEST_HOME/.claude/settings.json"
    ...
}
```

### Container Management
```bash
start_test_container() {
    local name="test-sync-$$"
    docker run -d --name "$name" containai:latest sleep infinity
    echo "$name"
}

exec_in_container() {
    docker exec "$CONTAINER_NAME" "$@"
}

cleanup_container() {
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
```

### Test Helpers
```bash
assert_file_exists() { ... }
assert_file_contains() { ... }
assert_symlink_target() { ... }
assert_permissions() { ... }
run_test() { ... }
print_summary() { ... }
```

## Key context

- Pattern: `tests/integration/test-containai.sh` for existing test structure
- Use `test-` prefix for container names
- Trap EXIT to ensure cleanup
## Acceptance
- [ ] test-sync-e2e.sh created with main structure
- [ ] sync-test-helpers.sh created with helper functions
- [ ] setup_mock_home() creates all agent directories
- [ ] Container start/stop/exec helpers work
- [ ] Assert functions work (file exists, contains, symlink, permissions)
- [ ] Cleanup on exit (trap)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
