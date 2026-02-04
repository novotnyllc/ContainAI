#!/usr/bin/env bash
# ==============================================================================
# Edge Case Tests
# ==============================================================================
# Tests edge cases: no-pollution for optional entries, partial configs,
# large directories, symlink relinking, concurrent containers.
#
# Edge cases tested:
#   1. No pollution (optional agent roots not created when missing)
#   2. Partial config (non-optional - placeholder behavior)
#   3. Partial config (optional - no creation)
#   4. Pi volume paths (pi/settings.json not pi/agent/settings.json)
#   5. Large fonts/ directory (50 files)
#   6. Unicode content preserved
#   7. Internal absolute symlinks relinked
#   8. Concurrent containers (separate volumes)
#
# Usage:
#   ./tests/integration/sync-tests/test-edge-cases.sh
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
# Usage: run_edge_test NAME SETUP_FN TEST_FN
run_edge_test() {
    local test_name="$1"
    local setup_fn="$2"
    local test_fn="$3"

    local import_output import_exit=0

    # Create fresh volume for this test (isolation)
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "edge-data-${SYNC_TEST_COUNTER}")

    # Create unique container for this test
    # Override entrypoint to bypass systemd (which requires Sysbox)
    # Use tail -f for portable keepalive
    create_test_container "$test_name" \
        --entrypoint /bin/bash \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" -c "tail -f /dev/null" >/dev/null

    # Set up fixture
    if [[ -n "$setup_fn" ]]; then
        "$setup_fn"
    fi

    # Run import and capture output/exit code
    import_output=$(run_cai_import_from 2>&1) || import_exit=$?
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
# Test 1: No Pollution (Optional Agent Roots)
# ==============================================================================
# Optional agents (o flag) should NOT create any target directories when
# source is missing. This verifies no symlinks, no directories, no volume
# entries for Pi, Kimi, Cursor, etc. when not configured.

setup_no_pollution_optional_agents() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    # Create only Claude config (non-optional agent)
    mkdir -p "$fixture/.claude"
    printf '%s\n' '{}' > "$fixture/.claude/settings.json"

    # DON'T create Pi, Kimi, Cursor, Copilot, Gemini, Aider, Continue configs (optional agents)
}

test_no_pollution_optional_agents_assertions() {
    # Claude should exist (non-optional)
    assert_path_exists_in_container "/home/agent/.claude" || {
        printf '%s\n' "[DEBUG] Claude should exist in container" >&2
        return 1
    }

    # Optional agents should NOT exist (no symlinks, no dirs) in container
    if exec_in_container "$SYNC_TEST_CONTAINER" test -e "/home/agent/.pi" 2>/dev/null; then
        printf '%s\n' "[DEBUG] .pi should NOT exist in container" >&2
        return 1
    fi

    if exec_in_container "$SYNC_TEST_CONTAINER" test -e "/home/agent/.kimi" 2>/dev/null; then
        printf '%s\n' "[DEBUG] .kimi should NOT exist in container" >&2
        return 1
    fi

    if exec_in_container "$SYNC_TEST_CONTAINER" test -e "/home/agent/.cursor" 2>/dev/null; then
        printf '%s\n' "[DEBUG] .cursor should NOT exist in container" >&2
        return 1
    fi

    # No volume entries either for optional agents
    if assert_path_exists_in_volume "pi" 2>/dev/null; then
        printf '%s\n' "[DEBUG] pi volume dir should NOT exist" >&2
        return 1
    fi

    if assert_path_exists_in_volume "kimi" 2>/dev/null; then
        printf '%s\n' "[DEBUG] kimi volume dir should NOT exist" >&2
        return 1
    fi

    if assert_path_exists_in_volume "cursor" 2>/dev/null; then
        printf '%s\n' "[DEBUG] cursor volume dir should NOT exist" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 2: Partial Config (Non-Optional - Placeholder Behavior)
# ==============================================================================
# For non-optional entries with s/j flags, missing sources get placeholders.
# Creates .claude dir but only settings.json, not credentials (fs - secret).

setup_partial_config_non_optional() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.claude"
    # Only create settings.json (fj - non-optional)
    printf '%s\n' '{"editor": "vim"}' > "$fixture/.claude/settings.json"
    # Don't create .credentials.json (fs - secret, non-optional)
}

test_partial_config_non_optional_assertions() {
    # settings.json should sync with content
    assert_file_exists_in_volume "claude/settings.json" || {
        printf '%s\n' "[DEBUG] settings.json should exist in volume" >&2
        return 1
    }
    local content
    content=$(cat_from_volume "claude/settings.json")
    if [[ "$content" != *"editor"* ]]; then
        printf '%s\n' "[DEBUG] settings.json content missing 'editor': $content" >&2
        return 1
    fi

    # .credentials.json: missing source with fs flags gets placeholder
    # Placeholder exists with 600 perms but empty (ensure() creates it)
    assert_file_exists_in_volume "claude/credentials.json" || {
        printf '%s\n' "[DEBUG] credentials.json placeholder should exist" >&2
        return 1
    }
    assert_permissions_in_volume "claude/credentials.json" "600" || {
        local actual
        actual=$(exec_in_container "$SYNC_TEST_CONTAINER" stat -c '%a' "/mnt/agent-data/claude/credentials.json")
        printf '%s\n' "[DEBUG] credentials.json perms='$actual', expected='600'" >&2
        return 1
    }

    return 0
}

# ==============================================================================
# Test 3: Partial Config (Optional Agent)
# ==============================================================================
# Optional entries are completely skipped when source is missing.
# If partial Pi config exists, only existing files sync.

setup_partial_config_optional_agent() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    # Create partial Pi config
    # Source: .pi/agent/settings.json -> Target: pi/settings.json
    mkdir -p "$fixture/.pi/agent"
    printf '%s\n' '{}' > "$fixture/.pi/agent/settings.json"
    # Don't create models.json (fjso - optional secret)
    # Don't create keybindings.json (fjo - optional)
}

test_partial_config_optional_agent_assertions() {
    # settings.json syncs (source exists)
    # Note: target is "pi/settings.json" not "pi/agent/settings.json"
    assert_file_exists_in_volume "pi/settings.json" || {
        printf '%s\n' "[DEBUG] pi/settings.json should exist" >&2
        return 1
    }

    # models.json NOT created (fjso - optional, source missing)
    if assert_path_exists_in_volume "pi/models.json" 2>/dev/null; then
        printf '%s\n' "[DEBUG] pi/models.json should NOT exist (optional, source missing)" >&2
        return 1
    fi

    # keybindings.json NOT created (fjo - optional, source missing)
    if assert_path_exists_in_volume "pi/keybindings.json" 2>/dev/null; then
        printf '%s\n' "[DEBUG] pi/keybindings.json should NOT exist (optional, source missing)" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 4: Pi Volume Path Mapping
# ==============================================================================
# Verify Pi source paths map correctly to target paths.
# Source: .pi/agent/X -> Target: pi/X (no 'agent' in target)

setup_pi_path_mapping() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.pi/agent/skills/custom"
    mkdir -p "$fixture/.pi/agent/extensions"

    printf '%s\n' '{"settings": true}' > "$fixture/.pi/agent/settings.json"
    printf '%s\n' '{"models": "secret"}' > "$fixture/.pi/agent/models.json"
    printf '%s\n' '{"keybindings": true}' > "$fixture/.pi/agent/keybindings.json"
    printf '%s\n' '{"skill": "custom"}' > "$fixture/.pi/agent/skills/custom/user.json"
    printf '%s\n' 'extension' > "$fixture/.pi/agent/extensions/ext.txt"
}

test_pi_path_mapping_assertions() {
    # Verify target is pi/X not pi/agent/X
    assert_file_exists_in_volume "pi/settings.json" || {
        printf '%s\n' "[DEBUG] pi/settings.json should exist (not pi/agent/settings.json)" >&2
        return 1
    }
    assert_file_exists_in_volume "pi/models.json" || {
        printf '%s\n' "[DEBUG] pi/models.json should exist" >&2
        return 1
    }
    assert_file_exists_in_volume "pi/keybindings.json" || {
        printf '%s\n' "[DEBUG] pi/keybindings.json should exist" >&2
        return 1
    }
    assert_dir_exists_in_volume "pi/skills/custom" || {
        printf '%s\n' "[DEBUG] pi/skills/custom should exist" >&2
        return 1
    }
    assert_dir_exists_in_volume "pi/extensions" || {
        printf '%s\n' "[DEBUG] pi/extensions should exist" >&2
        return 1
    }

    # Verify content
    local content
    content=$(cat_from_volume "pi/settings.json")
    if [[ "$content" != *"settings"* ]]; then
        printf '%s\n' "[DEBUG] pi/settings.json missing 'settings': $content" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 5: Large Directory (fonts/)
# ==============================================================================
# Verify large directories sync completely.

setup_large_fonts_directory() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.local/share/fonts"
    local i
    for i in $(seq 1 50); do
        # Create small dummy font files
        printf 'font%d' "$i" > "$fixture/.local/share/fonts/font$i.ttf"
    done
}

test_large_fonts_directory_assertions() {
    # Verify fonts directory exists
    assert_dir_exists_in_volume "local/share/fonts" || {
        printf '%s\n' "[DEBUG] local/share/fonts should exist" >&2
        return 1
    }

    # Verify all 50 fonts synced
    local count
    count=$(exec_in_container "$SYNC_TEST_CONTAINER" find /mnt/agent-data/local/share/fonts -type f -name '*.ttf' 2>/dev/null | wc -l)
    if [[ "$count" -ne 50 ]]; then
        printf '%s\n' "[DEBUG] Expected 50 fonts, found $count" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 6: Unicode Content Preserved
# ==============================================================================
# Verify Unicode characters (emoji, CJK) are preserved during sync.

setup_unicode_content() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.claude"
    # Use actual Unicode characters
    printf '%s\n' '{"name": "Test User", "emoji": "🚀", "chinese": "你好世界"}' > "$fixture/.claude/settings.json"
}

test_unicode_content_assertions() {
    local content
    content=$(cat_from_volume "claude/settings.json")

    # Check for rocket emoji (may be multi-byte)
    if [[ "$content" != *"🚀"* ]]; then
        printf '%s\n' "[DEBUG] Emoji not preserved: $content" >&2
        return 1
    fi

    # Check for Chinese characters
    if [[ "$content" != *"你好世界"* ]]; then
        printf '%s\n' "[DEBUG] Chinese not preserved: $content" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 7: Internal Absolute Symlinks Relinked
# ==============================================================================
# Verify that internal absolute symlinks are relinked to container paths.
# The import process should adjust symlinks that point within the synced tree.

setup_internal_symlink() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.agents/shared"
    printf 'shared config\n' > "$fixture/.agents/shared/base.yml"
    # Create absolute symlink pointing to host path
    ln -s "$fixture/.agents/shared/base.yml" "$fixture/.agents/link.yml"
}

test_internal_symlink_assertions() {
    # The .agents directory should exist
    assert_dir_exists_in_volume "agents" || {
        printf '%s\n' "[DEBUG] agents dir should exist" >&2
        return 1
    }

    # Check if symlink exists
    if ! exec_in_container "$SYNC_TEST_CONTAINER" test -L "/mnt/agent-data/agents/link.yml" 2>/dev/null; then
        # Symlink may have been resolved to a file, which is also acceptable
        if exec_in_container "$SYNC_TEST_CONTAINER" test -f "/mnt/agent-data/agents/link.yml" 2>/dev/null; then
            # Verify content is correct (symlink was dereferenced)
            local content
            content=$(cat_from_volume "agents/link.yml")
            if [[ "$content" == *"shared config"* ]]; then
                # Symlink was dereferenced, content preserved - acceptable
                return 0
            fi
        fi
        printf '%s\n' "[DEBUG] link.yml should exist as symlink or file" >&2
        return 1
    fi

    # If it's a symlink, verify target doesn't point to original host path
    local link_target
    link_target=$(exec_in_container "$SYNC_TEST_CONTAINER" readlink /mnt/agent-data/agents/link.yml 2>/dev/null) || true

    # The symlink should NOT contain the original fixture home path
    if [[ "$link_target" == *"$SYNC_TEST_FIXTURE_HOME"* ]]; then
        printf '%s\n' "[DEBUG] Symlink still points to host path: $link_target" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 8: Concurrent Containers (Separate Volumes)
# ==============================================================================
# Each container uses its own volume to avoid conflicts.
# This is the expected production pattern.

test_concurrent_containers() {
    sync_test_info "Testing concurrent containers with separate volumes"

    # Create two volumes
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    local vol1 vol2
    vol1=$(create_test_volume "concurrent-vol1-${SYNC_TEST_COUNTER}")
    vol2=$(create_test_volume "concurrent-vol2-${SYNC_TEST_COUNTER}")

    # Create two containers with separate volumes
    # Override entrypoint to bypass systemd (which requires Sysbox)
    create_test_container "concurrent-1" \
        --entrypoint /bin/bash \
        --volume "$vol1:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" -c "tail -f /dev/null" >/dev/null
    create_test_container "concurrent-2" \
        --entrypoint /bin/bash \
        --volume "$vol2:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" -c "tail -f /dev/null" >/dev/null

    local container1="test-concurrent-1-${SYNC_TEST_RUN_ID}"
    local container2="test-concurrent-2-${SYNC_TEST_RUN_ID}"

    # Create fixture
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    printf '%s\n' '{"original": true}' > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"

    # Ensure profile home is set up
    if [[ -z "$SYNC_TEST_PROFILE_HOME" ]]; then
        init_profile_home >/dev/null
    fi

    # Import to both volumes
    local import_output1 import_output2
    import_output1=$(HOME="$SYNC_TEST_PROFILE_HOME" bash -c 'source "$1/containai.sh" && shift && cai import "$@"' _ "$SYNC_TEST_SRC_DIR" --from "$SYNC_TEST_FIXTURE_HOME" --data-volume "$vol1" 2>&1) || {
        sync_test_fail "concurrent-containers: import to vol1 failed"
        printf '%s\n' "$import_output1" >&2
        "${DOCKER_CMD[@]}" rm -f "$container1" "$container2" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$vol1" "$vol2" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    }
    import_output2=$(HOME="$SYNC_TEST_PROFILE_HOME" bash -c 'source "$1/containai.sh" && shift && cai import "$@"' _ "$SYNC_TEST_SRC_DIR" --from "$SYNC_TEST_FIXTURE_HOME" --data-volume "$vol2" 2>&1) || {
        sync_test_fail "concurrent-containers: import to vol2 failed"
        printf '%s\n' "$import_output2" >&2
        "${DOCKER_CMD[@]}" rm -f "$container1" "$container2" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$vol1" "$vol2" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    }

    # Start containers
    start_test_container "$container1"
    start_test_container "$container2"

    # Both should have configs independently
    if ! "${DOCKER_CMD[@]}" exec "$container1" test -f /mnt/agent-data/claude/settings.json 2>/dev/null; then
        sync_test_fail "concurrent-containers: container1 missing settings.json"
        "${DOCKER_CMD[@]}" rm -f "$container1" "$container2" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$vol1" "$vol2" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi
    if ! "${DOCKER_CMD[@]}" exec "$container2" test -f /mnt/agent-data/claude/settings.json 2>/dev/null; then
        sync_test_fail "concurrent-containers: container2 missing settings.json"
        "${DOCKER_CMD[@]}" rm -f "$container1" "$container2" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$vol1" "$vol2" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    # Modify container1's volume, verify container2 unchanged
    "${DOCKER_CMD[@]}" exec "$container1" bash -c 'echo "MODIFIED_BY_CONTAINER1" >> /mnt/agent-data/claude/settings.json' 2>/dev/null

    local content2
    content2=$("${DOCKER_CMD[@]}" exec "$container2" cat /mnt/agent-data/claude/settings.json 2>/dev/null) || content2=""
    if [[ "$content2" == *"MODIFIED_BY_CONTAINER1"* ]]; then
        sync_test_fail "concurrent-containers: volumes should be isolated"
        printf '%s\n' "[DEBUG] container2 content: $content2" >&2
        "${DOCKER_CMD[@]}" rm -f "$container1" "$container2" 2>/dev/null || true
        "${DOCKER_CMD[@]}" volume rm "$vol1" "$vol2" 2>/dev/null || true
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
        return
    fi

    sync_test_pass "concurrent-containers"

    # Cleanup
    "${DOCKER_CMD[@]}" stop "$container1" "$container2" 2>/dev/null || true
    "${DOCKER_CMD[@]}" rm -f "$container1" "$container2" 2>/dev/null || true
    "${DOCKER_CMD[@]}" volume rm "$vol1" "$vol2" 2>/dev/null || true
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# Main Test Execution
# ==============================================================================
main() {
    sync_test_section "Edge Case Tests"
    sync_test_info "Run ID: $SYNC_TEST_RUN_ID"

    # Test 1: No Pollution (Optional Agent Roots)
    run_edge_test "no-pollution-optional" setup_no_pollution_optional_agents test_no_pollution_optional_agents_assertions

    # Test 2: Partial Config (Non-Optional - Placeholder Behavior)
    run_edge_test "partial-non-optional" setup_partial_config_non_optional test_partial_config_non_optional_assertions

    # Test 3: Partial Config (Optional Agent)
    run_edge_test "partial-optional" setup_partial_config_optional_agent test_partial_config_optional_agent_assertions

    # Test 4: Pi Volume Path Mapping
    run_edge_test "pi-path-mapping" setup_pi_path_mapping test_pi_path_mapping_assertions

    # Test 5: Large Directory (fonts/)
    run_edge_test "large-fonts" setup_large_fonts_directory test_large_fonts_directory_assertions

    # Test 6: Unicode Content Preserved
    run_edge_test "unicode-content" setup_unicode_content test_unicode_content_assertions

    # Test 7: Internal Absolute Symlinks Relinked
    run_edge_test "internal-symlinks" setup_internal_symlink test_internal_symlink_assertions

    # Test 8: Concurrent Containers (Separate Volumes)
    test_concurrent_containers

    sync_test_section "Summary"
    if [[ $SYNC_TEST_FAILED -eq 0 ]]; then
        sync_test_info "All edge case tests passed"
        exit 0
    else
        sync_test_info "Some edge case tests failed"
        exit 1
    fi
}

main "$@"
