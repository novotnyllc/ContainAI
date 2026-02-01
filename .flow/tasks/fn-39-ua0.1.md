# fn-39-ua0.1 Test infrastructure setup

## Description
Create test harness for sync E2E tests: mock HOME setup, container management, test helpers. Reuse patterns from existing test-sync-integration.sh.

**Size:** M
**Files:** `tests/integration/test-sync-e2e.sh`, `tests/integration/sync-test-helpers.sh`

## Approach

### Mock HOME Setup (Selective Creation)
```bash
# Create minimal fixture - tests opt-in to what they need
create_fixture_home() {
    FIXTURE_HOME=$(mktemp -d)
    # Do NOT create all agent dirs - let tests create what they need
    # This allows testing "optional missing = no target" behavior
}

# Per-test helpers for specific agents
create_claude_fixture() {
    mkdir -p "$FIXTURE_HOME/.claude"
    echo '{}' > "$FIXTURE_HOME/.claude/settings.json"
}

create_pi_fixture() {
    mkdir -p "$FIXTURE_HOME/.pi/agent"
    echo '{}' > "$FIXTURE_HOME/.pi/agent/settings.json"
}

# Preset: "full" fixture with all agents (for coverage tests)
create_full_fixture() {
    create_claude_fixture
    create_codex_fixture
    create_opencode_fixture
    # ... etc
}

# Preset: "minimal" fixture with only Claude (for most tests)
create_minimal_fixture() {
    create_claude_fixture
}
```

### Container Management (Reuse existing patterns)
```bash
# Reuse helpers from test-sync-integration.sh:
# - Docker context selection (DinD vs host)
# - Safe cleanup with labels
# - Hermetic HOME/DOCKER_CONFIG preservation

start_test_container() {
    local name="${1:-test-sync-$$}"
    local volume="${2:-test-sync-vol-$$}"

    # Use labels for safe cleanup
    docker run -d --name "$name" \
        --label "containai-test=true" \
        -v "$volume:/mnt/agent-data" \
        containai:latest sleep infinity
    echo "$name"
}

exec_in_container() {
    local container="$1"
    shift
    docker exec "$container" "$@"
}

cleanup_test_containers() {
    docker rm -f $(docker ps -aq --filter "label=containai-test=true") 2>/dev/null || true
    docker volume rm $(docker volume ls -q --filter "label=containai-test=true") 2>/dev/null || true
}
```

### Test Helpers
```bash
# Volume path assertions (for /mnt/agent-data)
assert_file_exists_in_volume() {
    local path="$1"  # relative to /mnt/agent-data
    exec_in_container "$CONTAINER" test -f "/mnt/agent-data/$path"
}

assert_path_not_exists_in_volume() {
    local path="$1"
    ! exec_in_container "$CONTAINER" test -e "/mnt/agent-data/$path"
}

# Container path assertions (for ~/)
assert_path_exists_in_container() {
    local path="$1"  # absolute path like /home/agent/.claude
    exec_in_container "$CONTAINER" test -e "$path"
}

assert_symlink_target() {
    local link="$1"
    local expected_target="$2"
    actual=$(exec_in_container "$CONTAINER" readlink "$link")
    [ "$actual" = "$expected_target" ]
}

assert_permissions_in_volume() {
    local path="$1"
    local expected="$2"
    actual=$(exec_in_container "$CONTAINER" stat -c '%a' "/mnt/agent-data/$path")
    [ "$actual" = "$expected" ]
}

cat_from_volume() {
    local path="$1"
    exec_in_container "$CONTAINER" cat "/mnt/agent-data/$path"
}

# Import helper with --from support
run_import() {
    # Uses cai import with appropriate flags
    # Handles --from, --dry-run, --no-secrets
    ...
}
```

## Key context

- Selective fixture creation enables testing optional entry behavior
- Reuse Docker context selection from test-sync-integration.sh
- Use labels for safe cleanup
- Volume path vs container path distinction is critical
- Trap EXIT for cleanup

## Acceptance
- [ ] test-sync-e2e.sh created with main structure
- [ ] sync-test-helpers.sh created with helper functions
- [ ] Selective fixture creation (not all dirs upfront)
- [ ] Per-agent fixture helpers (create_claude_fixture, etc.)
- [ ] Container start/stop/exec helpers work
- [ ] Volume path assertion helpers
- [ ] Container path assertion helpers
- [ ] --from import helper
- [ ] Cleanup on exit (trap with labels)
- [ ] Reuses patterns from test-sync-integration.sh

## Done summary
Created test infrastructure for sync E2E tests with two files:

**sync-test-helpers.sh (648 lines)**
- Docker context selection (DinD vs host) - reuses pattern from test-sync-integration.sh
- Hermetic fixture setup with HOME/DOCKER_CONFIG preservation
- Selective fixture creation (create_fixture_home, create_minimal_fixture, create_full_fixture)
- Per-agent fixture helpers for all 10 agents (Claude, Codex, OpenCode, Pi, Kimi, Copilot, Gemini, Aider, Continue, Cursor)
- Dev tool fixture helpers (Git, gh, shell, tmux, vim, vscode, fonts, starship, agents)
- Container management with labels (create_test_container, create_test_volume, start/stop/exec)
- Volume path assertion helpers (assert_file_exists_in_volume, assert_dir_exists_in_volume, etc.)
- Container path assertion helpers (assert_path_exists_in_container, assert_is_symlink, etc.)
- Permission and content assertions
- run_cai_import and run_cai_import_from helpers with --from support
- Cleanup on exit (trap with labels for parallel-safe cleanup)

**test-sync-e2e.sh (382 lines)**
- Main test orchestrator with --only filter support (agents, shell, flags, tools, edge)
- run_sync_test helper for fresh container per test
- Test categories: agents, tools, shell, flags, edge cases
- Example tests implemented for each category
## Evidence
- Commits:
- Tests:
- PRs:
