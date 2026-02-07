#!/usr/bin/env bash
# ==============================================================================
# AI Agent Sync Tests
# ==============================================================================
# Tests sync for all 10 AI agents using `--from <fixture>` to validate full
# content sync. Also tests profile-import placeholder behavior.
#
# Agents tested:
#   1. Claude Code
#   2. OpenCode (auth.json at ~/.local/share/opencode/)
#   3. Codex (x flag excludes .system/)
#   4. Copilot (optional, not secret)
#   5. Gemini (optional)
#   6. Aider (optional)
#   7. Continue (optional)
#   8. Cursor (optional)
#   9. Pi (optional)
#  10. Kimi (optional)
#
# Usage:
#   ./tests/integration/sync-tests/test-agent-sync.sh
#
# Prerequisites:
#   - Docker daemon running
#   - Test image built: dotnet msbuild src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
# Usage: run_agent_sync_test NAME SETUP_FN TEST_FN [--profile-import]
run_agent_sync_test() {
    local test_name="$1"
    local setup_fn="$2"
    local test_fn="$3"
    shift 3
    local profile_import=false

    # Parse optional flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile-import) profile_import=true; shift ;;
            *) shift ;;
        esac
    done

    local import_output import_exit=0

    # Create fresh volume for this test (isolation)
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "agent-data-${SYNC_TEST_COUNTER}")

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
    if [[ "$profile_import" == "true" ]]; then
        import_output=$(run_cai_import_profile 2>&1) || import_exit=$?
    else
        import_output=$(run_cai_import_from 2>&1) || import_exit=$?
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

    # Run init script to create symlinks (since we bypassed systemd)
    exec_in_container "$SYNC_TEST_CONTAINER" cai system init >/dev/null 2>&1 || true

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
# Test 1: Claude Code
# ==============================================================================
test_claude_sync_assertions() {
    # Verify files synced to volume
    assert_file_exists_in_volume "claude/claude.json" || return 1
    assert_file_exists_in_volume "claude/credentials.json" || return 1
    assert_file_exists_in_volume "claude/settings.json" || return 1
    assert_file_exists_in_volume "claude/settings.local.json" || return 1
    assert_dir_exists_in_volume "claude/plugins" || return 1
    assert_file_exists_in_volume "claude/plugins/cache/test-plugin/plugin.json" || return 1
    assert_file_exists_in_volume "claude/commands/command.txt" || return 1
    assert_file_exists_in_volume "claude/agents/agent.json" || return 1
    assert_file_exists_in_volume "claude/skills/skill.json" || return 1
    assert_file_exists_in_volume "claude/hooks/hook.sh" || return 1
    assert_file_exists_in_volume "claude/CLAUDE.md" || return 1

    # Verify symlinks exist in container
    assert_is_symlink "/home/agent/.claude.json" || return 1
    assert_is_symlink "/home/agent/.claude/settings.json" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "claude/credentials.json" "CREDENTIALS_MARKER" || return 1
    assert_content_marker_in_volume "claude/claude.json" "CLAUDE_JSON_MARKER" || return 1
    assert_content_marker_in_volume "claude/settings.json" "SETTINGS_MARKER" || return 1
    assert_content_marker_in_volume "claude/settings.local.json" "SETTINGS_LOCAL_MARKER" || return 1
    assert_content_marker_in_volume "claude/commands/command.txt" "COMMAND_MARKER" || return 1
    assert_content_marker_in_volume "claude/agents/agent.json" "AGENT_MARKER" || return 1
    assert_content_marker_in_volume "claude/skills/skill.json" "SKILL_MARKER" || return 1
    assert_content_marker_in_volume "claude/hooks/hook.sh" "HOOK_MARKER" || return 1
    assert_content_marker_in_volume "claude/CLAUDE.md" "CLAUDE_MD_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 2: OpenCode (auth.json at ~/.local/share/opencode/)
# ==============================================================================
test_opencode_sync_assertions() {
    # Verify config directory entries synced
    assert_file_exists_in_volume "config/opencode/opencode.json" || return 1
    assert_file_exists_in_volume "config/opencode/instructions.md" || return 1
    assert_dir_exists_in_volume "config/opencode/agents" || return 1
    assert_dir_exists_in_volume "config/opencode/commands" || return 1
    assert_dir_exists_in_volume "config/opencode/skills" || return 1
    assert_dir_exists_in_volume "config/opencode/modes" || return 1
    assert_dir_exists_in_volume "config/opencode/plugins" || return 1
    assert_file_exists_in_volume "config/opencode/agents/agent.json" || return 1
    assert_file_exists_in_volume "config/opencode/commands/command.txt" || return 1
    assert_file_exists_in_volume "config/opencode/skills/skill.json" || return 1
    assert_file_exists_in_volume "config/opencode/modes/mode.json" || return 1
    assert_file_exists_in_volume "config/opencode/plugins/plugin.json" || return 1

    # Verify auth.json at different path (~/.local/share/opencode/)
    assert_file_exists_in_volume "local/share/opencode/auth.json" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "local/share/opencode/auth.json" "OPENCODE_AUTH_MARKER" || return 1
    assert_content_marker_in_volume "config/opencode/opencode.json" "OPENCODE_CONFIG_MARKER" || return 1
    assert_content_marker_in_volume "config/opencode/instructions.md" "OPENCODE_INSTRUCTIONS_MARKER" || return 1
    assert_content_marker_in_volume "config/opencode/agents/agent.json" "OPENCODE_AGENT_MARKER" || return 1
    assert_content_marker_in_volume "config/opencode/commands/command.txt" "OPENCODE_COMMAND_MARKER" || return 1
    assert_content_marker_in_volume "config/opencode/skills/skill.json" "OPENCODE_SKILL_MARKER" || return 1
    assert_content_marker_in_volume "config/opencode/modes/mode.json" "OPENCODE_MODE_MARKER" || return 1
    assert_content_marker_in_volume "config/opencode/plugins/plugin.json" "OPENCODE_PLUGIN_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 3: Codex (x flag excludes .system/)
# ==============================================================================
test_codex_sync_assertions() {
    # Verify config files synced
    assert_file_exists_in_volume "codex/config.toml" || return 1
    assert_file_exists_in_volume "codex/auth.json" || return 1

    # Verify .system/ was excluded (x flag)
    if assert_path_exists_in_volume "codex/skills/.system" 2>/dev/null; then
        return 1  # .system/ should NOT exist
    fi

    # Verify other skills synced
    assert_dir_exists_in_volume "codex/skills/custom" || return 1
    assert_file_exists_in_volume "codex/skills/custom/user.json" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "codex/auth.json" "CODEX_AUTH_MARKER" || return 1
    assert_content_marker_in_volume "codex/config.toml" "CODEX_CONFIG_MARKER" || return 1
    assert_content_marker_in_volume "codex/skills/custom/user.json" "CODEX_CUSTOM_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 4: Copilot (optional, not secret)
# ==============================================================================
# NOTE: Copilot is an optional agent (o flag), so symlinks are NOT created by
# init.sh. We only verify volume content, not container symlinks.
test_copilot_sync_assertions() {
    # Verify config files synced to volume
    assert_file_exists_in_volume "copilot/config.json" || return 1
    assert_file_exists_in_volume "copilot/mcp-config.json" || return 1
    assert_dir_exists_in_volume "copilot/skills" || return 1
    assert_file_exists_in_volume "copilot/skills/skill.json" || return 1

    # NOTE: No symlink assertions - optional agents don't have symlinks created
    # by init.sh (they're not in link-spec.json)

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "copilot/config.json" "COPILOT_CONFIG_MARKER" || return 1
    assert_content_marker_in_volume "copilot/mcp-config.json" "COPILOT_MCP_MARKER" || return 1
    assert_content_marker_in_volume "copilot/skills/skill.json" "COPILOT_SKILL_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 5: Gemini (optional)
# ==============================================================================
test_gemini_sync_assertions() {
    # Verify files synced
    assert_file_exists_in_volume "gemini/google_accounts.json" || return 1
    assert_file_exists_in_volume "gemini/oauth_creds.json" || return 1
    assert_file_exists_in_volume "gemini/settings.json" || return 1
    assert_file_exists_in_volume "gemini/GEMINI.md" || return 1

    # Verify secret file permissions (fso = file, secret, optional)
    assert_permissions_in_volume "gemini/google_accounts.json" "600" || return 1
    assert_permissions_in_volume "gemini/oauth_creds.json" "600" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "gemini/google_accounts.json" "GEMINI_ACCOUNTS_MARKER" || return 1
    assert_content_marker_in_volume "gemini/oauth_creds.json" "GEMINI_OAUTH_MARKER" || return 1
    assert_content_marker_in_volume "gemini/settings.json" "GEMINI_SETTINGS_MARKER" || return 1
    assert_content_marker_in_volume "gemini/GEMINI.md" "GEMINI_MD_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 6: Aider (optional)
# ==============================================================================
# NOTE: Aider is an optional agent (o flag), so symlinks are NOT created by
# init.sh. We only verify volume content, not container symlinks.
test_aider_sync_assertions() {
    # Verify config files synced to volume
    assert_file_exists_in_volume "aider/aider.conf.yml" || return 1
    assert_file_exists_in_volume "aider/aider.model.settings.yml" || return 1

    # Verify secret permissions (fso = file, secret, optional)
    assert_permissions_in_volume "aider/aider.conf.yml" "600" || return 1
    assert_permissions_in_volume "aider/aider.model.settings.yml" "600" || return 1

    # NOTE: No symlink assertions - optional agents don't have symlinks created
    # by init.sh (they're not in link-spec.json)

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "aider/aider.conf.yml" "AIDER_CONF_MARKER" || return 1
    assert_content_marker_in_volume "aider/aider.model.settings.yml" "AIDER_MODEL_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 7: Continue (optional)
# ==============================================================================
test_continue_sync_assertions() {
    # Verify config files synced
    assert_file_exists_in_volume "continue/config.yaml" || return 1
    assert_file_exists_in_volume "continue/config.json" || return 1

    # Verify secret permissions (fso/fjso = secret)
    assert_permissions_in_volume "continue/config.yaml" "600" || return 1
    assert_permissions_in_volume "continue/config.json" "600" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "continue/config.yaml" "CONTINUE_YAML_MARKER" || return 1
    assert_content_marker_in_volume "continue/config.json" "CONTINUE_JSON_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 8: Cursor (optional)
# ==============================================================================
test_cursor_sync_assertions() {
    # Verify files and directories synced
    assert_file_exists_in_volume "cursor/mcp.json" || return 1
    assert_dir_exists_in_volume "cursor/rules" || return 1
    assert_dir_exists_in_volume "cursor/extensions" || return 1
    assert_file_exists_in_volume "cursor/rules/rule.mdc" || return 1
    assert_file_exists_in_volume "cursor/extensions/ext.txt" || return 1

    # Verify secret permissions on mcp.json (fjso)
    assert_permissions_in_volume "cursor/mcp.json" "600" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "cursor/mcp.json" "CURSOR_MCP_MARKER" || return 1
    assert_content_marker_in_volume "cursor/rules/rule.mdc" "CURSOR_RULE_MARKER" || return 1
    assert_content_marker_in_volume "cursor/extensions/ext.txt" "CURSOR_EXTENSION_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 9: Pi (optional)
# ==============================================================================
test_pi_sync_assertions() {
    # Verify config files synced
    assert_file_exists_in_volume "pi/settings.json" || return 1
    assert_file_exists_in_volume "pi/models.json" || return 1
    assert_file_exists_in_volume "pi/keybindings.json" || return 1

    # Verify .system/ excluded (x flag)
    if assert_path_exists_in_volume "pi/skills/.system" 2>/dev/null; then
        return 1  # .system/ should NOT exist
    fi

    # Verify custom skills synced
    assert_dir_exists_in_volume "pi/skills/custom" || return 1
    assert_dir_exists_in_volume "pi/extensions" || return 1
    assert_file_exists_in_volume "pi/extensions/ext.txt" || return 1

    # Verify secret permissions on models.json (fjso)
    assert_permissions_in_volume "pi/models.json" "600" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "pi/models.json" "PI_MODELS_MARKER" || return 1
    assert_content_marker_in_volume "pi/settings.json" "PI_SETTINGS_MARKER" || return 1
    assert_content_marker_in_volume "pi/keybindings.json" "PI_KEYBINDINGS_MARKER" || return 1
    assert_content_marker_in_volume "pi/skills/custom/user.json" "PI_SKILL_MARKER" || return 1
    assert_content_marker_in_volume "pi/extensions/ext.txt" "PI_EXTENSION_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 10: Kimi (optional)
# ==============================================================================
test_kimi_sync_assertions() {
    # Verify config files synced
    assert_file_exists_in_volume "kimi/config.toml" || return 1
    assert_file_exists_in_volume "kimi/mcp.json" || return 1

    # Verify secret permissions (fso/fjso)
    assert_permissions_in_volume "kimi/config.toml" "600" || return 1
    assert_permissions_in_volume "kimi/mcp.json" "600" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "kimi/config.toml" "KIMI_CONFIG_MARKER" || return 1
    assert_content_marker_in_volume "kimi/mcp.json" "KIMI_MCP_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 11: Profile-import placeholder behavior
# ==============================================================================
# Note: This tests that when importing from $HOME (profile import), secret
# credentials become placeholders rather than copying actual content.
# Profile import is triggered when HOME == source (no --from flag).
# This test uses run_agent_sync_test with --profile-import to test this path.

setup_profile_import_fixture() {
    create_fixture_home >/dev/null
    create_claude_fixture
}

# Profile import (HOME == source, no --from) should create placeholders for secrets
# This test verifies that credentials are NOT copied when doing profile import
test_profile_import_placeholder_assertions() {
    # Profile import should create credential file with proper permissions
    assert_file_exists_in_volume "claude/credentials.json" || return 1
    assert_permissions_in_volume "claude/credentials.json" "600" || return 1

    # But the content should NOT contain the actual secret marker (it's skipped in profile import)
    # The file should be empty or minimal placeholder, NOT the fixture's marker
    assert_no_content_marker_in_volume "claude/credentials.json" "CREDENTIALS_MARKER" || return 1

    return 0
}

# ==============================================================================
# Test 12: Optional agent missing = no target created
# ==============================================================================
setup_optional_missing_fixture() {
    create_fixture_home >/dev/null
    # Only create Claude, not any optional agents
    create_claude_fixture
}

test_optional_missing_assertions() {
    # Verify optional agent directories are NOT created when fixture missing
    if assert_path_exists_in_volume "pi" 2>/dev/null; then
        return 1  # Pi dir should NOT exist when fixture missing
    fi

    if assert_path_exists_in_volume "kimi" 2>/dev/null; then
        return 1  # Kimi dir should NOT exist when fixture missing
    fi

    if assert_path_exists_in_volume "copilot" 2>/dev/null; then
        return 1  # Copilot dir should NOT exist when fixture missing
    fi

    if assert_path_exists_in_volume "gemini" 2>/dev/null; then
        return 1  # Gemini dir should NOT exist when fixture missing
    fi

    if assert_path_exists_in_volume "aider" 2>/dev/null; then
        return 1  # Aider dir should NOT exist when fixture missing
    fi

    if assert_path_exists_in_volume "continue" 2>/dev/null; then
        return 1  # Continue dir should NOT exist when fixture missing
    fi

    if assert_path_exists_in_volume "cursor" 2>/dev/null; then
        return 1  # Cursor dir should NOT exist when fixture missing
    fi

    # Claude should exist (non-optional)
    assert_dir_exists_in_volume "claude" || return 1

    return 0
}

# ==============================================================================
# Main Test Execution
# ==============================================================================
main() {
    sync_test_section "AI Agent Sync Tests"
    sync_test_info "Run ID: $SYNC_TEST_RUN_ID"

    # Test 1: Claude Code
    run_agent_sync_test "claude-sync" create_claude_fixture test_claude_sync_assertions

    # Test 2: OpenCode
    run_agent_sync_test "opencode-sync" create_opencode_fixture test_opencode_sync_assertions

    # Test 3: Codex
    run_agent_sync_test "codex-sync" create_codex_fixture test_codex_sync_assertions

    # Test 4: Copilot
    run_agent_sync_test "copilot-sync" create_copilot_fixture test_copilot_sync_assertions

    # Test 5: Gemini
    run_agent_sync_test "gemini-sync" create_gemini_fixture test_gemini_sync_assertions

    # Test 6: Aider
    run_agent_sync_test "aider-sync" create_aider_fixture test_aider_sync_assertions

    # Test 7: Continue
    run_agent_sync_test "continue-sync" create_continue_fixture test_continue_sync_assertions

    # Test 8: Cursor
    run_agent_sync_test "cursor-sync" create_cursor_fixture test_cursor_sync_assertions

    # Test 9: Pi
    run_agent_sync_test "pi-sync" create_pi_fixture test_pi_sync_assertions

    # Test 10: Kimi
    run_agent_sync_test "kimi-sync" create_kimi_fixture test_kimi_sync_assertions

    # Test 11: Profile-import placeholder behavior (uses --profile-import flag)
    run_agent_sync_test "profile-import" setup_profile_import_fixture test_profile_import_placeholder_assertions --profile-import

    # Test 12: Optional agent missing = no target created
    run_agent_sync_test "optional-missing" setup_optional_missing_fixture test_optional_missing_assertions

    sync_test_section "Summary"
    if [[ $SYNC_TEST_FAILED -eq 0 ]]; then
        sync_test_info "All AI agent sync tests passed"
        exit 0
    else
        sync_test_info "Some AI agent sync tests failed"
        exit 1
    fi
}

main "$@"
