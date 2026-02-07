#!/usr/bin/env bash
# ==============================================================================
# Dev Tool Sync Tests
# ==============================================================================
# Tests sync for dev tools: Git (with g-filter), GitHub CLI (secret separation),
# SSH (disabled/additional_paths), VS Code, tmux, vim/neovim, Starship, Oh My Posh.
#
# Usage:
#   ./tests/integration/sync-tests/test-tool-sync.sh
#
# Prerequisites:
#   - Docker daemon running
#   - Test image built: dotnet msbuild src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make tests hermetic: clear config discovery inputs to prevent developer's
# real config (e.g., ~/.config/containai/containai.toml) from affecting tests.
# This prevents issues like additional_paths=["~/.ssh"] in user's config
# breaking the ssh-disabled test.
unset XDG_CONFIG_HOME 2>/dev/null || true
# Also unset git-related env vars that _cai_import_git_config honors
unset GIT_CONFIG_GLOBAL 2>/dev/null || true

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
# Usage: run_tool_sync_test NAME SETUP_FN TEST_FN [extra_import_args...]
run_tool_sync_test() {
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
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "tool-data-${SYNC_TEST_COUNTER}")

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
    if [[ ${#extra_import_args[@]} -gt 0 ]]; then
        import_output=$(run_cai_import_from "${extra_import_args[@]}" 2>&1) || import_exit=$?
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

# Special helper for git test that uses profile import (HOME == fixture)
# This is needed because _cai_import_git_config reads from $HOME, not --from
# Note: Does not support extra_import_args (profile import has fixed args)
run_git_sync_test() {
    local test_name="$1"
    local setup_fn="$2"
    local test_fn="$3"
    # No extra args - profile import mode has fixed behavior

    local import_output import_exit=0

    # Create fresh volume for this test (isolation)
    SYNC_TEST_COUNTER=$((SYNC_TEST_COUNTER + 1))
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "tool-data-${SYNC_TEST_COUNTER}")

    # Create unique container for this test
    # Override entrypoint to bypass systemd (which requires Sysbox)
    create_test_container "$test_name" \
        --entrypoint /bin/bash \
        --volume "$SYNC_TEST_DATA_VOLUME:/mnt/agent-data" \
        "$SYNC_TEST_IMAGE_NAME" -c "tail -f /dev/null" >/dev/null

    # Set up fixture
    if [[ -n "$setup_fn" ]]; then
        "$setup_fn"
    fi

    # Run import using PROFILE mode (HOME == fixture) so _cai_import_git_config
    # reads the fixture's .gitconfig
    import_output=$(run_cai_import_profile 2>&1) || import_exit=$?
    if [[ $import_exit -ne 0 ]]; then
        sync_test_fail "$test_name: import failed (exit=$import_exit)"
        printf '%s\n' "$import_output" | head -20 >&2
        find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
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

    # Clean up
    "${DOCKER_CMD[@]}" rm -f "test-${test_name}-${SYNC_TEST_RUN_ID}" 2>/dev/null || true
    "${DOCKER_CMD[@]}" volume rm "$SYNC_TEST_DATA_VOLUME" 2>/dev/null || true

    # Clear fixture for next test
    find "${SYNC_TEST_FIXTURE_HOME:?}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
}

# ==============================================================================
# Test 1: Git g-filter - credential.helper stripped
# ==============================================================================
# NOTE: _cai_import_git_config reads from $HOME, not from the --from source.
# For the git filter test, we use profile import mode (HOME == fixture)
# so that the gitconfig in the fixture is the one being imported.
setup_git_filter_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"

    cat >"$fixture/.gitconfig" <<'EOF'
[user]
    name = Test User
    email = test@example.com
[credential]
    helper = osxkeychain
[commit]
    gpgsign = true
[gpg]
    program = /usr/local/bin/gpg
    format = ssh
[user]
    signingkey = ~/.ssh/id_ed25519.pub
[tag]
    gpgsign = true
[alias]
    co = checkout
    st = status
[core]
    editor = vim
EOF

    # Also create .gitignore_global (listed in spec's Tools to Test)
    printf '%s\n' '# Global gitignore - GITIGNORE_MARKER' >"$fixture/.gitignore_global"
    printf '%s\n' '*.log' >>"$fixture/.gitignore_global"
    printf '%s\n' '.DS_Store' >>"$fixture/.gitignore_global"
}

test_git_filter_assertions() {
    # Verify gitconfig synced to volume
    assert_file_exists_in_volume "git/gitconfig" || return 1

    # Read the synced gitconfig
    local gitconfig
    gitconfig=$(cat_from_volume "git/gitconfig") || return 1

    # Verify user identity preserved (name = Test User)
    if [[ "$gitconfig" != *"name = Test User"* ]]; then
        printf '%s\n' "[DEBUG] gitconfig does not contain 'name = Test User'" >&2
        printf '%s\n' "$gitconfig" >&2
        return 1
    fi

    # Verify email preserved
    if [[ "$gitconfig" != *"email = test@example.com"* ]]; then
        printf '%s\n' "[DEBUG] gitconfig does not contain email" >&2
        return 1
    fi

    # Verify alias preserved
    if [[ "$gitconfig" != *"co = checkout"* ]]; then
        printf '%s\n' "[DEBUG] gitconfig does not contain alias" >&2
        return 1
    fi

    # Verify credential.helper stripped (case-insensitive)
    local gitconfig_lower
    gitconfig_lower=$(printf '%s' "$gitconfig" | tr '[:upper:]' '[:lower:]')
    if [[ "$gitconfig_lower" == *"credential"*"helper"* ]]; then
        printf '%s\n' "[DEBUG] gitconfig still contains credential.helper" >&2
        return 1
    fi

    # Verify gpgsign stripped
    if [[ "$gitconfig_lower" == *"gpgsign"* ]]; then
        printf '%s\n' "[DEBUG] gitconfig still contains gpgsign" >&2
        return 1
    fi

    # Verify gpg.program stripped
    if [[ "$gitconfig_lower" == *"gpg"*"program"* ]]; then
        printf '%s\n' "[DEBUG] gitconfig still contains gpg.program" >&2
        return 1
    fi

    # Verify gpg.format stripped
    if [[ "$gitconfig_lower" == *"gpg"*"format"* ]]; then
        # Check if it's gpg.format = ssh (not just any format mention)
        if [[ "$gitconfig_lower" == *"format = ssh"* ]] || [[ "$gitconfig_lower" == *"format=ssh"* ]]; then
            printf '%s\n' "[DEBUG] gitconfig still contains gpg.format" >&2
            return 1
        fi
    fi

    # Verify signingkey stripped
    if [[ "$gitconfig_lower" == *"signingkey"* ]]; then
        printf '%s\n' "[DEBUG] gitconfig still contains signingkey" >&2
        return 1
    fi

    # Verify safe.directory added - check for actual [safe] section and the directory line
    if [[ "$gitconfig" != *"[safe]"* ]]; then
        printf '%s\n' "[DEBUG] gitconfig does not contain [safe] section" >&2
        return 1
    fi
    if [[ "$gitconfig" != *"directory = /home/agent/workspace"* ]] && [[ "$gitconfig" != *"directory=/home/agent/workspace"* ]]; then
        printf '%s\n' "[DEBUG] gitconfig does not contain safe.directory = /home/agent/workspace" >&2
        return 1
    fi

    # Verify .gitignore_global synced (listed in spec's Tools to Test)
    assert_file_exists_in_volume "git/gitignore_global" || {
        printf '%s\n' "[DEBUG] git/gitignore_global does not exist in volume" >&2
        return 1
    }
    local gitignore_content
    gitignore_content=$(cat_from_volume "git/gitignore_global") || return 1
    if [[ "$gitignore_content" != *"GITIGNORE_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] gitignore_global does not contain expected marker" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 2: GitHub CLI secret separation (hosts.yml vs config.yml)
# ==============================================================================
setup_gh_secret_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.config/gh"

    printf '%s\n' 'github.com:' >"$fixture/.config/gh/hosts.yml"
    printf '%s\n' '  oauth_token: test-token' >>"$fixture/.config/gh/hosts.yml"
    # Set source to non-secret mode (644) so we can verify the IMPORTER enforces 600
    # If we set source to 600, rsync -a would preserve it and we wouldn't test
    # that the import logic correctly applies secret permissions
    chmod 644 "$fixture/.config/gh/hosts.yml"

    printf '%s\n' 'editor: vim' >"$fixture/.config/gh/config.yml"
    # Non-secret file - set to 644 but we'll only verify it's not 600 in volume
    chmod 644 "$fixture/.config/gh/config.yml"
}

test_gh_secret_separation_assertions() {
    # Both should sync with --from
    assert_file_exists_in_volume "config/gh/hosts.yml" || return 1
    assert_file_exists_in_volume "config/gh/config.yml" || return 1

    # hosts.yml should have 600 perms (secret) - the IMPORTER must enforce this
    # even though the source file is 644 (set in fixture to test enforcement)
    assert_permissions_in_volume "config/gh/hosts.yml" "600" || return 1

    # config.yml should NOT have secret permissions (600)
    # We don't assert exact mode (644) because permissions may vary across platforms/filesystems
    local config_perms
    config_perms=$(exec_in_container "$SYNC_TEST_CONTAINER" stat -c '%a' "/mnt/agent-data/config/gh/config.yml") || {
        printf '%s\n' "[DEBUG] Failed to get config.yml permissions" >&2
        return 1
    }
    if [[ "$config_perms" == "600" ]]; then
        printf '%s\n' "[DEBUG] config.yml has 600 perms but should not (not a secret)" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 3: GitHub CLI --no-secrets skips hosts.yml but keeps config.yml
# ==============================================================================
test_gh_no_secrets_assertions() {
    # With --no-secrets, hosts.yml should not have content from import
    # Note: init.sh creates empty placeholder files, so we check for content not existence
    local hosts_content
    hosts_content=$(cat_from_volume "config/gh/hosts.yml" 2>/dev/null) || hosts_content=""
    if [[ -n "$hosts_content" ]]; then
        printf '%s\n' "[DEBUG] hosts.yml has content but should be empty with --no-secrets" >&2
        printf '%s\n' "[DEBUG] Content: $hosts_content" >&2
        return 1
    fi

    # config.yml should still sync (not secret) - check it has content
    assert_file_exists_in_volume "config/gh/config.yml" || return 1
    local config_content
    config_content=$(cat_from_volume "config/gh/config.yml") || return 1
    if [[ -z "$config_content" ]]; then
        printf '%s\n' "[DEBUG] config.yml should have content but is empty" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 4: SSH disabled by default
# ==============================================================================
setup_ssh_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.ssh"

    printf '%s\n' 'Host *' >"$fixture/.ssh/config"
    printf '%s\n' '    StrictHostKeyChecking no' >>"$fixture/.ssh/config"
    printf '%s\n' 'github.com ssh-ed25519 AAAA...' >"$fixture/.ssh/known_hosts"
    # Create fake key files for testing - use non-key-looking content to avoid
    # triggering security scanners that look for SSH key headers
    printf '%s\n' 'TEST_PRIVATE_KEY_MARKER_START' >"$fixture/.ssh/id_ed25519"
    printf '%s\n' 'fake test key content for testing purposes only' >>"$fixture/.ssh/id_ed25519"
    printf '%s\n' 'TEST_PRIVATE_KEY_MARKER_END' >>"$fixture/.ssh/id_ed25519"
    printf '%s\n' 'ssh-ed25519 AAAA... test@example.com' >"$fixture/.ssh/id_ed25519.pub"
}

test_ssh_disabled_assertions() {
    # SSH should NOT be synced by default (disabled=true in manifest)
    # Note: init.sh creates empty placeholder files for symlinks to work, so we check content not existence
    local ssh_config_content
    ssh_config_content=$(cat_from_volume "ssh/config" 2>/dev/null) || ssh_config_content=""
    if [[ -n "$ssh_config_content" ]]; then
        printf '%s\n' "[DEBUG] ssh/config has content but SSH is disabled by default" >&2
        printf '%s\n' "[DEBUG] Content: $ssh_config_content" >&2
        return 1
    fi

    local known_hosts_content
    known_hosts_content=$(cat_from_volume "ssh/known_hosts" 2>/dev/null) || known_hosts_content=""
    if [[ -n "$known_hosts_content" ]]; then
        printf '%s\n' "[DEBUG] ssh/known_hosts has content but SSH is disabled by default" >&2
        printf '%s\n' "[DEBUG] Content: $known_hosts_content" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 5: SSH via additional_paths opt-in
# ==============================================================================
setup_ssh_additional_paths_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.ssh"

    printf '%s\n' 'Host *' >"$fixture/.ssh/config"
    printf '%s\n' '    StrictHostKeyChecking no' >>"$fixture/.ssh/config"
    printf '%s\n' 'github.com ssh-ed25519 AAAA...' >"$fixture/.ssh/known_hosts"
    # Create fake key files for testing - use non-key-looking content to avoid
    # triggering security scanners that look for SSH key headers
    printf '%s\n' 'TEST_PRIVATE_KEY_MARKER_START' >"$fixture/.ssh/id_ed25519"
    printf '%s\n' 'fake test key content for testing purposes only' >>"$fixture/.ssh/id_ed25519"
    printf '%s\n' 'TEST_PRIVATE_KEY_MARKER_END' >>"$fixture/.ssh/id_ed25519"
    printf '%s\n' 'ssh-ed25519 AAAA... test@example.com' >"$fixture/.ssh/id_ed25519.pub"

    # Create containai.toml with additional_paths to opt-in SSH
    mkdir -p "$fixture/.config/containai"
    cat >"$fixture/.config/containai/containai.toml" <<'EOF'
[import]
additional_paths = ["~/.ssh"]
EOF
}

test_ssh_additional_paths_assertions() {
    # SSH should now be synced since it's in additional_paths
    assert_dir_exists_in_volume "ssh" || return 1
    assert_file_exists_in_volume "ssh/config" || return 1
    assert_file_exists_in_volume "ssh/known_hosts" || return 1
    # Note: id_* files may or may not sync depending on glob handling
    # The important test is that the ssh directory syncs at all

    return 0
}

# Helper for additional_paths tests that need --config
run_tool_sync_test_with_config() {
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
    SYNC_TEST_DATA_VOLUME=$(create_test_volume "tool-data-${SYNC_TEST_COUNTER}")

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

    # Run import WITH --config pointing to fixture's config
    local config_path="${SYNC_TEST_FIXTURE_HOME}/.config/containai/containai.toml"
    if [[ -f "$config_path" ]]; then
        extra_import_args+=(--config "$config_path")
    fi

    if [[ ${#extra_import_args[@]} -gt 0 ]]; then
        import_output=$(run_cai_import_from "${extra_import_args[@]}" 2>&1) || import_exit=$?
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
# Test 6: --no-secrets does NOT affect additional_paths
# ==============================================================================
# When user explicitly adds paths via additional_paths, --no-secrets should NOT skip them
# This is by design: explicit user choice overrides secret filtering
test_no_secrets_keeps_additional_paths_assertions() {
    # Even with --no-secrets, additional_paths should still sync
    # SSH was added via additional_paths, so it should still be synced
    assert_dir_exists_in_volume "ssh" || return 1
    assert_file_exists_in_volume "ssh/config" || return 1

    # Crucially: secret files (private keys) should ALSO be synced because
    # additional_paths are an explicit user choice that overrides --no-secrets
    # This is the key assertion that validates the spec requirement
    assert_file_exists_in_volume "ssh/id_ed25519" || {
        printf '%s\n' "[DEBUG] ssh/id_ed25519 should exist - --no-secrets must not affect additional_paths" >&2
        return 1
    }

    return 0
}

# ==============================================================================
# Test 7 & 8: VS Code Server tests
# ==============================================================================
setup_vscode_empty_fixture() {
    # Don't create any VS Code files in fixture
    # This tests that directories are ensured even when source is missing
    create_fixture_home >/dev/null
    # Create a minimal Claude fixture to ensure import runs
    create_claude_fixture
}

test_vscode_ensures_targets_assertions() {
    # VS Code entries are non-optional d flags
    # Even when source is missing, targets should be ensured (empty dirs created)
    # This tests the ensure() behavior for non-optional directory entries

    # These directories should be ensured even when source is missing
    assert_dir_exists_in_volume "vscode-server/extensions" || {
        printf '%s\n' "[DEBUG] vscode-server/extensions should be ensured even when source missing" >&2
        return 1
    }
    assert_dir_exists_in_volume "vscode-server/data/Machine" || {
        printf '%s\n' "[DEBUG] vscode-server/data/Machine should be ensured even when source missing" >&2
        return 1
    }
    assert_dir_exists_in_volume "vscode-server/data/User/mcp" || {
        printf '%s\n' "[DEBUG] vscode-server/data/User/mcp should be ensured even when source missing" >&2
        return 1
    }
    assert_dir_exists_in_volume "vscode-server/data/User/prompts" || {
        printf '%s\n' "[DEBUG] vscode-server/data/User/prompts should be ensured even when source missing" >&2
        return 1
    }

    return 0
}

test_vscode_content_sync_assertions() {
    # Verify content synced correctly
    assert_dir_exists_in_volume "vscode-server/extensions" || return 1
    assert_file_exists_in_volume "vscode-server/extensions/test-ext/package.json" || return 1
    assert_dir_exists_in_volume "vscode-server/data/Machine" || return 1
    assert_file_exists_in_volume "vscode-server/data/Machine/settings.json" || return 1
    assert_dir_exists_in_volume "vscode-server/data/User/mcp" || return 1

    return 0
}

# ==============================================================================
# Test 9: tmux sync - verify XDG wins over legacy
# ==============================================================================
# Custom setup to verify XDG precedence: use distinct content in legacy vs XDG
setup_tmux_precedence_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.config/tmux"
    mkdir -p "$fixture/.local/share/tmux/plugins/tpm"

    # Legacy content with distinct marker
    printf '%s\n' '# LEGACY_TMUX_MARKER' >"$fixture/.tmux.conf"
    printf '%s\n' 'set -g prefix C-b' >>"$fixture/.tmux.conf"

    # XDG content with distinct marker - this should WIN when both exist
    printf '%s\n' '# XDG_TMUX_MARKER' >"$fixture/.config/tmux/tmux.conf"
    printf '%s\n' 'set -g prefix C-a' >>"$fixture/.config/tmux/tmux.conf"

    printf '%s\n' '# TPM' >"$fixture/.local/share/tmux/plugins/tpm/tpm"
}

test_tmux_sync_assertions() {
    # tmux.conf should exist in volume
    assert_file_exists_in_volume "config/tmux/tmux.conf" || return 1

    # Verify XDG wins over legacy: the XDG marker should be present
    # (XDG config syncs AFTER legacy, so it overwrites)
    local content
    content=$(cat_from_volume "config/tmux/tmux.conf") || return 1

    if [[ "$content" != *"XDG_TMUX_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] tmux.conf does not contain XDG_TMUX_MARKER - XDG should win over legacy" >&2
        printf '%s\n' "[DEBUG] Content: $content" >&2
        return 1
    fi

    # Legacy marker should NOT be present (XDG overwrites)
    if [[ "$content" == *"LEGACY_TMUX_MARKER"* ]]; then
        printf '%s\n' "[DEBUG] tmux.conf contains LEGACY marker but XDG should have overwritten it" >&2
        return 1
    fi

    # local/share/tmux should be synced
    assert_dir_exists_in_volume "local/share/tmux" || return 1
    assert_file_exists_in_volume "local/share/tmux/plugins/tpm/tpm" || return 1

    return 0
}

# ==============================================================================
# Test 10: vim/neovim sync
# ==============================================================================
test_vim_sync_assertions() {
    # .vimrc -> editors/vimrc
    assert_file_exists_in_volume "editors/vimrc" || return 1
    local vimrc_content
    vimrc_content=$(cat_from_volume "editors/vimrc") || return 1
    if [[ "$vimrc_content" != *"set number"* ]]; then
        printf '%s\n' "[DEBUG] vimrc does not contain expected content" >&2
        return 1
    fi

    # .vim/ -> editors/vim/
    assert_dir_exists_in_volume "editors/vim" || return 1
    assert_file_exists_in_volume "editors/vim/colors/custom.vim" || return 1

    # .config/nvim/ -> config/nvim/
    assert_dir_exists_in_volume "config/nvim" || return 1
    assert_file_exists_in_volume "config/nvim/init.vim" || return 1

    return 0
}

# ==============================================================================
# Test 11: Starship sync
# ==============================================================================
test_starship_sync_assertions() {
    assert_file_exists_in_volume "config/starship.toml" || return 1

    local starship_content
    starship_content=$(cat_from_volume "config/starship.toml") || return 1
    if [[ "$starship_content" != *'format = "$all"'* ]]; then
        printf '%s\n' "[DEBUG] starship.toml does not contain expected content" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Test 12: Oh My Posh sync
# ==============================================================================
setup_ohmyposh_fixture() {
    local fixture="${SYNC_TEST_FIXTURE_HOME:-$(create_fixture_home)}"
    mkdir -p "$fixture/.config/oh-my-posh"

    printf '%s\n' '{"$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json"}' >"$fixture/.config/oh-my-posh/theme.json"
}

test_ohmyposh_sync_assertions() {
    assert_dir_exists_in_volume "config/oh-my-posh" || return 1
    assert_file_exists_in_volume "config/oh-my-posh/theme.json" || return 1

    local content
    content=$(cat_from_volume "config/oh-my-posh/theme.json") || return 1
    if [[ "$content" != *"schema"* ]]; then
        printf '%s\n' "[DEBUG] oh-my-posh theme.json does not contain expected content" >&2
        return 1
    fi

    return 0
}

# ==============================================================================
# Main Test Execution
# ==============================================================================
main() {
    sync_test_section "Dev Tool Sync Tests"
    sync_test_info "Run ID: $SYNC_TEST_RUN_ID"

    # Test 1: Git g-filter - credential.helper stripped
    # Uses profile import mode because _cai_import_git_config reads from $HOME
    run_git_sync_test "git-filter" setup_git_filter_fixture test_git_filter_assertions

    # Test 2: GitHub CLI secret separation
    run_tool_sync_test "gh-secret-sep" setup_gh_secret_fixture test_gh_secret_separation_assertions

    # Test 3: GitHub CLI --no-secrets behavior
    run_tool_sync_test "gh-no-secrets" setup_gh_secret_fixture test_gh_no_secrets_assertions --no-secrets

    # Test 4: SSH disabled by default
    run_tool_sync_test "ssh-disabled" setup_ssh_fixture test_ssh_disabled_assertions

    # Test 5: SSH via additional_paths opt-in
    run_tool_sync_test_with_config "ssh-addl-paths" setup_ssh_additional_paths_fixture test_ssh_additional_paths_assertions

    # Test 6: --no-secrets does NOT affect additional_paths
    run_tool_sync_test_with_config "no-secrets-addl" setup_ssh_additional_paths_fixture test_no_secrets_keeps_additional_paths_assertions --no-secrets

    # Test 7: VS Code Server - targets ensured when source missing
    run_tool_sync_test "vscode-empty" setup_vscode_empty_fixture test_vscode_ensures_targets_assertions

    # Test 8: VS Code Server - content syncs when source exists
    run_tool_sync_test "vscode-content" create_vscode_fixture test_vscode_content_sync_assertions

    # Test 9: tmux sync - verify XDG wins over legacy
    run_tool_sync_test "tmux-sync" setup_tmux_precedence_fixture test_tmux_sync_assertions

    # Test 10: vim/neovim sync
    run_tool_sync_test "vim-sync" create_vim_fixture test_vim_sync_assertions

    # Test 11: Starship sync
    run_tool_sync_test "starship-sync" create_starship_fixture test_starship_sync_assertions

    # Test 12: Oh My Posh sync
    run_tool_sync_test "ohmyposh-sync" setup_ohmyposh_fixture test_ohmyposh_sync_assertions

    sync_test_section "Summary"
    if [[ $SYNC_TEST_FAILED -eq 0 ]]; then
        sync_test_info "All dev tool sync tests passed"
        exit 0
    else
        sync_test_info "Some dev tool sync tests failed"
        exit 1
    fi
}

main "$@"
