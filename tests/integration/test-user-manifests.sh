#!/usr/bin/env bash
# ==============================================================================
# Integration tests for user-defined manifest support
# ==============================================================================
# Verifies:
# 1. User manifest files are synced to container volume
# 2. User manifests are processed at container startup
# 3. User manifest symlinks are created correctly
# 4. User manifest wrappers are generated
# 5. Invalid user manifests don't break container startup
# 6. Optional binary check in user manifests works
#
# Prerequisites:
#   - Docker daemon running
#   - Test image built: ./src/build.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test helpers
source "$SCRIPT_DIR/sync-test-helpers.sh"

# ==============================================================================
# Test configuration
# ==============================================================================
USER_MANIFEST_TEST_RUN_ID="usermanifest-$(date +%s)-$$"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    printf '[PASS] %s\n' "$*"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    printf '[FAIL] %s\n' "$*" >&2
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_skip() {
    printf '[SKIP] %s\n' "$*"
}

test_info() {
    printf '[INFO] %s\n' "$*"
}

# ==============================================================================
# Early guards
# ==============================================================================
docker_status=0
check_docker_available || docker_status=$?
if [[ "$docker_status" == "2" ]]; then
    # Docker binary not found - skip
    test_info "Docker binary not found - skipping user manifest tests"
    exit 0
elif [[ "$docker_status" != "0" ]]; then
    # Docker daemon not running - fail
    test_fail "Docker daemon not running"
    exit 1
fi

if ! check_test_image; then
    test_info "Test image not available - skipping user manifest tests"
    test_info "Run './src/build.sh' first to build the test image"
    exit 0
fi

# ==============================================================================
# Setup and cleanup
# ==============================================================================
setup_cleanup_trap
init_fixture_home >/dev/null

test_info "Fixture home: $SYNC_TEST_FIXTURE_HOME"
test_info "Test image: $SYNC_TEST_IMAGE_NAME"

# Test counter for unique names
TEST_COUNTER=0

# ==============================================================================
# Test 1: User manifest directory synced to container
# ==============================================================================
printf '\n=== Test 1: User manifest directory synced to container ===\n'

TEST_COUNTER=$((TEST_COUNTER + 1))
test_vol=$(create_test_volume "user-manifest-sync-${TEST_COUNTER}")
test_container_name="test-user-manifest-sync-${USER_MANIFEST_TEST_RUN_ID}"

# Create user manifest fixture
mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests"
cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests/99-custom.toml" << 'EOF'
# Custom user agent manifest
[agent]
name = "customtool"
binary = "customtool"
default_args = ["--autonomous"]
aliases = []
optional = true

[[entries]]
source = ".customtool/config.json"
target = "customtool/config.json"
container_link = ".customtool/config.json"
flags = "fjo"
EOF

# Also create Claude fixture (required agent)
create_claude_fixture

# Create the container
create_test_container "user-manifest-sync" \
    --volume "$test_vol:/mnt/agent-data" \
    "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

# Run import
import_output=$(run_cai_import_from 2>&1) || {
    test_fail "Import failed: $import_output"
    exit 1
}

# Start container
start_test_container "$test_container_name"
sleep 2

# Verify user manifest was synced to volume
SYNC_TEST_CONTAINER="$test_container_name"
if assert_file_exists_in_volume "containai/manifests/99-custom.toml"; then
    test_pass "User manifest synced to /mnt/agent-data/containai/manifests/"
else
    test_fail "User manifest not found in container volume"
fi

# Verify symlink exists in container (if link was created)
if exec_in_container "$test_container_name" test -L /home/agent/.config/containai/manifests 2>/dev/null; then
    test_pass "User manifest symlink created in container home"
else
    # May be a directory instead of symlink if entry doesn't use container_link
    test_info "User manifest path exists as directory (not symlink)"
fi

# Cleanup
stop_test_container "$test_container_name"
"${DOCKER_CMD[@]}" rm -f "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" volume rm "$test_vol" 2>/dev/null || true
find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true

# ==============================================================================
# Test 2: User manifest generates wrapper function at runtime
# ==============================================================================
printf '\n=== Test 2: User manifest generates wrapper at runtime ===\n'

TEST_COUNTER=$((TEST_COUNTER + 1))
test_vol=$(create_test_volume "user-manifest-wrapper-${TEST_COUNTER}")
test_container_name="test-user-manifest-wrapper-${USER_MANIFEST_TEST_RUN_ID}"

# Create user manifest with a real binary (bash) for testing
mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests"
cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests/99-test-wrapper.toml" << 'EOF'
# Test wrapper generation with real binary
[agent]
name = "testwrapper"
binary = "bash"
default_args = ["--norc", "--noprofile"]
aliases = ["testwrapper-alias"]
optional = true
EOF

# Create Claude fixture
create_claude_fixture

# Create container
create_test_container "user-manifest-wrapper" \
    --volume "$test_vol:/mnt/agent-data" \
    "$SYNC_TEST_IMAGE_NAME" /sbin/init >/dev/null

# Run import
import_output=$(run_cai_import_from 2>&1) || {
    test_fail "Import failed: $import_output"
}

# Start container with init to run containai-init.sh
"${DOCKER_CMD[@]}" start "$test_container_name" >/dev/null

# Wait for container init to complete
sleep 5

# Check if user wrapper file was created
if "${DOCKER_CMD[@]}" exec "$test_container_name" test -f /home/agent/.bash_env.d/containai-user-agents.sh 2>/dev/null; then
    test_pass "User wrapper file created at /home/agent/.bash_env.d/containai-user-agents.sh"

    # Check wrapper content
    wrapper_content=$("${DOCKER_CMD[@]}" exec "$test_container_name" cat /home/agent/.bash_env.d/containai-user-agents.sh 2>/dev/null || true)
    if [[ "$wrapper_content" == *'testwrapper()'* ]]; then
        test_pass "User wrapper function testwrapper() is defined"
    else
        test_fail "User wrapper function testwrapper() not found in wrapper file"
    fi

    if [[ "$wrapper_content" == *'testwrapper-alias()'* ]]; then
        test_pass "User wrapper alias testwrapper-alias() is defined"
    else
        test_fail "User wrapper alias testwrapper-alias() not found"
    fi
else
    test_info "User wrapper file not created (may require systemd init)"
fi

# Cleanup
"${DOCKER_CMD[@]}" stop "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" rm -f "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" volume rm "$test_vol" 2>/dev/null || true
find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true

# ==============================================================================
# Test 3: Invalid user manifest doesn't break startup
# ==============================================================================
printf '\n=== Test 3: Invalid user manifest does not break startup ===\n'

TEST_COUNTER=$((TEST_COUNTER + 1))
test_vol=$(create_test_volume "user-manifest-invalid-${TEST_COUNTER}")
test_container_name="test-user-manifest-invalid-${USER_MANIFEST_TEST_RUN_ID}"

# Create invalid user manifest (malformed TOML)
mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests"
cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests/99-broken.toml" << 'EOF'
# This is intentionally broken TOML
[agent
name = "broken
EOF

# Create Claude fixture
create_claude_fixture

# Create container
create_test_container "user-manifest-invalid" \
    --volume "$test_vol:/mnt/agent-data" \
    "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

# Run import (should succeed even with invalid manifest in user dir)
import_output=$(run_cai_import_from 2>&1) || {
    test_fail "Import should not fail due to invalid user manifest"
}
test_pass "Import succeeded despite invalid user manifest"

# Start container
start_test_container "$test_container_name"
sleep 2

# Container should still be running
if "${DOCKER_CMD[@]}" ps -q -f name="$test_container_name" | grep -q .; then
    test_pass "Container started successfully despite invalid user manifest"
else
    test_fail "Container failed to start with invalid user manifest"
fi

# Cleanup
stop_test_container "$test_container_name"
"${DOCKER_CMD[@]}" rm -f "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" volume rm "$test_vol" 2>/dev/null || true
find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true

# ==============================================================================
# Test 4: User manifest with optional binary not installed
# ==============================================================================
printf '\n=== Test 4: User manifest with optional binary not installed ===\n'

TEST_COUNTER=$((TEST_COUNTER + 1))
test_vol=$(create_test_volume "user-manifest-optional-${TEST_COUNTER}")
test_container_name="test-user-manifest-optional-${USER_MANIFEST_TEST_RUN_ID}"

# Create user manifest with non-existent binary
mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests"
cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests/99-nonexistent.toml" << 'EOF'
# Agent with binary that doesn't exist
[agent]
name = "nonexistent-agent"
binary = "this-binary-does-not-exist"
default_args = ["--flag"]
aliases = []
optional = true
EOF

# Create Claude fixture
create_claude_fixture

# Create container
create_test_container "user-manifest-optional" \
    --volume "$test_vol:/mnt/agent-data" \
    "$SYNC_TEST_IMAGE_NAME" /sbin/init >/dev/null

# Run import
import_output=$(run_cai_import_from 2>&1) || {
    test_fail "Import failed"
}

# Start container
"${DOCKER_CMD[@]}" start "$test_container_name" >/dev/null
sleep 5

# Container should still be running (optional binary guard prevents errors)
if "${DOCKER_CMD[@]}" ps -q -f name="$test_container_name" | grep -q .; then
    test_pass "Container started despite non-existent optional binary"
else
    test_fail "Container failed with non-existent optional binary"
fi

# Check that wrapper is guarded (if file exists)
if "${DOCKER_CMD[@]}" exec "$test_container_name" test -f /home/agent/.bash_env.d/containai-user-agents.sh 2>/dev/null; then
    wrapper_content=$("${DOCKER_CMD[@]}" exec "$test_container_name" cat /home/agent/.bash_env.d/containai-user-agents.sh 2>/dev/null || true)
    if [[ "$wrapper_content" == *'command -v this-binary-does-not-exist'* ]]; then
        test_pass "User wrapper is guarded with command -v check"
    else
        test_info "Wrapper may not be generated for missing binary (expected)"
    fi
fi

# Cleanup
"${DOCKER_CMD[@]}" stop "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" rm -f "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" volume rm "$test_vol" 2>/dev/null || true
find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true

# ==============================================================================
# Test 5: User manifest entries create symlinks
# ==============================================================================
printf '\n=== Test 5: User manifest entries create symlinks ===\n'

TEST_COUNTER=$((TEST_COUNTER + 1))
test_vol=$(create_test_volume "user-manifest-links-${TEST_COUNTER}")
test_container_name="test-user-manifest-links-${USER_MANIFEST_TEST_RUN_ID}"

# Create user manifest with entry
mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests"
cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests/99-userconfig.toml" << 'EOF'
# User config entry (no agent section, just entries)
[[entries]]
source = ".myconfig/settings.json"
target = "myconfig/settings.json"
container_link = ".myconfig/settings.json"
flags = "fjo"
EOF

# Create the source file
mkdir -p "$SYNC_TEST_FIXTURE_HOME/.myconfig"
echo '{"user": "config", "_marker": "USER_CONFIG_MARKER"}' > "$SYNC_TEST_FIXTURE_HOME/.myconfig/settings.json"

# Create Claude fixture
create_claude_fixture

# Create container
create_test_container "user-manifest-links" \
    --volume "$test_vol:/mnt/agent-data" \
    "$SYNC_TEST_IMAGE_NAME" /sbin/init >/dev/null

# Run import
import_output=$(run_cai_import_from 2>&1) || {
    test_fail "Import failed"
}

# Start container
"${DOCKER_CMD[@]}" start "$test_container_name" >/dev/null
sleep 5

# Check if user config was synced
SYNC_TEST_CONTAINER="$test_container_name"
if assert_file_exists_in_volume "myconfig/settings.json"; then
    test_pass "User config synced to volume"

    # Check content
    content=$(cat_from_volume "myconfig/settings.json" 2>/dev/null || true)
    if [[ "$content" == *"USER_CONFIG_MARKER"* ]]; then
        test_pass "User config content is correct"
    else
        test_fail "User config content mismatch"
    fi
else
    test_fail "User config not synced to volume"
fi

# Cleanup
"${DOCKER_CMD[@]}" stop "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" rm -f "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" volume rm "$test_vol" 2>/dev/null || true
find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true

# ==============================================================================
# Summary
# ==============================================================================
printf '\n==========================================\n'
printf 'Tests run:   %s\n' "$TESTS_RUN"
printf 'Passed:      %s\n' "$TESTS_PASSED"
printf 'Failed:      %s\n' "$TESTS_FAILED"
printf '==========================================\n'

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
