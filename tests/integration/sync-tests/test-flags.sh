#!/usr/bin/env bash
# ==============================================================================
# Flag and Operation Tests
# ==============================================================================
# Tests manifest flag behaviors and CLI operations: s, j, R, x, o flags,
# --no-secrets, --dry-run, import AND export operations.
#
# Key test points:
# - s flag: 600 file permissions verified
# - j flag: {} created for non-optional fj entries
# - j flag: optional fjo entries NOT created when missing
# - R flag: symlink replaces conflicting directory via link-repair
# - x flag: .system/ excluded from Codex/Pi skills
# - o flag: missing optional = no target
# - cai import --dry-run: [DRY-RUN] output, no volume changes
# - cai import --no-secrets: s-flagged entries skipped entirely
# - cai export creates .tgz archive
# - cai export with config excludes works
# - cai export --no-excludes skips excludes
#
# Usage:
#   ./tests/integration/sync-tests/test-flags.sh
#
# Prerequisites:
#   - Docker daemon running
#   - Test image built: ./src/build.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make tests hermetic: clear config discovery inputs to prevent developer's
# real config (e.g., ~/.config/containai/containai.toml) from affecting tests.
unset XDG_CONFIG_HOME 2>/dev/null || true

# Source test helpers
source "$SCRIPT_DIR/../sync-test-helpers.sh"

# ==============================================================================
# Early Guards
# ==============================================================================
docker_status=0
check_docker_available || docker_status=$?
if [[ "$docker_status" == "2" ]]; then
    exit 0
elif [[ "$docker_status" != "0" ]]; then
    exit 1
fi

if ! check_test_image; then
    exit 1
fi

# ==============================================================================
# Test Setup
# ==============================================================================
setup_cleanup_trap

init_fixture_home >/dev/null

sync_test_info "Fixture home: $SYNC_TEST_FIXTURE_HOME"
sync_test_info "Test image: $SYNC_TEST_IMAGE_NAME"

# Test counter for unique volume names
SYNC_TEST_COUNTER=0

# ==============================================================================
# Helper to run a test with a fresh container and volume
# ==============================================================================
# Each test gets its own fresh volume for isolation
# Usage: run_flags_test NAME SETUP_FN TEST_FN [extra_import_args...]
run_flags_test() {
    local test_name="$1"
    local setup_fn="$2"
    local test_fn="$3"
    shift 3

    local extra_import_args=()
    while [[ $# -gt 0 ]]; do
        extra_import_args+=("$1")
        shift
    done

    local import_output import_exit=0

    # Create fresh volume for this test (isolation)
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "flags-data-${SYNC_TEST_COUNTER}")

    # Create unique container for this test (use tail -f for portable keepalive)
    create_test_container "$test_name" \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

    # Set up fixture
    if [[ -n "$setup_fn" ]]; then
        "$setup_fn"
    fi

    # Run import and capture output/exit code
    if [[ ${#extra_import_args[@]} -gt 0 ]]; then
        import_output=$(run_cai_import_from "${extra_import_args[@]}") || import_exit=$?
    else
        import_output=$(run_cai_import_from) || import_exit=$?
    fi
    if [[ $import_exit -ne 0 ]]; then
        sync_test_fail "$test_name: import failed (exit=$import_exit)"
        printf '%s\n' "$import_output" | head -20 >&2
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        # Clean up this test's container and volume
        "${DOCKER_CMD[@]}" rm -f "test-${test_name}-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        return
    fi

    # Start container
    start_test_container "test-${test_name}-${SYNC_TEST_RUN_ID}"

    # Set current container for assertions
    SYNC_TEST_CONTAINER="test-${test_name}-${SYNC_TEST_RUN_ID}"

    # Run test
    if "$test_fn"; then
        sync_test_pass "$test_name"
    else
        sync_test_fail "$test_name"
    fi

    # Stop container
    stop_test_container "test-${test_name}-${SYNC_TEST_RUN_ID}"

    # Clean up this test's volume (for isolation)
    "${DOCKER_CMD[@]}" rm -f "test-${test_name}-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
    "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true

    # Clear fixture for next test
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# Test 1: s Flag (Secret File Permissions) - 600 for files
# ==============================================================================
# The s flag sets 600 permissions on secret files.

setup_secret_file_permissions_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.claude"
    mkdir -p "$fixture/.codex"

    # Create secret files (s flag entries from manifest)
    printf '%s\n' '{"token": "secret"}' >"$fixture/.claude/.credentials.json"
    printf '%s\n' '{"auth": "token"}' >"$fixture/.codex/auth.json"
}

test_secret_file_permissions_assertions() {
    # claude/credentials.json should have 600 permissions
    assert_file_exists_in_volume "claude/credentials.json" || {
        printf '%s\n' "[DEBUG] claude/credentials.json not found in volume" >&2
        return 1
    }
    assert_permissions_in_volume "claude/credentials.json" "600" || {
        local actual
        actual=$(exec_in_container "$SYNC_TEST_CONTAINER" stat -c '%a' "/mnt/agent-data/claude/credentials.json")
        printf '%s\n' "[DEBUG] claude/credentials.json permissions='$actual', expected='600'" >&2
        return 1
    }

    # codex/auth.json should have 600 permissions
    assert_file_exists_in_volume "codex/auth.json" || {
        printf '%s\n' "[DEBUG] codex/auth.json not found in volume" >&2
        return 1
    }
    assert_permissions_in_volume "codex/auth.json" "600" || {
        local actual
        actual=$(exec_in_container "$SYNC_TEST_CONTAINER" stat -c '%a' "/mnt/agent-data/codex/auth.json")
        printf '%s\n' "[DEBUG] codex/auth.json permissions='$actual', expected='600'" >&2
        return 1
    }

    return 0
}

# ==============================================================================
# Test 2: j Flag (JSON Init) - {} created for non-optional fj entries
# ==============================================================================
# The j flag creates {} for empty/missing files, but only for non-optional entries.

setup_json_init_non_optional_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    # Create .claude dir but NOT settings.json
    # .claude/settings.json is fj (non-optional) in the manifest
    mkdir -p "$fixture/.claude"
}

test_json_init_non_optional_assertions() {
    # settings.json should be created with {} because fj (not optional)
    assert_file_exists_in_volume "claude/settings.json" || {
        printf '%s\n' "[DEBUG] claude/settings.json should be created for fj entry" >&2
        return 1
    }

    local content
    content=$(cat_from_volume "claude/settings.json") || return 1
    if [[ "$content" != "{}" ]]; then
        printf '%s\n' "[DEBUG] claude/settings.json content='$content', expected='{}'" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 3: j Flag (JSON Init) - optional fjo entries NOT created when missing
# ==============================================================================
# Optional entries with j flag should NOT be created if source is missing.

setup_json_init_optional_skipped_fixture() {
    # Don't create any .gemini files
    # .gemini/settings.json is fjo (optional) in the manifest
    # Gemini dir should not exist at all - empty fixture is intentional
    :
}

test_json_init_optional_skipped_assertions() {
    # gemini/settings.json should NOT be created (optional entry, source missing)
    if assert_path_exists_in_volume "gemini/settings.json" 2>/dev/null; then
        printf '%s\n' "[DEBUG] gemini/settings.json should NOT exist for fjo entry with missing source" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 4: R Flag (Remove Existing Before Symlink) via link-repair
# ==============================================================================
# The R flag removes existing path before creating symlink.
# This is enforced by link-repair.sh when repairing links.

setup_R_flag_symlink_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.claude/plugins"

    # Create some content that should be synced
    printf '%s\n' '{"plugin": "test"}' >"$fixture/.claude/plugins/test.json"
}

test_R_flag_symlink_assertions() {
    # Phase 1: Verify initial sync created the symlink
    local actual_target
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.claude/plugins" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Phase 1: Failed to read initial symlink ~/.claude/plugins" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/claude/plugins" ]]; then
        printf '%s\n' "[DEBUG] Phase 1: Unexpected initial symlink target='$actual_target'" >&2
        return 1
    fi

    # Phase 2: Replace symlink with real directory containing sentinel file
    exec_in_container "$SYNC_TEST_CONTAINER" rm -f "/home/agent/.claude/plugins" 2>/dev/null || true
    exec_in_container "$SYNC_TEST_CONTAINER" mkdir -p "/home/agent/.claude/plugins" 2>/dev/null || {
        printf '%s\n' "[DEBUG] Phase 2: Failed to create real directory" >&2
        return 1
    }
    exec_in_container "$SYNC_TEST_CONTAINER" sh -c 'echo "SENTINEL_SHOULD_BE_GONE" > /home/agent/.claude/plugins/sentinel.txt' 2>/dev/null || {
        printf '%s\n' "[DEBUG] Phase 2: Failed to create sentinel file" >&2
        return 1
    }

    # Verify sentinel exists
    if ! exec_in_container "$SYNC_TEST_CONTAINER" test -f "/home/agent/.claude/plugins/sentinel.txt" 2>/dev/null; then
        printf '%s\n' "[DEBUG] Phase 2: Sentinel file not created" >&2
        return 1
    fi

    # Phase 3: Explicitly trigger link-repair.sh to simulate repair mechanism
    if ! exec_in_container "$SYNC_TEST_CONTAINER" /usr/local/lib/containai/link-repair.sh --fix --quiet 2>/dev/null; then
        printf '%s\n' "[DEBUG] Phase 3: link-repair.sh failed" >&2
        return 1
    fi

    # Phase 4: Verify R flag behavior - symlink should be restored, sentinel gone
    if ! actual_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink "/home/agent/.claude/plugins" 2>/dev/null); then
        printf '%s\n' "[DEBUG] Phase 4: ~/.claude/plugins is not a symlink after repair (R flag failed)" >&2
        return 1
    fi
    if [[ "$actual_target" != "/mnt/agent-data/claude/plugins" ]]; then
        printf '%s\n' "[DEBUG] Phase 4: Symlink target='$actual_target' after repair, expected volume path" >&2
        return 1
    fi

    # Verify sentinel is gone (was in the replaced real directory)
    if exec_in_container "$SYNC_TEST_CONTAINER" test -f "/home/agent/.claude/plugins/sentinel.txt" 2>/dev/null; then
        printf '%s\n' "[DEBUG] Phase 4: Sentinel file still exists - R flag did not replace directory" >&2
        return 1
    fi

    # Verify synced content still accessible
    if ! exec_in_container "$SYNC_TEST_CONTAINER" test -f "/home/agent/.claude/plugins/test.json" 2>/dev/null; then
        printf '%s\n' "[DEBUG] Phase 4: Synced content not accessible after repair" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 5: x Flag (Exclude .system/) - .system/ excluded from Codex skills
# ==============================================================================
# The x flag excludes .system/ subdirectory from sync.

setup_x_flag_excludes_system_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.codex/skills"
    mkdir -p "$fixture/.codex/skills/.system"

    # User skill - should sync
    printf '%s\n' '{"skill": "user"}' >"$fixture/.codex/skills/test.json"

    # .system/ content - should be EXCLUDED
    printf '%s\n' '{"system": "hidden"}' >"$fixture/.codex/skills/.system/cache.json"
}

test_x_flag_excludes_system_assertions() {
    # User skill should sync
    assert_file_exists_in_volume "codex/skills/test.json" || {
        printf '%s\n' "[DEBUG] codex/skills/test.json should exist" >&2
        return 1
    }

    # .system/ should be excluded
    if assert_path_exists_in_volume "codex/skills/.system" 2>/dev/null; then
        printf '%s\n' "[DEBUG] codex/skills/.system should NOT exist (x flag excludes .system/)" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 6: o Flag (Optional) - missing source = no target created
# ==============================================================================
# Optional entries are completely skipped when source is missing.

setup_optional_missing_no_target_fixture() {
    # Don't create any Pi config (all entries are optional)
    # Pi directory should not exist - empty fixture is intentional
    :
}

test_optional_missing_no_target_assertions() {
    # No Pi directory should exist in volume
    if assert_path_exists_in_volume "pi" 2>/dev/null; then
        printf '%s\n' "[DEBUG] pi directory should NOT exist when source is missing" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 7: Import --dry-run - Shows [DRY-RUN] markers, no volume changes
# ==============================================================================
# --dry-run should show what would happen without making changes.

test_import_dry_run() {
    sync_test_info "Testing import --dry-run"

    # Create fresh volume and container for this test
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "flags-data-${SYNC_TEST_COUNTER}")

    create_test_container "dry-run" \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

    start_test_container "test-dry-run-${SYNC_TEST_RUN_ID}"
    SYNC_TEST_CONTAINER="test-dry-run-${SYNC_TEST_RUN_ID}"

    # Set up fixture with files
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    printf '%s\n' '{"test": true}' >"$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"

    # Ensure profile home is set up
    if [[ -z "$SYNC_TEST_PROFILE_HOME" ]]; then
        init_profile_home >/dev/null
    fi

    # Run import with --dry-run and capture exit status
    local output import_exit=0
    output=$(run_cai_import_from --dry-run) || import_exit=$?

    # dry-run should succeed (exit 0)
    if [[ $import_exit -ne 0 ]]; then
        sync_test_fail "import-dry-run: command failed with exit=$import_exit"
        printf '%s\n' "[DEBUG] Output: $output" >&2
        stop_test_container "test-dry-run-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-dry-run-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    # Should show [DRY-RUN] markers
    if [[ "$output" != *"[DRY-RUN]"* ]]; then
        sync_test_fail "import-dry-run: No [DRY-RUN] markers in output"
        printf '%s\n' "[DEBUG] Output: $output" >&2
        stop_test_container "test-dry-run-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-dry-run-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    # Volume should remain unchanged (no settings.json)
    if assert_path_exists_in_volume "claude/settings.json" 2>/dev/null; then
        sync_test_fail "import-dry-run: Volume was modified (should be unchanged)"
        printf '%s\n' "[DEBUG] claude/settings.json should NOT exist after dry-run" >&2
        stop_test_container "test-dry-run-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-dry-run-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    sync_test_pass "import-dry-run"

    # Cleanup
    stop_test_container "test-dry-run-${SYNC_TEST_RUN_ID}"
    "${DOCKER_CMD[@]}" rm -f "test-dry-run-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
    "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# Test 8: Import --no-secrets - s-flagged entries skipped entirely
# ==============================================================================
# --no-secrets should skip entries with s flag entirely (no placeholder).

test_import_no_secrets() {
    sync_test_info "Testing import --no-secrets"

    # Create fresh volume and container for this test
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "flags-data-${SYNC_TEST_COUNTER}")

    create_test_container "no-secrets" \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

    start_test_container "test-no-secrets-${SYNC_TEST_RUN_ID}"
    SYNC_TEST_CONTAINER="test-no-secrets-${SYNC_TEST_RUN_ID}"

    # Set up fixture with both secret and non-secret files
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    printf '%s\n' '{"token": "secret"}' >"$SYNC_TEST_FIXTURE_HOME/.claude/.credentials.json"
    printf '%s\n' '{"settings": true}' >"$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"

    # Ensure profile home is set up
    if [[ -z "$SYNC_TEST_PROFILE_HOME" ]]; then
        init_profile_home >/dev/null
    fi

    # Run import with --no-secrets
    local output
    output=$(run_cai_import_from --no-secrets 2>&1) || {
        sync_test_fail "import-no-secrets: import failed"
        printf '%s\n' "[DEBUG] Output: $output" >&2
        stop_test_container "test-no-secrets-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-no-secrets-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    }

    # Non-secret file should sync
    if ! assert_file_exists_in_volume "claude/settings.json" 2>/dev/null; then
        sync_test_fail "import-no-secrets: non-secret file should sync"
        printf '%s\n' "[DEBUG] claude/settings.json should exist" >&2
        stop_test_container "test-no-secrets-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-no-secrets-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    # Secret file should be skipped entirely (no placeholder)
    if assert_path_exists_in_volume "claude/credentials.json" 2>/dev/null; then
        sync_test_fail "import-no-secrets: secret file should be skipped"
        printf '%s\n' "[DEBUG] claude/credentials.json should NOT exist with --no-secrets" >&2
        stop_test_container "test-no-secrets-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-no-secrets-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    sync_test_pass "import-no-secrets"

    # Cleanup
    stop_test_container "test-no-secrets-${SYNC_TEST_RUN_ID}"
    "${DOCKER_CMD[@]}" rm -f "test-no-secrets-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
    "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# Helper: Run cai export
# ==============================================================================
run_cai_export() {
    # Use profile home for HOME so config discovery works
    if [[ -z "$SYNC_TEST_PROFILE_HOME" ]]; then
        init_profile_home >/dev/null
    fi
    HOME="$SYNC_TEST_PROFILE_HOME" bash -c 'source "$1/containai.sh" && shift && cai export "$@"' _ "$SYNC_TEST_SRC_DIR" --data-volume "$SYNC_TEST_DATA_VOLUME" "$@" 2>&1
}

# ==============================================================================
# Test 9: Export Basic - creates .tgz archive
# ==============================================================================
# cai export should create a .tgz archive from the data volume.

test_export_basic() {
    sync_test_info "Testing export basic"

    # Create fresh volume and container for this test
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "flags-data-${SYNC_TEST_COUNTER}")

    create_test_container "export-basic" \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

    start_test_container "test-export-basic-${SYNC_TEST_RUN_ID}"
    SYNC_TEST_CONTAINER="test-export-basic-${SYNC_TEST_RUN_ID}"

    # Set up fixture and import some data
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    printf '%s\n' '{"original": true}' >"$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"

    # Ensure profile home is set up
    if [[ -z "$SYNC_TEST_PROFILE_HOME" ]]; then
        init_profile_home >/dev/null
    fi

    local import_output
    import_output=$(run_cai_import_from) || {
        sync_test_fail "export-basic: import failed"
        printf '%s\n' "[DEBUG] Output: $import_output" >&2
        stop_test_container "test-export-basic-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-basic-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    }

    # Modify data in container volume
    exec_in_container "$SYNC_TEST_CONTAINER" bash -c 'echo "{\"modified\": true}" > /mnt/agent-data/claude/settings.json'

    # Export to a .tgz archive
    EXPORT_ARCHIVE=$(mktemp --suffix=.tgz)
    local export_output
    export_output=$(run_cai_export --output "$EXPORT_ARCHIVE" 2>&1) || {
        sync_test_fail "export-basic: export failed"
        printf '%s\n' "[DEBUG] Output: $export_output" >&2
        rm -f "$EXPORT_ARCHIVE" 2>/dev/null || true
        stop_test_container "test-export-basic-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-basic-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    }

    # Verify archive exists
    if [[ ! -f "$EXPORT_ARCHIVE" ]]; then
        sync_test_fail "export-basic: archive not created"
        printf '%s\n' "[DEBUG] Expected archive at: $EXPORT_ARCHIVE" >&2
        stop_test_container "test-export-basic-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-basic-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    # Verify archive contains expected files
    if ! tar -tzf "$EXPORT_ARCHIVE" 2>/dev/null | grep -q "claude/settings.json"; then
        sync_test_fail "export-basic: archive doesn't contain expected file"
        printf '%s\n' "[DEBUG] Archive contents:" >&2
        tar -tzf "$EXPORT_ARCHIVE" 2>&1 | head -20 >&2
        rm -f "$EXPORT_ARCHIVE" 2>/dev/null || true
        stop_test_container "test-export-basic-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-basic-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    # Extract and verify content
    EXTRACT_DIR=$(mktemp -d)
    tar -xzf "$EXPORT_ARCHIVE" -C "$EXTRACT_DIR"
    local content
    content=$(cat "$EXTRACT_DIR/claude/settings.json" 2>/dev/null) || content=""
    if [[ "$content" != *"modified"* ]]; then
        sync_test_fail "export-basic: exported content doesn't match"
        printf '%s\n' "[DEBUG] Content: $content" >&2
        rm -rf "$EXTRACT_DIR" "$EXPORT_ARCHIVE" 2>/dev/null || true
        stop_test_container "test-export-basic-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-basic-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    sync_test_pass "export-basic"

    # Cleanup
    rm -rf "$EXTRACT_DIR" "$EXPORT_ARCHIVE" 2>/dev/null || true
    stop_test_container "test-export-basic-${SYNC_TEST_RUN_ID}"
    "${DOCKER_CMD[@]}" rm -f "test-export-basic-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
    "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# Test 10: Export with config excludes
# ==============================================================================
# Export should respect default_excludes from config file.

test_export_with_config_excludes() {
    sync_test_info "Testing export with config excludes"

    # Create fresh volume and container for this test
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "flags-data-${SYNC_TEST_COUNTER}")

    create_test_container "export-excludes" \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

    start_test_container "test-export-excludes-${SYNC_TEST_RUN_ID}"
    SYNC_TEST_CONTAINER="test-export-excludes-${SYNC_TEST_RUN_ID}"

    # Ensure profile home is set up
    if [[ -z "$SYNC_TEST_PROFILE_HOME" ]]; then
        init_profile_home >/dev/null
    fi

    # Create config with exclude patterns (top-level default_excludes)
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai"
    cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/containai.toml" <<'EOF'
default_excludes = ["shell/bashrc.d/*.priv.*"]
EOF

    # Import some data
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.bashrc.d"
    printf '%s\n' 'public' >"$SYNC_TEST_FIXTURE_HOME/.bashrc.d/public.sh"
    local import_output
    import_output=$(run_cai_import_from) || {
        sync_test_fail "export-config-excludes: import failed"
        printf '%s\n' "[DEBUG] Output: $import_output" >&2
        stop_test_container "test-export-excludes-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-excludes-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    }

    # Add a .priv file directly to volume (simulating container-side creation)
    exec_in_container "$SYNC_TEST_CONTAINER" bash -c 'echo "secret" > /mnt/agent-data/shell/bashrc.d/secret.priv.sh'

    # Export with config that has excludes
    EXPORT_ARCHIVE=$(mktemp --suffix=.tgz)
    local export_output
    export_output=$(run_cai_export --output "$EXPORT_ARCHIVE" --config "$SYNC_TEST_FIXTURE_HOME/.config/containai/containai.toml" 2>&1) || {
        sync_test_fail "export-config-excludes: export failed"
        printf '%s\n' "[DEBUG] Output: $export_output" >&2
        rm -f "$EXPORT_ARCHIVE" 2>/dev/null || true
        stop_test_container "test-export-excludes-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-excludes-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    }

    # Extract archive
    EXTRACT_DIR=$(mktemp -d)
    tar -xzf "$EXPORT_ARCHIVE" -C "$EXTRACT_DIR"

    # public.sh should be in archive
    if [[ ! -f "$EXTRACT_DIR/shell/bashrc.d/public.sh" ]]; then
        sync_test_fail "export-config-excludes: public.sh should be in archive"
        printf '%s\n' "[DEBUG] Archive contents:" >&2
        tar -tzf "$EXPORT_ARCHIVE" 2>&1 | head -20 >&2
        rm -rf "$EXTRACT_DIR" "$EXPORT_ARCHIVE" 2>/dev/null || true
        stop_test_container "test-export-excludes-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-excludes-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    # .priv file should be excluded per config
    if [[ -e "$EXTRACT_DIR/shell/bashrc.d/secret.priv.sh" ]]; then
        sync_test_fail "export-config-excludes: .priv file should be excluded"
        printf '%s\n' "[DEBUG] secret.priv.sh should NOT be in archive" >&2
        rm -rf "$EXTRACT_DIR" "$EXPORT_ARCHIVE" 2>/dev/null || true
        stop_test_container "test-export-excludes-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-excludes-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    sync_test_pass "export-config-excludes"

    # Cleanup
    rm -rf "$EXTRACT_DIR" "$EXPORT_ARCHIVE" 2>/dev/null || true
    stop_test_container "test-export-excludes-${SYNC_TEST_RUN_ID}"
    "${DOCKER_CMD[@]}" rm -f "test-export-excludes-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
    "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# Test 11: Export --no-excludes flag
# ==============================================================================
# --no-excludes should skip exclude patterns from config.

test_export_no_excludes_flag() {
    sync_test_info "Testing export --no-excludes"

    # Create fresh volume and container for this test
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "flags-data-${SYNC_TEST_COUNTER}")

    create_test_container "export-no-excludes" \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

    start_test_container "test-export-no-excludes-${SYNC_TEST_RUN_ID}"
    SYNC_TEST_CONTAINER="test-export-no-excludes-${SYNC_TEST_RUN_ID}"

    # Ensure profile home is set up
    if [[ -z "$SYNC_TEST_PROFILE_HOME" ]]; then
        init_profile_home >/dev/null
    fi

    # Create config with exclude patterns that would exclude claude/*
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.config/containai"
    cat > "$SYNC_TEST_FIXTURE_HOME/.config/containai/containai.toml" <<'EOF'
default_excludes = ["claude/*"]
EOF

    # Import some data
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    printf '%s\n' '{}' >"$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"
    local import_output
    import_output=$(run_cai_import_from) || {
        sync_test_fail "export-no-excludes: import failed"
        printf '%s\n' "[DEBUG] Output: $import_output" >&2
        stop_test_container "test-export-no-excludes-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-no-excludes-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    }

    # Export with --no-excludes
    EXPORT_ARCHIVE=$(mktemp --suffix=.tgz)
    local export_output
    export_output=$(run_cai_export --output "$EXPORT_ARCHIVE" --config "$SYNC_TEST_FIXTURE_HOME/.config/containai/containai.toml" --no-excludes 2>&1) || {
        sync_test_fail "export-no-excludes: export failed"
        printf '%s\n' "[DEBUG] Output: $export_output" >&2
        rm -f "$EXPORT_ARCHIVE" 2>/dev/null || true
        stop_test_container "test-export-no-excludes-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-no-excludes-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    }

    # claude/settings.json should be in archive (excludes skipped)
    if ! tar -tzf "$EXPORT_ARCHIVE" 2>/dev/null | grep -q "claude/settings.json"; then
        sync_test_fail "export-no-excludes: claude/settings.json should be in archive"
        printf '%s\n' "[DEBUG] Archive contents:" >&2
        tar -tzf "$EXPORT_ARCHIVE" 2>&1 | head -20 >&2
        rm -f "$EXPORT_ARCHIVE" 2>/dev/null || true
        stop_test_container "test-export-no-excludes-${SYNC_TEST_RUN_ID}"
        "${DOCKER_CMD[@]}" rm -f "test-export-no-excludes-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    sync_test_pass "export-no-excludes"

    # Cleanup
    rm -f "$EXPORT_ARCHIVE" 2>/dev/null || true
    stop_test_container "test-export-no-excludes-${SYNC_TEST_RUN_ID}"
    "${DOCKER_CMD[@]}" rm -f "test-export-no-excludes-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
    "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# Main Test Execution
# ==============================================================================
main() {
    sync_test_section "Flag and Operation Tests"
    sync_test_info "Run ID: $SYNC_TEST_RUN_ID"

    # Test 1: s Flag (Secret File Permissions)
    run_flags_test "s-flag-permissions" setup_secret_file_permissions_fixture test_secret_file_permissions_assertions

    # Test 2: j Flag (JSON Init) - {} created for non-optional fj entries
    run_flags_test "j-flag-non-optional" setup_json_init_non_optional_fixture test_json_init_non_optional_assertions

    # Test 3: j Flag (JSON Init) - optional fjo entries NOT created when missing
    run_flags_test "j-flag-optional-skipped" setup_json_init_optional_skipped_fixture test_json_init_optional_skipped_assertions

    # Test 4: R Flag (Remove Existing Before Symlink) via link-repair
    run_flags_test "R-flag-symlink" setup_R_flag_symlink_fixture test_R_flag_symlink_assertions

    # Test 5: x Flag (Exclude .system/)
    run_flags_test "x-flag-system" setup_x_flag_excludes_system_fixture test_x_flag_excludes_system_assertions

    # Test 6: o Flag (Optional) - missing source = no target created
    run_flags_test "o-flag-optional" setup_optional_missing_no_target_fixture test_optional_missing_no_target_assertions

    # Test 7: Import --dry-run
    test_import_dry_run

    # Test 8: Import --no-secrets
    test_import_no_secrets

    # Test 9: Export Basic
    test_export_basic

    # Test 10: Export with config excludes
    test_export_with_config_excludes

    # Test 11: Export --no-excludes flag
    test_export_no_excludes_flag

    sync_test_section "Summary"
    if [[ $SYNC_TEST_FAILED -eq 0 ]]; then
        sync_test_info "All flag and operation tests passed"
        exit 0
    else
        sync_test_info "Some flag and operation tests failed"
        exit 1
    fi
}

main "$@"
