# fn-4-vet.6 Update integration tests for configurable volumes

## Description
## Overview
Update `test-sync-integration.sh` to use **isolated test volumes by default** and add tests for workspace path-based volume selection.

## Implementation

### Isolated Test Volumes
```bash
TEST_RUN_ID="test-$(date +%s)-$$"
TEST_DATA_VOLUME="containai-test-${TEST_RUN_ID}"

cleanup_test_volumes() {
    docker volume rm "$TEST_DATA_VOLUME" 2>/dev/null || true
    docker volume ls --filter "name=containai-test-" -q | xargs -r docker volume rm 2>/dev/null || true
}
trap cleanup_test_volumes EXIT
```

### New Test Cases

```bash
test_custom_volume_flag() {
    step "Testing --volume flag for sync-agent"
    local test_vol="test-flag-vol-$$"
    ./sync-agent-plugins.sh --volume "$test_vol" --dry-run 2>&1 | grep -q "$test_vol"
    pass "sync-agent respects --volume flag"
}

test_env_var_volume() {
    step "Testing CONTAINAI_DATA_VOLUME environment variable"
    local test_vol="test-env-vol-$$"
    CONTAINAI_DATA_VOLUME="$test_vol" ./sync-agent-plugins.sh --dry-run 2>&1 | grep -q "$test_vol"
    pass "sync-agent respects CONTAINAI_DATA_VOLUME"
}

test_workspace_path_matching() {
    step "Testing workspace path-based config matching"
    local test_dir="/tmp/test-workspace-match-$$"
    local test_vol="test-ws-vol-$$"
    
    mkdir -p "$test_dir/subproject/.containai"
    cat > "$test_dir/subproject/.containai/config.toml" << EOF
[agent]
data_volume = "default-vol"

[workspace."./"]
data_volume = "$test_vol"
EOF
    
    (cd "$test_dir/subproject" && source "$ORIG_DIR/aliases.sh" && \
     [[ "$(_containai_resolve_volume "" "$test_dir/subproject")" == "$test_vol" ]])
    pass "Workspace path matching works"
    rm -rf "$test_dir"
}

test_workspace_fallback_to_agent() {
    step "Testing fallback to [agent] when no workspace match"
    local test_dir="/tmp/test-fallback-$$"
    local default_vol="fallback-vol-$$"
    
    mkdir -p "$test_dir/.containai"
    cat > "$test_dir/.containai/config.toml" << EOF
[agent]
data_volume = "$default_vol"

[workspace."/some/other/path"]
data_volume = "other-vol"
EOF
    
    (cd "$test_dir" && source "$ORIG_DIR/aliases.sh" && \
     [[ "$(_containai_resolve_volume "" "$test_dir")" == "$default_vol" ]])
    pass "Falls back to [agent] when no workspace match"
    rm -rf "$test_dir"
}

test_longest_match_wins() {
    step "Testing longest workspace path match wins"
    local test_dir="/tmp/test-longest-$$"
    
    mkdir -p "$test_dir/project/subdir/.containai"
    cat > "$test_dir/project/subdir/.containai/config.toml" << EOF
[agent]
data_volume = "default"

[workspace."/tmp/test-longest-$$/project"]
data_volume = "project-vol"

[workspace."/tmp/test-longest-$$/project/subdir"]
data_volume = "subdir-vol"
EOF
    
    (cd "$test_dir/project/subdir" && source "$ORIG_DIR/aliases.sh" && \
     [[ "$(_containai_resolve_volume "" "$test_dir/project/subdir")" == "subdir-vol" ]])
    pass "Longest workspace path match wins"
    rm -rf "$test_dir"
}

test_data_volume_overrides_config() {
    step "Testing --data-volume overrides workspace config"
    local test_dir="/tmp/test-override-$$"
    
    mkdir -p "$test_dir/.containai"
    echo '[workspace."./"]
data_volume = "config-vol"' > "$test_dir/.containai/config.toml"
    
    (cd "$test_dir" && source "$ORIG_DIR/aliases.sh" && \
     [[ "$(_containai_resolve_volume "cli-vol")" == "cli-vol" ]])
    pass "--data-volume overrides workspace config"
    rm -rf "$test_dir"
}
```

## Key Files
- Modify: `agent-sandbox/test-sync-integration.sh` (isolated volumes, new tests)
## Overview
Update `test-sync-integration.sh` to use **isolated test volumes by default** to prevent clobbering user data. Add tests for configurable volume functionality including --workspace config discovery.

## Implementation

### Critical Change: Isolated Test Volumes
Tests MUST NOT use `sandbox-agent-data` by default:

```bash
TEST_RUN_ID="test-$(date +%s)-$$"
TEST_DATA_VOLUME="containai-test-${TEST_RUN_ID}"

cleanup_test_volumes() {
    docker volume rm "$TEST_DATA_VOLUME" 2>/dev/null || true
    docker volume ls --filter "name=containai-test-" -q | xargs -r docker volume rm 2>/dev/null || true
}
trap cleanup_test_volumes EXIT
```

### New Test Cases

```bash
test_custom_volume_flag() {
    step "Testing --volume flag for sync-agent"
    local test_vol="test-flag-vol-$$"
    ./sync-agent-plugins.sh --volume "$test_vol" --dry-run 2>&1 | grep -q "$test_vol"
    pass "sync-agent respects --volume flag"
}

test_env_var_volume() {
    step "Testing CONTAINAI_DATA_VOLUME environment variable"
    local test_vol="test-env-vol-$$"
    CONTAINAI_DATA_VOLUME="$test_vol" ./sync-agent-plugins.sh --dry-run 2>&1 | grep -q "$test_vol"
    pass "sync-agent respects CONTAINAI_DATA_VOLUME"
}

test_config_file_volume() {
    step "Testing config file discovery"
    local test_dir="/tmp/test-containai-config-$$"
    local test_vol="test-config-vol-$$"
    mkdir -p "$test_dir/.containai"
    echo "[agent]
data_volume = \"$test_vol\"" > "$test_dir/.containai/config.toml"
    
    (cd "$test_dir" && source "$ORIG_DIR/aliases.sh" && \
     [[ "$(_containai_resolve_volume)" == "$test_vol" ]])
    pass "Config file discovery works"
    rm -rf "$test_dir"
}

test_workspace_config_discovery() {
    step "Testing --workspace affects config discovery"
    local test_dir="/tmp/test-workspace-$$"
    local test_vol="test-workspace-vol-$$"
    mkdir -p "$test_dir/.containai"
    echo "[agent]
data_volume = \"$test_vol\"" > "$test_dir/.containai/config.toml"
    
    # Run from different directory but with --workspace pointing to test_dir
    source "$ORIG_DIR/aliases.sh"
    local resolved
    resolved=$(_containai_resolve_volume "" "" "$test_dir")
    [[ "$resolved" == "$test_vol" ]]
    pass "--workspace config discovery works"
    rm -rf "$test_dir"
}

test_profile_selection() {
    step "Testing --profile flag"
    local test_dir="/tmp/test-profile-$$"
    mkdir -p "$test_dir/.containai"
    echo "[agent]
data_volume = \"default-vol\"
[profile.testing]
data_volume = \"test-profile-vol\"" > "$test_dir/.containai/config.toml"
    
    (cd "$test_dir" && source "$ORIG_DIR/aliases.sh" && \
     [[ "$(_containai_resolve_volume "" "testing")" == "test-profile-vol" ]])
    pass "Profile selection works"
    rm -rf "$test_dir"
}

test_data_volume_overrides_config() {
    step "Testing --data-volume overrides config file"
    local test_dir="/tmp/test-override-$$"
    mkdir -p "$test_dir/.containai"
    echo "[agent]
data_volume = \"config-vol\"" > "$test_dir/.containai/config.toml"
    
    (cd "$test_dir" && source "$ORIG_DIR/aliases.sh" && \
     [[ "$(_containai_resolve_volume "cli-vol")" == "cli-vol" ]])
    pass "--data-volume overrides config"
    rm -rf "$test_dir"
}
```

## Key Files
- Modify: `agent-sandbox/test-sync-integration.sh:20` (unique volume name)
- Modify: `agent-sandbox/test-sync-integration.sh` (add cleanup trap)
- Modify: `agent-sandbox/test-sync-integration.sh` (add new test functions)
## Overview
Update `test-sync-integration.sh` to use **isolated test volumes by default** to prevent clobbering user data. Add tests for configurable volume functionality.

## Implementation

### Critical Change: Isolated Test Volumes
Tests MUST NOT use `sandbox-agent-data` by default. Use unique temporary volume names:

```bash
# At top of test file
TEST_RUN_ID="test-$(date +%s)-$$"
TEST_DATA_VOLUME="containai-test-${TEST_RUN_ID}"

# Cleanup function
cleanup_test_volumes() {
    docker volume rm "$TEST_DATA_VOLUME" 2>/dev/null || true
    # Also clean any volumes created by individual tests
    docker volume ls --filter "name=containai-test-" -q | xargs -r docker volume rm 2>/dev/null || true
}
trap cleanup_test_volumes EXIT
```

### Current Code (line 20)
```bash
DATA_VOLUME="sandbox-agent-data"
```

### New Approach
1. Default to unique test volume name
2. Accept `--volume` flag to override (for testing specific volume scenarios)
3. Add `--use-default-volume` flag to explicitly opt-in to testing with `sandbox-agent-data`
4. Cleanup test volumes on exit

### New Test Cases
```bash
test_custom_volume_flag() {
    step "Testing --volume flag for sync-agent"
    local test_vol="test-flag-vol-$$"
    ./sync-agent-plugins.sh --volume "$test_vol" --dry-run 2>&1 | grep -q "$test_vol"
    pass "sync-agent respects --volume flag"
    docker volume rm "$test_vol" 2>/dev/null || true
}

test_env_var_volume() {
    step "Testing CONTAINAI_DATA_VOLUME environment variable"
    local test_vol="test-env-vol-$$"
    CONTAINAI_DATA_VOLUME="$test_vol" ./sync-agent-plugins.sh --dry-run 2>&1 | grep -q "$test_vol"
    pass "sync-agent respects CONTAINAI_DATA_VOLUME"
}

test_config_file_volume() {
    step "Testing config file discovery"
    local test_dir="/tmp/test-containai-$$"
    local test_vol="test-config-vol-$$"
    mkdir -p "$test_dir/.containai"
    echo "[agent]
data_volume = \"$test_vol\"" > "$test_dir/.containai/config.toml"
    
    (cd "$test_dir" && source "$ORIG_DIR/aliases.sh" && \
     [[ "$(_containai_resolve_volume)" == "$test_vol" ]])
    pass "Config file discovery works"
    
    rm -rf "$test_dir"
}

test_profile_selection() {
    step "Testing --profile flag"
    local test_dir="/tmp/test-profile-$$"
    mkdir -p "$test_dir/.containai"
    echo "[agent]
data_volume = \"default-vol\"
[profile.testing]
data_volume = \"test-profile-vol\"" > "$test_dir/.containai/config.toml"
    
    (cd "$test_dir" && source "$ORIG_DIR/aliases.sh" && \
     [[ "$(_containai_resolve_volume "" "testing")" == "test-profile-vol" ]])
    pass "Profile selection works"
    
    rm -rf "$test_dir"
}

test_python_optional() {
    step "Testing graceful fallback without Python"
    # This test verifies warning is shown but doesn't fail
    # Actual test depends on environment
    pass "Python optional handling (manual verification needed)"
}
```

## Key Files
- Modify: `agent-sandbox/test-sync-integration.sh:20` (change DATA_VOLUME to unique)
- Modify: `agent-sandbox/test-sync-integration.sh` (add cleanup trap)
- Modify: `agent-sandbox/test-sync-integration.sh` (add new test functions)
## Overview
Update `test-sync-integration.sh` to test both default and custom volume configurations. Ensure tests can run with isolated volumes to avoid interference.

## Implementation

### Current Code (line 20)
```bash
DATA_VOLUME="sandbox-agent-data"
```

### New Approach
1. Accept `--volume` flag for test runs
2. Default to a test-specific volume name to avoid production interference
3. Add tests for config loading behavior

### New Test Cases
```bash
test_custom_volume_flag() {
    # Test that --volume flag is respected
    ./sync-agent-plugins.sh --volume test-custom-vol --dry-run
    # Verify output mentions test-custom-vol
}

test_env_var_volume() {
    # Test that CONTAINAI_VOLUME env var works
    CONTAINAI_VOLUME=test-env-vol ./sync-agent-plugins.sh --dry-run
    # Verify output mentions test-env-vol
}

test_config_file_volume() {
    # Test config file discovery
    mkdir -p /tmp/test-containai/.containai
    echo '[agent]
volume = "test-config-vol"' > /tmp/test-containai/.containai/config.toml
    cd /tmp/test-containai
    source "$ORIG_DIR/aliases.sh"
    # Verify $_CONTAINAI_VOLUME equals test-config-vol
}
```

### Test Volume Cleanup
Add cleanup function to remove test volumes after test run.

## Key Files
- Modify: `agent-sandbox/test-sync-integration.sh:20` (DATA_VOLUME)
- Modify: `agent-sandbox/test-sync-integration.sh` (add new test functions)
## Acceptance
- [ ] Tests use unique isolated volume names by default
- [ ] `cleanup_test_volumes()` removes test volumes on exit
- [ ] `test_custom_volume_flag()` passes
- [ ] `test_env_var_volume()` passes
- [ ] `test_workspace_path_matching()` passes
- [ ] `test_workspace_fallback_to_agent()` passes
- [ ] `test_longest_match_wins()` passes
- [ ] `test_data_volume_overrides_config()` passes
- [ ] No test volumes left behind after run
- [ ] `./test-sync-integration.sh` completes successfully
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
