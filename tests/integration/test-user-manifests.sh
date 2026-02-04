#!/usr/bin/env bash
# ==============================================================================
# Integration tests for user-defined manifest support
# ==============================================================================
# Verifies:
# 1. User manifest files are synced to container volume
# 2. User manifest entries create proper data in volume
# 3. Invalid user manifests don't prevent import
#
# Note: Tests for runtime processing of user manifests (wrapper generation,
# symlink creation at startup) require Sysbox/systemd and are located in
# test-startup-hooks.sh or similar systemd-enabled test suites.
#
# Prerequisites:
#   - Docker daemon running
#   - Test image built: ./src/build.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source test helpers
source "$SCRIPT_DIR/sync-test-helpers.sh"

# ==============================================================================
# Test counters
# ==============================================================================
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
test_info "Run ID: $SYNC_TEST_RUN_ID"

# Test counter for unique volume names
TEST_COUNTER=0

# Helper: wait for container file/directory to exist
wait_for_container_path() {
    local container="$1"
    local path="$2"
    local timeout="${3:-30}"
    local count=0

    while [[ $count -lt $timeout ]]; do
        if "${DOCKER_CMD[@]}" exec "$container" test -e "$path" 2>/dev/null; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    test_info "Timeout waiting for path: $path"
    return 1
}

# Helper: wait for container to be running
wait_for_container_running() {
    local container="$1"
    local timeout="${2:-30}"
    local count=0

    while [[ $count -lt $timeout ]]; do
        if "${DOCKER_CMD[@]}" ps -q -f name="$container" | grep -q .; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    test_info "Timeout waiting for container to be running"
    return 1
}

# ==============================================================================
# Test 1: User manifest directory synced to container
# ==============================================================================
printf '\n=== Test 1: User manifest directory synced to container ===\n'

TEST_COUNTER=$((TEST_COUNTER + 1))
# Create test volume and set SYNC_TEST_DATA_VOLUME for run_cai_import_from
SYNC_TEST_DATA_VOLUME=$(create_test_volume "user-manifest-sync-${TEST_COUNTER}")

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

# Create the container using helper (uses SYNC_TEST_RUN_ID internally)
create_test_container "user-manifest-sync" \
    --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
    "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

# Derive correct container name (matches helper's naming)
test_container_name="test-user-manifest-sync-${SYNC_TEST_RUN_ID}"

# Run import
import_exit=0
import_output=$(run_cai_import_from 2>&1) || import_exit=$?

if [[ $import_exit -ne 0 ]]; then
    test_fail "Import failed: $import_output"
else
    # Start container
    start_test_container "$test_container_name"

    # Wait for container to be ready (poll instead of fixed sleep)
    if wait_for_container_path "$test_container_name" "/mnt/agent-data" 10; then

        # Verify user manifest was synced to volume
        SYNC_TEST_CONTAINER="$test_container_name"
        if assert_file_exists_in_volume "containai/manifests/99-custom.toml"; then
            test_pass "User manifest synced to /mnt/agent-data/containai/manifests/"
        else
            test_fail "User manifest not found in container volume"
        fi

        # Verify symlink exists in container
        if exec_in_container "$test_container_name" test -L /home/agent/.config/containai/manifests 2>/dev/null; then
            test_pass "User manifest symlink created in container home"
        else
            test_info "User manifest path may be a directory (symlink not found)"
        fi
    else
        test_fail "Container did not become ready"
    fi
fi

# Cleanup test 1
stop_test_container "$test_container_name"
"${DOCKER_CMD[@]}" rm -f "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true

# ==============================================================================
# Test 2: Invalid user manifest doesn't prevent import
# ==============================================================================
printf '\n=== Test 2: Invalid user manifest does not prevent import ===\n'

TEST_COUNTER=$((TEST_COUNTER + 1))
SYNC_TEST_DATA_VOLUME=$(create_test_volume "user-manifest-invalid-${TEST_COUNTER}")

# Create invalid user manifest (malformed TOML)
mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests"
cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests/99-broken.toml" << 'EOF'
# This is intentionally broken TOML
[agent
name = "broken
EOF

# Create Claude fixture (valid, should still work)
create_claude_fixture

# Create container
create_test_container "user-manifest-invalid" \
    --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
    "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

test_container_name="test-user-manifest-invalid-${SYNC_TEST_RUN_ID}"

# Run import - user manifests are just files, sync should succeed
# The validation happens at runtime, not during import
import_exit=0
import_output=$(run_cai_import_from 2>&1) || import_exit=$?

if [[ $import_exit -eq 0 ]]; then
    test_pass "Import succeeded with invalid user manifest file"

    # Start container
    start_test_container "$test_container_name"

    # Wait for container to be ready
    if wait_for_container_running "$test_container_name" 10; then
        test_pass "Container started successfully"

        # Verify Claude data was still synced (invalid manifest shouldn't break valid data)
        SYNC_TEST_CONTAINER="$test_container_name"
        if assert_file_exists_in_volume "claude/settings.json"; then
            test_pass "Valid agent data synced despite invalid user manifest"
        else
            test_fail "Valid agent data was not synced"
        fi
    else
        test_fail "Container failed to start"
    fi
else
    test_fail "Import failed unexpectedly: $import_output"
fi

# Cleanup test 2
stop_test_container "$test_container_name"
"${DOCKER_CMD[@]}" rm -f "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true

# ==============================================================================
# Test 3: User manifest entries sync custom data
# ==============================================================================
printf '\n=== Test 3: User manifest entries sync custom data ===\n'

TEST_COUNTER=$((TEST_COUNTER + 1))
SYNC_TEST_DATA_VOLUME=$(create_test_volume "user-manifest-data-${TEST_COUNTER}")

# Create user manifest with entry for custom config
mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests"
cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/manifests/99-userconfig.toml" << 'EOF'
# User config entry (entries only, no agent section)
[[entries]]
source = ".myconfig/settings.json"
target = "myconfig/settings.json"
container_link = ".myconfig/settings.json"
flags = "fjo"
EOF

# Create the source file
mkdir -p "$SYNC_TEST_FIXTURE_HOME/.myconfig"
printf '%s\n' '{"user": "config", "_marker": "USER_CONFIG_MARKER"}' > "$SYNC_TEST_FIXTURE_HOME/.myconfig/settings.json"

# Create Claude fixture
create_claude_fixture

# Create container
create_test_container "user-manifest-data" \
    --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
    "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

test_container_name="test-user-manifest-data-${SYNC_TEST_RUN_ID}"

# Run import
import_exit=0
import_output=$(run_cai_import_from 2>&1) || import_exit=$?

if [[ $import_exit -ne 0 ]]; then
    test_fail "Import failed: $import_output"
else
    # Start container
    start_test_container "$test_container_name"

    # Wait for container to be ready
    if wait_for_container_path "$test_container_name" "/mnt/agent-data" 10; then

        SYNC_TEST_CONTAINER="$test_container_name"

        # Check if user config was synced
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
    else
        test_fail "Container did not become ready"
    fi
fi

# Cleanup test 3
stop_test_container "$test_container_name"
"${DOCKER_CMD[@]}" rm -f "$test_container_name" 2>/dev/null || true
"${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
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
