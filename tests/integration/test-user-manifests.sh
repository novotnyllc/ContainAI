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
# test-startup-hooks.sh (Test 6: User manifest runtime processing).
# That test verifies: wrapper generation, alias functions, symlink creation,
# and containai-init log output for user manifest processing.
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

# Helper: probe volume contents without starting systemd containers.
# Use a small non-systemd image to inspect the data volume.
VOLUME_PROBE_IMAGE="${CONTAINAI_VOLUME_PROBE_IMAGE:-alpine:3.20}"

ensure_probe_image() {
    if ! "${DOCKER_CMD[@]}" image inspect "$VOLUME_PROBE_IMAGE" >/dev/null 2>&1; then
        test_info "Pulling volume probe image: $VOLUME_PROBE_IMAGE"
        "${DOCKER_CMD[@]}" pull "$VOLUME_PROBE_IMAGE" >/dev/null
    fi
}

volume_exec() {
    local cmd="$1"
    "${DOCKER_CMD[@]}" run --rm \
        -v "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$VOLUME_PROBE_IMAGE" /bin/sh -c "$cmd"
}

volume_path_exists() {
    local path="$1"
    volume_exec "test -e \"/mnt/agent-data/$path\""
}

volume_cat() {
    local path="$1"
    volume_exec "cat \"/mnt/agent-data/$path\""
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

# Run import
import_exit=0
import_output=$(run_cai_import_from 2>&1) || import_exit=$?

if [[ $import_exit -ne 0 ]]; then
    test_fail "Import failed: $import_output"
else
    ensure_probe_image

    # Verify user manifest was synced to volume (no system container required)
    if volume_path_exists "containai/manifests/99-custom.toml"; then
        test_pass "User manifest synced to /mnt/agent-data/containai/manifests/"
    else
        test_fail "User manifest not found in volume"
    fi
fi

# Cleanup test 1
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

# Run import - user manifests are just files, sync should succeed
# The validation happens at runtime, not during import
import_exit=0
import_output=$(run_cai_import_from 2>&1) || import_exit=$?

if [[ $import_exit -eq 0 ]]; then
    test_pass "Import succeeded with invalid user manifest file"

    ensure_probe_image

    # Verify Claude data was still synced (invalid manifest shouldn't break valid data)
    if volume_path_exists "claude/settings.json"; then
        test_pass "Valid agent data synced despite invalid user manifest"
    else
        test_fail "Valid agent data was not synced"
    fi
else
    test_fail "Import failed unexpectedly: $import_output"
fi

# Cleanup test 2
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

# Run import
import_exit=0
import_output=$(run_cai_import_from 2>&1) || import_exit=$?

if [[ $import_exit -ne 0 ]]; then
    test_fail "Import failed: $import_output"
else
    ensure_probe_image

    # Check if user config was synced
    if volume_path_exists "myconfig/settings.json"; then
        test_pass "User config synced to volume"

        # Check content
        content=$(volume_cat "myconfig/settings.json" 2>/dev/null || true)
        if [[ "$content" == *"USER_CONFIG_MARKER"* ]]; then
            test_pass "User config content is correct"
        else
            test_fail "User config content mismatch"
        fi
    else
        test_fail "User config not synced to volume"
    fi
fi

# Cleanup test 3
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
