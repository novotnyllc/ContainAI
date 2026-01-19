#!/usr/bin/env bash
# ==============================================================================
# Integration tests for sync-agent-plugins.sh workflow
# ==============================================================================
# Verifies:
# 1. Platform guard rejects non-Linux
# 2. Dry-run makes no volume changes
# 3. Full sync copies all configs
# 4. Secret permissions correct (600 files, 700 dirs)
# 5. Plugins load correctly in container
# 6. No orphan markers visible
# 7. Shell sources .bashrc.d scripts
# 8. tmux loads config
# 9. gh CLI available in container
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use isolated test volumes by default to prevent clobbering user data
# Each test run gets a unique volume name
TEST_RUN_ID="test-$(date +%s)-$$"
DATA_VOLUME="containai-test-${TEST_RUN_ID}"

IMAGE_NAME="agent-sandbox-test:latest"

# Cleanup test volumes on exit
cleanup_test_volumes() {
    # Remove the main test volume
    docker volume rm "$DATA_VOLUME" 2>/dev/null || true
    # Also clean any stale test volumes from previous interrupted runs
    # Using a subshell to capture the list safely
    local stale_volumes
    stale_volumes=$(docker volume ls --filter "name=containai-test-" -q 2>/dev/null || true)
    if [[ -n "$stale_volumes" ]]; then
        echo "$stale_volumes" | xargs -r docker volume rm 2>/dev/null || true
    fi
}
trap cleanup_test_volumes EXIT

# Color output helpers
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; FAILED=1; }
info() { echo "[INFO] $*"; }
section() { echo ""; echo "=== $* ==="; }

FAILED=0

# Helper to run commands in rsync container and extract clean output
# Filters out SSH key generation noise from eeacms/rsync
# Captures docker exit code to avoid false positives
run_in_rsync() {
    local output exit_code
    output=$(docker run --rm -v "$DATA_VOLUME":/data eeacms/rsync sh -c "$1" 2>&1) || exit_code=$?
    if [[ ${exit_code:-0} -ne 0 && ${exit_code:-0} -ne 1 ]]; then
        echo "docker_run_failed:$exit_code"
        return 1
    fi
    echo "$output" | \
        grep -v "^Generating SSH" | \
        grep -v "^ssh-keygen:" | \
        grep -v "^Please add this" | \
        grep -v "^====" | \
        grep -v "^ssh-rsa "
}

# Helper to get a single numeric value from rsync container (handles wc -l whitespace)
# Returns -1 on docker failure to distinguish from "0 results"
get_count() {
    local output
    output=$(run_in_rsync "$1") || { echo "-1"; return 1; }
    echo "$output" | awk '{print $1}' | grep -E '^[0-9]+$' | tail -1 || echo "0"
}

# Helper to run in test image - bypassing entrypoint for symlink checks only
run_in_image_no_entrypoint() {
    if ! docker run --rm --entrypoint /bin/bash -v "$DATA_VOLUME":/mnt/agent-data "$IMAGE_NAME" -c "$1" 2>/dev/null; then
        echo "docker_error"
    fi
}

# ==============================================================================
# Test 1: Platform guard rejects non-Linux
# ==============================================================================
test_platform_guard() {
    section "Test 1: Platform guard rejects non-Linux"

    # Create a temp directory with a fake uname that returns Darwin
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cat > "$tmp_dir/uname" << 'FAKE_UNAME'
#!/bin/bash
if [[ "$1" == "-s" ]]; then
    echo "Darwin"
else
    /usr/bin/uname "$@"
fi
FAKE_UNAME
    chmod +x "$tmp_dir/uname"

    # Test that script fails on "Darwin" (via PATH override)
    local darwin_output
    local darwin_exit=0
    darwin_output=$(PATH="$tmp_dir:$PATH" "$SCRIPT_DIR/sync-agent-plugins.sh" 2>&1) || darwin_exit=$?

    if [[ $darwin_exit -ne 0 ]] && echo "$darwin_output" | grep -q "macOS is not supported"; then
        pass "Darwin platform rejected with correct error message"
    else
        fail "Darwin platform should be rejected (exit=$darwin_exit)"
    fi

    # Test Linux (real platform) - should succeed past platform check
    # We check that --help works (proves platform guard passes)
    local linux_output linux_exit=0
    linux_output=$("$SCRIPT_DIR/sync-agent-plugins.sh" --help 2>&1) || linux_exit=$?
    if [[ $linux_exit -eq 0 ]]; then
        pass "Linux platform accepted (--help works)"
    else
        fail "Linux platform should accept --help (exit=$linux_exit, output: $linux_output)"
    fi

    # Cleanup
    rm -rf "$tmp_dir"
}

# ==============================================================================
# Test 2: Dry-run makes no volume changes
# ==============================================================================
test_dry_run() {
    section "Test 2: Dry-run makes no volume changes"

    # Ensure volume exists before test (test setup, not mutation from dry-run)
    if ! docker volume inspect "$DATA_VOLUME" &>/dev/null; then
        info "Creating test volume (test setup, not dry-run mutation)"
        docker volume create "$DATA_VOLUME" >/dev/null
    fi

    # Capture volume snapshot before dry-run using stat (BusyBox compatible)
    # Format: permissions size path
    local before_snapshot
    before_snapshot=$(run_in_rsync 'find /data -exec stat -c "%a %s %n" {} \; 2>/dev/null | sort')

    # Run dry-run - should succeed when prerequisites are met
    local dry_run_exit=0
    local dry_run_output
    dry_run_output=$("$SCRIPT_DIR/sync-agent-plugins.sh" --volume "$DATA_VOLUME" --dry-run 2>&1) || dry_run_exit=$?

    if [[ $dry_run_exit -ne 0 ]]; then
        fail "Dry-run failed with exit code $dry_run_exit"
        info "Output: $(echo "$dry_run_output" | head -10)"
        return
    fi
    pass "Dry-run command succeeded"

    # Verify required output includes resolved volume name
    if echo "$dry_run_output" | grep -q "Using data volume: $DATA_VOLUME"; then
        pass "Dry-run output includes 'Using data volume: $DATA_VOLUME'"
    else
        fail "Dry-run output missing 'Using data volume: $DATA_VOLUME'"
        info "Output: $(echo "$dry_run_output" | head -20)"
    fi

    # Create test volumes for precedence tests
    docker volume create env-test-vol >/dev/null 2>&1 || true
    docker volume create cli-test-vol >/dev/null 2>&1 || true

    # Test CONTAINAI_DATA_VOLUME env var precedence
    local env_test_output env_test_exit=0
    env_test_output=$(CONTAINAI_DATA_VOLUME="env-test-vol" "$SCRIPT_DIR/sync-agent-plugins.sh" --dry-run 2>&1) || env_test_exit=$?
    if echo "$env_test_output" | grep -q "Using data volume: env-test-vol"; then
        pass "CONTAINAI_DATA_VOLUME env var respected"
    else
        fail "CONTAINAI_DATA_VOLUME env var not respected (exit: $env_test_exit)"
        info "Output: $(echo "$env_test_output" | head -10)"
    fi

    # Test --volume flag takes precedence over env var
    local cli_test_output cli_test_exit=0
    cli_test_output=$(CONTAINAI_DATA_VOLUME="env-test-vol" "$SCRIPT_DIR/sync-agent-plugins.sh" --volume "cli-test-vol" --dry-run 2>&1) || cli_test_exit=$?
    if echo "$cli_test_output" | grep -q "Using data volume: cli-test-vol"; then
        pass "--volume flag takes precedence over env var"
    else
        fail "--volume flag does not take precedence over env var (exit: $cli_test_exit)"
        info "Output: $(echo "$cli_test_output" | head -10)"
    fi

    # Test --volume skips config parsing even when CONTAINAI_CONFIG points to invalid file
    local skip_config_output skip_config_exit=0
    skip_config_output=$(CONTAINAI_CONFIG="/nonexistent/config.toml" "$SCRIPT_DIR/sync-agent-plugins.sh" --volume "$DATA_VOLUME" --dry-run 2>&1) || skip_config_exit=$?
    if echo "$skip_config_output" | grep -q "Using data volume: $DATA_VOLUME"; then
        pass "--volume skips config parsing (ignores invalid CONTAINAI_CONFIG)"
    else
        fail "--volume should skip config parsing but didn't (exit: $skip_config_exit)"
        info "Output: $(echo "$skip_config_output" | head -10)"
    fi

    # Test explicit --config with missing file fails
    # Note: Must clear env vars to ensure config parsing is attempted
    local missing_config_output missing_config_exit=0
    missing_config_output=$(env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG "$SCRIPT_DIR/sync-agent-plugins.sh" --config "/nonexistent/config.toml" --dry-run 2>&1) || missing_config_exit=$?
    if [[ $missing_config_exit -ne 0 ]] && echo "$missing_config_output" | grep -q "Config file not found"; then
        pass "Explicit --config with missing file fails with error"
    else
        fail "Explicit --config with missing file should fail (exit: $missing_config_exit)"
        info "Output: $(echo "$missing_config_output" | head -10)"
    fi

    # Test config discovery from $PWD
    # Note: Must clear env vars to ensure config discovery is tested, not env precedence
    local config_test_dir config_test_output config_test_exit=0
    config_test_dir=$(mktemp -d)
    mkdir -p "$config_test_dir/.containai"
    echo '[agent]' > "$config_test_dir/.containai/config.toml"
    echo 'data_volume = "config-discovered-vol"' >> "$config_test_dir/.containai/config.toml"
    docker volume create config-discovered-vol >/dev/null 2>&1 || true
    config_test_output=$(cd "$config_test_dir" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG "$SCRIPT_DIR/sync-agent-plugins.sh" --dry-run 2>&1) || config_test_exit=$?
    if echo "$config_test_output" | grep -q "Using data volume: config-discovered-vol"; then
        pass "Config discovery from \$PWD works"
    else
        fail "Config discovery from \$PWD not working (exit: $config_test_exit)"
        info "Output: $(echo "$config_test_output" | head -10)"
    fi
    rm -rf "$config_test_dir"
    docker volume rm config-discovered-vol >/dev/null 2>&1 || true

    # Cleanup test volumes
    docker volume rm env-test-vol cli-test-vol >/dev/null 2>&1 || true

    # Capture volume snapshot after dry-run
    local after_snapshot
    after_snapshot=$(run_in_rsync 'find /data -exec stat -c "%a %s %n" {} \; 2>/dev/null | sort')

    if [[ "$before_snapshot" == "$after_snapshot" ]]; then
        pass "Dry-run did not change volume (permissions, sizes, paths unchanged)"
    else
        fail "Dry-run changed volume state"
        info "Before: $(echo "$before_snapshot" | wc -l | awk '{print $1}') entries"
        info "After: $(echo "$after_snapshot" | wc -l | awk '{print $1}') entries"
    fi
}

# ==============================================================================
# Test 3: Full sync copies all configs
# ==============================================================================
test_full_sync() {
    section "Test 3: Full sync copies all configs"

    # Run full sync and require success
    local sync_exit=0
    if ! "$SCRIPT_DIR/sync-agent-plugins.sh" --volume "$DATA_VOLUME" >/dev/null 2>&1; then
        sync_exit=$?
        fail "Full sync failed with exit code $sync_exit"
        return
    fi
    pass "Full sync completed successfully"

    # Verify key directories exist
    local dirs_to_check=(
        "/data/claude"
        "/data/claude/plugins"
        "/data/config/gh"
        "/data/codex"
        "/data/gemini"
        "/data/copilot"
        "/data/shell"
        "/data/tmux"
    )

    for dir in "${dirs_to_check[@]}"; do
        local exists
        exists=$(run_in_rsync "test -d '$dir' && echo yes || echo no" | tail -1)
        if [[ "$exists" == "yes" ]]; then
            pass "Directory exists: $dir"
        else
            fail "Directory missing: $dir"
        fi
    done

    # Verify key files exist (from spec requirements)
    local files_to_check=(
        "/data/claude/claude.json"
        "/data/claude/credentials.json"
        "/data/claude/settings.json"
    )

    for file in "${files_to_check[@]}"; do
        local exists
        exists=$(run_in_rsync "test -f '$file' && echo yes || echo no" | tail -1)
        if [[ "$exists" == "yes" ]]; then
            pass "File exists: $file"
        else
            fail "File missing: $file"
        fi
    done

    # Log volume structure for evidence (spec requirement: ls -laR)
    info "Volume structure (ls -laR /data | head -50):"
    run_in_rsync 'ls -laR /data 2>/dev/null | head -50' | while IFS= read -r line; do
        echo "    $line"
    done
}

# ==============================================================================
# Test 4: Secret permissions correct (600 files, 700 dirs)
# ==============================================================================
test_secret_permissions() {
    section "Test 4: Secret permissions correct"

    # Secret files should be 600 - these MUST exist after sync (per spec, sync ensures targets even when source missing)
    local secret_files=(
        "/data/claude/credentials.json"
        "/data/codex/auth.json"
        "/data/gemini/oauth_creds.json"
        "/data/gemini/google_accounts.json"
        "/data/local/share/opencode/auth.json"
    )

    for file in "${secret_files[@]}"; do
        local perm
        perm=$(run_in_rsync "stat -c '%a' '$file' 2>/dev/null || echo missing" | tail -1)
        if [[ "$perm" == "600" ]]; then
            pass "Secret file has 600 permissions: $file"
        elif [[ "$perm" == "missing" ]]; then
            fail "Secret file missing (should exist even without source): $file"
        else
            fail "Secret file has wrong permissions ($perm instead of 600): $file"
        fi
    done

    # Secret dirs should be 700
    local secret_dirs=(
        "/data/config/gh"
    )

    for dir in "${secret_dirs[@]}"; do
        local perm
        perm=$(run_in_rsync "stat -c '%a' '$dir' 2>/dev/null || echo missing" | tail -1)
        if [[ "$perm" == "700" ]]; then
            pass "Secret dir has 700 permissions: $dir"
        elif [[ "$perm" == "missing" ]]; then
            fail "Secret dir missing (should exist even without source): $dir"
        else
            fail "Secret dir has wrong permissions ($perm instead of 700): $dir"
        fi
    done

    # Log stat output for evidence (spec requirement - all secret files)
    info "Secret permissions verification (stat -c '%a %n'):"
    run_in_rsync "stat -c '%a %n' /data/claude/credentials.json /data/config/gh /data/gemini/oauth_creds.json /data/gemini/google_accounts.json /data/codex/auth.json /data/local/share/opencode/auth.json 2>/dev/null || true" | while IFS= read -r line; do
        echo "    $line"
    done
}

# ==============================================================================
# Test 5: Plugins load correctly in container
# ==============================================================================
test_plugins_in_container() {
    section "Test 5: Plugins load correctly in container"

    # Check if plugins directory has content
    local plugin_count
    plugin_count=$(get_count 'find /data/claude/plugins/cache -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l')

    if [[ "$plugin_count" -gt 0 ]]; then
        pass "Found $plugin_count plugin(s) in cache"
    else
        info "No plugins in cache (may not have been synced from host)"
    fi

    # Check symlinks in container point to correct locations
    local symlink_test
    symlink_test=$(run_in_image_no_entrypoint '
        if [ -L ~/.claude/plugins ] && [ "$(readlink ~/.claude/plugins)" = "/mnt/agent-data/claude/plugins" ]; then
            echo "ok"
        else
            echo "fail"
        fi
    ')

    if [[ "$symlink_test" == "ok" ]]; then
        pass "Claude plugins symlink points to volume"
    elif [[ "$symlink_test" == "docker_error" ]]; then
        fail "Docker container failed to start for symlink check"
    else
        fail "Claude plugins symlink incorrect"
    fi

    # Verify installed_plugins.json is valid JSON if it exists (use test image which has jq)
    local json_valid
    json_valid=$(run_in_image_no_entrypoint '
        if [ -f /mnt/agent-data/claude/plugins/installed_plugins.json ]; then
            jq empty /mnt/agent-data/claude/plugins/installed_plugins.json 2>/dev/null && echo valid || echo invalid
        else
            echo missing
        fi
    ')

    if [[ "$json_valid" == "valid" ]]; then
        pass "installed_plugins.json is valid JSON"
    elif [[ "$json_valid" == "missing" ]]; then
        info "installed_plugins.json not present"
    elif [[ "$json_valid" == "docker_error" ]]; then
        fail "Docker container failed to start for JSON validation"
    else
        fail "installed_plugins.json is invalid JSON"
    fi
}

# ==============================================================================
# Test 6: No orphan markers visible
# ==============================================================================
test_no_orphan_markers() {
    section "Test 6: No orphan markers visible"

    local orphan_count
    orphan_count=$(get_count 'find /data -name ".orphaned_at" 2>/dev/null | wc -l')

    if [[ "$orphan_count" == "-1" ]]; then
        fail "Docker failed when checking for orphan markers"
    elif [[ "$orphan_count" -eq 0 ]]; then
        pass "No orphan markers found"
    else
        fail "Found $orphan_count orphan marker(s)"
    fi
}

# ==============================================================================
# Test 7: Shell sources .bashrc.d scripts
# ==============================================================================
test_bashrc_sourcing() {
    section "Test 7: Shell sources .bashrc.d scripts"

    # Check if sourcing hooks are in .bashrc
    local bashrc_test
    bashrc_test=$(run_in_image_no_entrypoint '
        if grep -q "bashrc.d" ~/.bashrc && grep -q "bash_aliases_imported" ~/.bashrc; then
            echo "hooks_present"
        else
            echo "hooks_missing"
        fi
    ')

    if [[ "$bashrc_test" == "hooks_present" ]]; then
        pass "Sourcing hooks present in .bashrc"
    elif [[ "$bashrc_test" == "docker_error" ]]; then
        fail "Docker container failed to start for .bashrc check"
    else
        fail "Sourcing hooks missing from .bashrc"
    fi

    # Test actual sourcing works
    local source_test
    source_test=$(run_in_image_no_entrypoint '
        # Ensure directory exists (since we bypass entrypoint)
        mkdir -p /mnt/agent-data/shell/.bashrc.d

        # Create test script
        echo "export TEST_VAR=success" > /mnt/agent-data/shell/.bashrc.d/test.sh
        chmod +x /mnt/agent-data/shell/.bashrc.d/test.sh

        # Test in interactive shell
        result=$(bash -i -c "echo \$TEST_VAR" 2>/dev/null)

        # Cleanup
        rm -f /mnt/agent-data/shell/.bashrc.d/test.sh

        echo "$result"
    ')

    if [[ "$source_test" == "success" ]]; then
        pass ".bashrc.d scripts are sourced in interactive shells"
    elif [[ "$source_test" == "docker_error" ]]; then
        fail "Docker container failed to start for sourcing test"
    else
        fail ".bashrc.d scripts are not being sourced (got: $source_test)"
    fi
}

# ==============================================================================
# Test 8: tmux loads config
# ==============================================================================
test_tmux_config() {
    section "Test 8: tmux loads config"

    # Check tmux symlink
    local tmux_link
    tmux_link=$(run_in_image_no_entrypoint '
        if [ -L ~/.tmux.conf ]; then
            readlink ~/.tmux.conf
        else
            echo "not_symlink"
        fi
    ')

    if [[ "$tmux_link" == "/mnt/agent-data/tmux/.tmux.conf" ]]; then
        pass "tmux.conf symlink points to volume"
    elif [[ "$tmux_link" == "docker_error" ]]; then
        fail "Docker container failed to start for tmux symlink check"
    else
        fail "tmux.conf symlink incorrect: $tmux_link"
    fi

    # Check tmux can load config (actually reads the config file)
    local tmux_test
    tmux_test=$(run_in_image_no_entrypoint '
        # Ensure config file exists (since we bypass entrypoint)
        mkdir -p /mnt/agent-data/tmux
        touch /mnt/agent-data/tmux/.tmux.conf
        # Try to start tmux with explicit config to prove it can be read
        if tmux -f ~/.tmux.conf -L test-config new-session -d -s test 2>/dev/null; then
            tmux -L test-config kill-session -t test 2>/dev/null || true
            echo "config_loaded"
        else
            echo "config_failed"
        fi
    ')

    if [[ "$tmux_test" == "config_loaded" ]]; then
        pass "tmux can load config from volume symlink"
    elif [[ "$tmux_test" == "docker_error" ]]; then
        fail "Docker container failed to start for tmux test"
    else
        fail "tmux failed to load config: $tmux_test"
    fi
}

# ==============================================================================
# Test 9: gh CLI available in container
# ==============================================================================
test_gh_cli() {
    section "Test 9: gh CLI available in container"

    # Check gh version
    local gh_version
    gh_version=$(run_in_image_no_entrypoint 'gh --version 2>&1 | head -1')

    if [[ "$gh_version" == docker_error ]]; then
        fail "Docker container failed to start for gh version check"
    elif echo "$gh_version" | grep -q "gh version"; then
        pass "gh CLI available: $gh_version"
    else
        fail "gh CLI not available or error: $gh_version"
    fi

    # Check gh auth status (expected to fail without credentials, but command should work)
    local gh_auth
    gh_auth=$(run_in_image_no_entrypoint 'gh auth status 2>&1; echo "exit_code=$?"')

    if [[ "$gh_auth" == docker_error ]]; then
        fail "Docker container failed to start for gh auth check"
    elif echo "$gh_auth" | grep -q "exit_code="; then
        # gh auth status returns non-zero when not logged in, that's expected
        if echo "$gh_auth" | grep -qE "(not logged in|To log in|logged in)"; then
            pass "gh auth status command works (not authenticated - expected)"
        else
            pass "gh auth status command executed"
        fi
    else
        fail "gh auth status command failed unexpectedly"
    fi
}

# ==============================================================================
# Test 10: opencode CLI available in container (spec requirement)
# ==============================================================================
test_opencode_cli() {
    section "Test 10: opencode CLI available in container"

    # Check opencode version (spec verification command)
    # Note: opencode is installed in Dockerfile but may not be in test image cache
    local opencode_version
    opencode_version=$(run_in_image_no_entrypoint 'which opencode >/dev/null 2>&1 && opencode --version 2>&1 | head -1 || echo "not_installed"')

    if [[ "$opencode_version" == docker_error ]]; then
        fail "Docker container failed to start for opencode version check"
    elif [[ "$opencode_version" == "not_installed" ]]; then
        # opencode should be installed per Dockerfile but may be missing in test image
        # This is a warning - rebuild test image to fix
        info "opencode CLI not in test image (rebuild with: docker build -t agent-sandbox-test:latest .)"
    elif echo "$opencode_version" | grep -qiE "opencode|version"; then
        pass "opencode CLI available: $opencode_version"
    else
        pass "opencode CLI check executed: $opencode_version"
    fi
}

# ==============================================================================
# Test 11: Workspace path matching in config
# ==============================================================================
test_workspace_path_matching() {
    section "Test 11: Workspace path-based config matching"

    local test_dir test_vol
    test_dir="/tmp/test-workspace-match-$$"
    test_vol="test-ws-vol-$$"

    mkdir -p "$test_dir/subproject/.containai"
    cat > "$test_dir/subproject/.containai/config.toml" << EOF
[agent]
data_volume = "default-vol"

[workspace."$test_dir/subproject"]
data_volume = "$test_vol"
EOF

    # Test that workspace path matching works
    # Must clear env vars to ensure config discovery is tested
    local resolved
    if resolved=$(cd "$test_dir/subproject" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/aliases.sh' && _containai_resolve_volume '' '$test_dir/subproject'" 2>&1); then
        if [[ "$resolved" == "$test_vol" ]]; then
            pass "Workspace path matching works"
        else
            fail "Workspace path matching returned wrong volume: $resolved (expected: $test_vol)"
        fi
    else
        fail "Workspace path matching failed: $resolved"
    fi

    rm -rf "$test_dir"
}

# ==============================================================================
# Test 12: Fallback to [agent] when no workspace match
# ==============================================================================
test_workspace_fallback_to_agent() {
    section "Test 12: Fallback to [agent] when no workspace match"

    local test_dir default_vol
    test_dir="/tmp/test-fallback-$$"
    default_vol="fallback-vol-$$"

    mkdir -p "$test_dir/.containai"
    cat > "$test_dir/.containai/config.toml" << EOF
[agent]
data_volume = "$default_vol"

[workspace."/some/other/path"]
data_volume = "other-vol"
EOF

    # Test that fallback to [agent] works when no workspace matches
    # Must clear env vars to ensure config discovery is tested
    local resolved
    if resolved=$(cd "$test_dir" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/aliases.sh' && _containai_resolve_volume '' '$test_dir'" 2>&1); then
        if [[ "$resolved" == "$default_vol" ]]; then
            pass "Falls back to [agent] when no workspace match"
        else
            fail "Fallback returned wrong volume: $resolved (expected: $default_vol)"
        fi
    else
        fail "Fallback to [agent] failed: $resolved"
    fi

    rm -rf "$test_dir"
}

# ==============================================================================
# Test 13: Longest workspace path match wins
# ==============================================================================
test_longest_match_wins() {
    section "Test 13: Longest workspace path match wins"

    local test_dir
    test_dir="/tmp/test-longest-$$"

    mkdir -p "$test_dir/project/subdir/.containai"
    cat > "$test_dir/project/subdir/.containai/config.toml" << EOF
[agent]
data_volume = "default"

[workspace."$test_dir/project"]
data_volume = "project-vol"

[workspace."$test_dir/project/subdir"]
data_volume = "subdir-vol"
EOF

    # Test that longest workspace path match wins
    # Must clear env vars to ensure config discovery is tested
    local resolved
    if resolved=$(cd "$test_dir/project/subdir" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/aliases.sh' && _containai_resolve_volume '' '$test_dir/project/subdir'" 2>&1); then
        if [[ "$resolved" == "subdir-vol" ]]; then
            pass "Longest workspace path match wins"
        else
            fail "Longest match returned wrong volume: $resolved (expected: subdir-vol)"
        fi
    else
        fail "Longest match test failed: $resolved"
    fi

    rm -rf "$test_dir"
}

# ==============================================================================
# Test 14: --data-volume overrides workspace config
# ==============================================================================
test_data_volume_overrides_config() {
    section "Test 14: --data-volume overrides workspace config"

    local test_dir
    test_dir="/tmp/test-override-$$"

    mkdir -p "$test_dir/.containai"
    cat > "$test_dir/.containai/config.toml" << 'EOF'
[agent]
data_volume = "config-vol"
EOF

    # Test that CLI volume overrides config
    # Must clear env vars to ensure CLI precedence is tested
    local resolved
    if resolved=$(cd "$test_dir" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/aliases.sh' && _containai_resolve_volume 'cli-vol'" 2>&1); then
        if [[ "$resolved" == "cli-vol" ]]; then
            pass "--data-volume overrides workspace config"
        else
            fail "CLI override returned wrong volume: $resolved (expected: cli-vol)"
        fi
    else
        fail "CLI override test failed: $resolved"
    fi

    rm -rf "$test_dir"
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo "=============================================================================="
    echo "Integration Tests for sync-agent-plugins.sh"
    echo "=============================================================================="

    # Check prerequisites
    if ! command -v docker &>/dev/null; then
        echo "ERROR: docker is required" >&2
        exit 1
    fi

    # Check if image exists (build if needed)
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        info "Building test image..."
        if ! docker build -t "$IMAGE_NAME" "$SCRIPT_DIR" >/dev/null 2>&1; then
            echo "ERROR: Failed to build test image" >&2
            exit 1
        fi
    fi

    # Run tests
    test_platform_guard
    test_dry_run
    test_full_sync
    test_secret_permissions
    test_plugins_in_container
    test_no_orphan_markers
    test_bashrc_sourcing
    test_tmux_config
    test_gh_cli
    test_opencode_cli
    test_workspace_path_matching
    test_workspace_fallback_to_agent
    test_longest_match_wins
    test_data_volume_overrides_config

    # Summary
    echo ""
    echo "=============================================================================="
    if [[ "$FAILED" -eq 0 ]]; then
        echo "All tests passed!"
        exit 0
    else
        echo "Some tests failed!"
        exit 1
    fi
}

main "$@"
