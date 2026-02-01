#!/usr/bin/env bash
# ==============================================================================
# Sync E2E Tests for ContainAI
# ==============================================================================
# Comprehensive end-to-end tests for the sync system. Tests validate that
# `cai import` works correctly for all agents/tools defined in sync-manifest.toml.
#
# Tests run from user perspective: build container, use `--from <mock-home>`
# to import test fixtures, verify sync behavior.
#
# Usage:
#   ./tests/integration/test-sync-e2e.sh           # Run all tests
#   ./tests/integration/test-sync-e2e.sh --only agents   # Run agent tests only
#   ./tests/integration/test-sync-e2e.sh --only shell    # Run shell tests only
#   ./tests/integration/test-sync-e2e.sh --only flags    # Run flag tests only
#   ./tests/integration/test-sync-e2e.sh --only tools    # Run tool tests only
#   ./tests/integration/test-sync-e2e.sh --only edge     # Run edge case tests only
#
# Prerequisites:
#   - Docker daemon running
#   - Test image built: ./src/build.sh
#
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source test helpers
source "$SCRIPT_DIR/sync-test-helpers.sh"

# ==============================================================================
# Command Line Argument Parsing
# ==============================================================================
RUN_ONLY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --only)
            if [[ $# -lt 2 ]]; then
                printf '%s\n' "Error: --only requires a value (agents|shell|flags|tools|edge)" >&2
                printf '%s\n' "Usage: $0 [--only agents|shell|flags|tools|edge]" >&2
                exit 1
            fi
            RUN_ONLY="$2"
            shift 2
            ;;
        --help|-h)
            printf '%s\n' "Usage: $0 [--only agents|shell|flags|tools|edge]"
            printf '%s\n' ""
            printf '%s\n' "Options:"
            printf '%s\n' "  --only agents   Run only AI agent sync tests"
            printf '%s\n' "  --only shell    Run only shell customization tests"
            printf '%s\n' "  --only flags    Run only flag behavior tests"
            printf '%s\n' "  --only tools    Run only dev tool sync tests"
            printf '%s\n' "  --only edge     Run only edge case tests"
            exit 0
            ;;
        *)
            printf '%s\n' "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ==============================================================================
# Early Guards
# ==============================================================================
docker_status=0
check_docker_available || docker_status=$?
if [[ "$docker_status" == "2" ]]; then
    # Docker binary not found - skip
    exit 0
elif [[ "$docker_status" != "0" ]]; then
    # Docker daemon not running - fail
    exit 1
fi

if ! check_test_image; then
    exit 1
fi

# ==============================================================================
# Test Setup
# ==============================================================================
setup_cleanup_trap

# Initialize fixture home (volume created per-test for isolation)
init_fixture_home >/dev/null

sync_test_info "Fixture home: $SYNC_TEST_FIXTURE_HOME"
sync_test_info "Test image: $SYNC_TEST_IMAGE_NAME"

# Test counter for unique volume names
SYNC_TEST_COUNTER=0

# ==============================================================================
# Helper to run a test with a fresh container and volume
# ==============================================================================
# Creates fixture, imports, starts container, runs test function, cleans up
# Each test gets its own fresh volume for isolation
# Usage: run_sync_test NAME SETUP_FN TEST_FN [--skip-import] [--profile-import]
run_sync_test() {
    local test_name="$1"
    local setup_fn="$2"
    local test_fn="$3"
    shift 3
    local skip_import=false
    local profile_import=false

    # Parse optional flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-import) skip_import=true; shift ;;
            --profile-import) profile_import=true; shift ;;
            *) shift ;;
        esac
    done

    local import_output import_exit=0

    # Create fresh volume for this test (isolation)
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "sync-data-${SYNC_TEST_COUNTER}")

    # Create unique container for this test (use tail -f for portable keepalive)
    create_test_container "$test_name" \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

    # Set up fixture
    if [[ -n "$setup_fn" ]]; then
        "$setup_fn"
    fi

    # Run import unless skipped
    if [[ "$skip_import" != "true" ]]; then
        if [[ "$profile_import" == "true" ]]; then
            import_output=$(run_cai_import_profile 2>&1) || import_exit=$?
        else
            import_output=$(run_cai_import_from 2>&1) || import_exit=$?
        fi
        if [[ $import_exit -ne 0 ]]; then
            sync_test_fail "$test_name: import failed (exit=$import_exit)"
            printf '%s\n' "$import_output" | head -20 >&2
            # Clean up fixture (including dotfiles)
            find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
            # Clean up this test's volume
            "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true
            return
        fi
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

    # Clear fixture for next test (including dotfiles)
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# AI Agent Sync Tests
# ==============================================================================
test_agents() {
    sync_test_section "AI Agent Sync Tests"

    # Test 1: Claude Code sync
    run_sync_test "claude-sync" create_claude_fixture test_claude_sync_assertions

    # Test 2: OpenCode sync (auth.json at ~/.local/share/opencode/)
    run_sync_test "opencode-sync" create_opencode_fixture test_opencode_sync_assertions

    # Test 3: Codex sync (x flag excludes .system/)
    run_sync_test "codex-sync" create_codex_fixture test_codex_sync_assertions

    # Test 4: Copilot sync (optional, not secret)
    run_sync_test "copilot-sync" create_copilot_fixture test_copilot_sync_assertions

    # Test 5: Gemini sync (optional)
    run_sync_test "gemini-sync" create_gemini_fixture test_gemini_sync_assertions

    # Test 6: Aider sync (optional)
    run_sync_test "aider-sync" create_aider_fixture test_aider_sync_assertions

    # Test 7: Continue sync (optional)
    run_sync_test "continue-sync" create_continue_fixture test_continue_sync_assertions

    # Test 8: Cursor sync (optional)
    run_sync_test "cursor-sync" create_cursor_fixture test_cursor_sync_assertions

    # Test 9: Pi sync (optional)
    run_sync_test "pi-sync" create_pi_fixture test_pi_sync_assertions

    # Test 10: Kimi sync (optional)
    run_sync_test "kimi-sync" create_kimi_fixture test_kimi_sync_assertions

    # Test 11: Profile-import placeholder behavior (uses --profile-import flag)
    run_sync_test "profile-import" create_claude_fixture test_profile_import_assertions --profile-import

    # Test 12: Optional agent missing = no target created
    run_sync_test "optional-missing" setup_optional_missing_fixture test_optional_missing_assertions
}

# --- Claude Code ---
test_claude_sync_assertions() {
    # Verify files synced to volume
    assert_file_exists_in_volume "claude/claude.json" || return 1
    assert_file_exists_in_volume "claude/credentials.json" || return 1
    assert_file_exists_in_volume "claude/settings.json" || return 1
    assert_file_exists_in_volume "claude/settings.local.json" || return 1
    assert_dir_exists_in_volume "claude/plugins" || return 1
    assert_file_exists_in_volume "claude/plugins/cache/test-plugin/plugin.json" || return 1
    assert_file_exists_in_volume "claude/CLAUDE.md" || return 1

    # Verify symlinks exist in container
    assert_is_symlink "/home/agent/.claude.json" || return 1
    assert_is_symlink "/home/agent/.claude/settings.json" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "claude/credentials.json" "CREDENTIALS_MARKER" || return 1
    assert_content_marker_in_volume "claude/claude.json" "CLAUDE_JSON_MARKER" || return 1
    assert_content_marker_in_volume "claude/settings.json" "SETTINGS_MARKER" || return 1
    assert_content_marker_in_volume "claude/settings.local.json" "SETTINGS_LOCAL_MARKER" || return 1

    return 0
}

# --- OpenCode (auth.json at ~/.local/share/opencode/) ---
test_opencode_sync_assertions() {
    # Verify config directory entries synced
    assert_file_exists_in_volume "config/opencode/opencode.json" || return 1
    assert_file_exists_in_volume "config/opencode/instructions.md" || return 1
    assert_dir_exists_in_volume "config/opencode/agents" || return 1
    assert_dir_exists_in_volume "config/opencode/commands" || return 1
    assert_dir_exists_in_volume "config/opencode/skills" || return 1
    assert_dir_exists_in_volume "config/opencode/modes" || return 1
    assert_dir_exists_in_volume "config/opencode/plugins" || return 1

    # Verify auth.json at different path (~/.local/share/opencode/)
    assert_file_exists_in_volume "local/share/opencode/auth.json" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "local/share/opencode/auth.json" "OPENCODE_AUTH_MARKER" || return 1
    assert_content_marker_in_volume "config/opencode/opencode.json" "OPENCODE_CONFIG_MARKER" || return 1

    return 0
}

# --- Codex (x flag excludes .system/) ---
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

    return 0
}

# --- Copilot (optional, not secret) ---
test_copilot_sync_assertions() {
    # Verify config files synced
    assert_file_exists_in_volume "copilot/config.json" || return 1
    assert_file_exists_in_volume "copilot/mcp-config.json" || return 1
    assert_dir_exists_in_volume "copilot/skills" || return 1

    # Verify symlinks in container
    assert_is_symlink "/home/agent/.copilot/config.json" || return 1
    assert_is_symlink "/home/agent/.copilot/mcp-config.json" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "copilot/config.json" "COPILOT_CONFIG_MARKER" || return 1
    assert_content_marker_in_volume "copilot/mcp-config.json" "COPILOT_MCP_MARKER" || return 1

    return 0
}

# --- Gemini (optional) ---
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

    return 0
}

# --- Aider (optional) ---
test_aider_sync_assertions() {
    # Verify config files synced (at root ~/)
    assert_file_exists_in_volume "aider/aider.conf.yml" || return 1
    assert_file_exists_in_volume "aider/aider.model.settings.yml" || return 1

    # Verify secret permissions (fso = file, secret, optional)
    assert_permissions_in_volume "aider/aider.conf.yml" "600" || return 1
    assert_permissions_in_volume "aider/aider.model.settings.yml" "600" || return 1

    # Verify symlinks at root
    assert_is_symlink "/home/agent/.aider.conf.yml" || return 1
    assert_is_symlink "/home/agent/.aider.model.settings.yml" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "aider/aider.conf.yml" "AIDER_CONF_MARKER" || return 1
    assert_content_marker_in_volume "aider/aider.model.settings.yml" "AIDER_MODEL_MARKER" || return 1

    return 0
}

# --- Continue (optional) ---
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

# --- Cursor (optional) ---
test_cursor_sync_assertions() {
    # Verify files and directories synced
    assert_file_exists_in_volume "cursor/mcp.json" || return 1
    assert_dir_exists_in_volume "cursor/rules" || return 1
    assert_dir_exists_in_volume "cursor/extensions" || return 1

    # Verify secret permissions on mcp.json (fjso)
    assert_permissions_in_volume "cursor/mcp.json" "600" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "cursor/mcp.json" "CURSOR_MCP_MARKER" || return 1

    return 0
}

# --- Pi (optional) ---
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

    # Verify secret permissions on models.json (fjso)
    assert_permissions_in_volume "pi/models.json" "600" || return 1

    # Verify content synced correctly (full content with --from, not placeholders)
    assert_content_marker_in_volume "pi/models.json" "PI_MODELS_MARKER" || return 1

    return 0
}

# --- Kimi (optional) ---
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

# --- Profile-import placeholder behavior ---
# Profile import (HOME == source, no --from) should create placeholders for secrets
# This test verifies that credentials are NOT copied when doing profile import
test_profile_import_assertions() {
    # Profile import should create credential file with proper permissions
    assert_file_exists_in_volume "claude/credentials.json" || return 1
    assert_permissions_in_volume "claude/credentials.json" "600" || return 1

    # But the content should NOT contain the actual secret marker (it's skipped in profile import)
    # The file should be empty or minimal placeholder, NOT the fixture's marker
    assert_no_content_marker_in_volume "claude/credentials.json" "CREDENTIALS_MARKER" || return 1

    return 0
}

# --- Optional agent missing = no target created ---
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
# Dev Tool Sync Tests
# ==============================================================================
test_tools() {
    sync_test_section "Dev Tool Sync Tests"

    # Test: Git config with g-filter
    run_sync_test "git-filter" create_git_fixture test_git_filter_assertions

    # Test: GitHub CLI sync (secret separation)
    run_sync_test "gh-sync" create_gh_fixture test_gh_sync_assertions
}

test_git_filter_assertions() {
    # Verify .gitconfig synced
    assert_file_exists_in_volume "git/gitconfig" || return 1

    # Verify credential.helper was stripped (g flag)
    if cat_from_volume "git/gitconfig" | grep -q "credential"; then
        return 1  # Should NOT contain credential.helper
    fi

    # Verify gpgsign was stripped
    if cat_from_volume "git/gitconfig" | grep -q "gpgsign"; then
        return 1  # Should NOT contain gpgsign
    fi

    # Verify alias preserved
    if ! cat_from_volume "git/gitconfig" | grep -q "alias"; then
        return 1  # Should contain alias section
    fi

    # Verify gitignore_global synced
    assert_file_exists_in_volume "git/gitignore_global" || return 1

    return 0
}

test_gh_sync_assertions() {
    # Verify hosts.yml synced
    assert_file_exists_in_volume "config/gh/hosts.yml" || return 1

    # Verify config.yml synced
    assert_file_exists_in_volume "config/gh/config.yml" || return 1

    return 0
}

# ==============================================================================
# Shell Customization Tests
# ==============================================================================
test_shell() {
    sync_test_section "Shell Customization Tests"

    # Test: Shell config sync
    run_sync_test "shell-sync" create_shell_fixture test_shell_sync_assertions
}

test_shell_sync_assertions() {
    # Verify bash_aliases synced
    assert_file_exists_in_volume "shell/bash_aliases" || return 1

    # Verify bashrc.d synced
    assert_dir_exists_in_volume "shell/bashrc.d" || return 1
    assert_file_exists_in_volume "shell/bashrc.d/test.sh" || return 1

    # Verify priv filter: *.priv.* files should NOT be synced
    if assert_file_exists_in_volume "shell/bashrc.d/secret.priv.sh" 2>/dev/null; then
        return 1  # Should NOT exist - priv filter should exclude it
    fi

    # Verify inputrc synced
    assert_file_exists_in_volume "shell/inputrc" || return 1

    # Verify symlink points to correct location
    assert_is_symlink "/home/agent/.bash_aliases_imported" || return 1

    # Verify .bashrc.d scripts are sourced (check TEST_VAR is set in interactive shell)
    local test_var_output
    test_var_output=$(exec_in_container "$SYNC_TEST_CONTAINER" bash -i -c 'echo "$TEST_VAR"' 2>/dev/null || true)
    if [[ "$test_var_output" != "from_bashrc_d" ]]; then
        # Container bashrc must source /mnt/agent-data/shell/bashrc.d for this to work
        return 1  # TEST_VAR should be set from bashrc.d/test.sh
    fi

    return 0
}

# ==============================================================================
# Flag Behavior Tests
# ==============================================================================
test_flags() {
    sync_test_section "Flag Behavior Tests"

    # Test: Secret permissions (s flag)
    run_sync_test "secret-perms" create_claude_fixture test_secret_permissions_assertions

    # Test: JSON init (j flag) - handled by testing empty file behavior
    run_sync_test "json-init" setup_json_init_fixture test_json_init_assertions

    # Test: Exclude .system (x flag)
    run_sync_test "exclude-system" create_codex_fixture test_exclude_system_assertions
}

setup_json_init_fixture() {
    create_fixture_home >/dev/null
    mkdir -p "$SYNC_TEST_FIXTURE_HOME/.claude"
    # Create empty settings.json (should become {} after import)
    : > "$SYNC_TEST_FIXTURE_HOME/.claude/settings.json"
}

test_secret_permissions_assertions() {
    # Verify secret files have 600 permissions
    assert_permissions_in_volume "claude/credentials.json" "600" || return 1

    return 0
}

test_json_init_assertions() {
    # Verify settings.json contains {} (json-init for empty file)
    local content
    content=$(cat_from_volume "claude/settings.json" | tr -d '[:space:]')
    if [[ "$content" != "{}" ]]; then
        return 1
    fi

    return 0
}

test_exclude_system_assertions() {
    # Verify .system/ was excluded
    if assert_path_exists_in_volume "codex/skills/.system" 2>/dev/null; then
        return 1  # Should NOT exist
    fi

    # Verify other skills synced
    assert_dir_exists_in_volume "codex/skills/custom" || return 1

    return 0
}

# ==============================================================================
# Edge Case Tests
# ==============================================================================
test_edge() {
    sync_test_section "Edge Case Tests"

    # Test: Optional entries don't create empty dirs when missing
    run_sync_test "no-pollution" setup_no_pollution_fixture test_no_pollution_assertions

    # Test: Dry-run doesn't modify volume (skip default import, run dry-run inside test)
    run_sync_test "dry-run" create_claude_fixture test_dry_run_assertions --skip-import
}

setup_no_pollution_fixture() {
    create_fixture_home >/dev/null
    # Only create Claude, not optional agents like Pi/Kimi
    create_claude_fixture
}

test_no_pollution_assertions() {
    # Verify optional agent directories are NOT created
    if assert_path_exists_in_volume "pi" 2>/dev/null; then
        return 1  # Pi dir should NOT exist when fixture missing
    fi

    if assert_path_exists_in_volume "kimi" 2>/dev/null; then
        return 1  # Kimi dir should NOT exist when fixture missing
    fi

    # Claude should exist
    assert_dir_exists_in_volume "claude" || return 1

    return 0
}

test_dry_run_assertions() {
    # Test dry-run: verify DRY-RUN markers appear and volume remains empty
    # Volume should be fresh and empty since we used --skip-import

    # Verify volume is initially empty (no claude directory yet)
    if assert_path_exists_in_volume "claude" 2>/dev/null; then
        return 1  # Volume should be empty before dry-run
    fi

    # Run dry-run import
    local output
    output=$(run_cai_import_from --dry-run 2>&1) || true

    # Should contain DRY-RUN markers
    if ! printf '%s' "$output" | grep -q "DRY-RUN"; then
        return 1  # Should contain DRY-RUN markers
    fi

    # Volume should STILL be empty after dry-run (no actual changes)
    if assert_path_exists_in_volume "claude" 2>/dev/null; then
        return 1  # Dry-run should NOT create files
    fi

    return 0
}

# ==============================================================================
# Main Test Execution
# ==============================================================================
main() {
    sync_test_section "Sync E2E Tests"
    sync_test_info "Run ID: $SYNC_TEST_RUN_ID"

    case "${RUN_ONLY:-}" in
        agents)
            test_agents
            ;;
        tools)
            test_tools
            ;;
        shell)
            test_shell
            ;;
        flags)
            test_flags
            ;;
        edge)
            test_edge
            ;;
        "")
            # Run all tests
            test_agents
            test_tools
            test_shell
            test_flags
            test_edge
            ;;
        *)
            sync_test_fail "Unknown test category: $RUN_ONLY"
            exit 1
            ;;
    esac

    sync_test_section "Summary"
    if [[ $SYNC_TEST_FAILED -eq 0 ]]; then
        sync_test_info "All tests passed"
        exit 0
    else
        sync_test_info "Some tests failed"
        exit 1
    fi
}

main "$@"
