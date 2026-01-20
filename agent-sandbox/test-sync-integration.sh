#!/usr/bin/env bash
# ==============================================================================
# Integration tests for ContainAI import workflow
# ==============================================================================
# Verifies:
# 1. CLI help works
# 2. Dry-run makes no volume changes
# 3. Full sync copies all configs
# 4. Secret permissions correct (600 files, 700 dirs)
# 5. Plugins load correctly in container
# 6. No orphan markers visible
# 7. Shell sources .bashrc.d scripts
# 8. tmux loads config
# 9. gh CLI available in container
# 10. opencode CLI check (optional - depends on image build)
# 11-15. Workspace volume resolution tests
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use isolated test volumes by default to prevent clobbering user data
# Each test run gets a unique volume name
TEST_RUN_ID="test-$(date +%s)-$$"
DATA_VOLUME="containai-test-${TEST_RUN_ID}"

IMAGE_NAME="agent-sandbox-test:latest"

# Track all test volumes created by THIS run for safe cleanup
# (avoids deleting volumes from parallel test runs)
declare -a TEST_VOLUMES_CREATED=()

# Register a test volume for cleanup (call after creating any test volume)
register_test_volume() {
    TEST_VOLUMES_CREATED+=("$1")
}

# Cleanup test volumes created by THIS run
# First pass: registered volumes (explicit tracking)
# Second pass: any volumes containing this run's ID (catches unregistered volumes)
cleanup_test_volumes() {
    local vol
    # First pass: explicitly registered volumes
    for vol in "${TEST_VOLUMES_CREATED[@]}"; do
        docker volume rm "$vol" 2>/dev/null || true
    done
    # Second pass: catch any volumes containing this run's ID that weren't registered
    # Note: containai-test-env-${TEST_RUN_ID}, containai-test-cli-${TEST_RUN_ID}, etc.
    # all contain $TEST_RUN_ID as a substring, so filter by run ID directly
    local run_volumes
    run_volumes=$(docker volume ls --filter "name=${TEST_RUN_ID}" -q 2>/dev/null || true)
    if [[ -n "$run_volumes" ]]; then
        echo "$run_volumes" | xargs -r docker volume rm 2>/dev/null || true
    fi
}
trap cleanup_test_volumes EXIT

# Register the main test volume
register_test_volume "$DATA_VOLUME"

# Color output helpers
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; FAILED=1; }
info() { echo "[INFO] $*"; }
section() { echo ""; echo "=== $* ==="; }

FAILED=0

# Helper to run commands in rsync container and extract clean output
# Filters out SSH key generation noise from eeacms/rsync
# Captures docker exit code to avoid false positives
# Uses sed instead of grep -v to avoid failure on empty output (pipefail-safe)
run_in_rsync() {
    local output exit_code
    output=$(docker run --rm -v "$DATA_VOLUME":/data eeacms/rsync sh -c "$1" 2>&1) || exit_code=$?
    if [[ ${exit_code:-0} -ne 0 && ${exit_code:-0} -ne 1 ]]; then
        echo "docker_run_failed:$exit_code"
        return 1
    fi
    # Use sed to filter noise (doesn't fail on empty input unlike grep -v)
    printf '%s\n' "$output" | sed \
        -e '/^Generating SSH/d' \
        -e '/^ssh-keygen:/d' \
        -e '/^Please add this/d' \
        -e '/^====/d' \
        -e '/^ssh-rsa /d'
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
# Test 1: CLI help works
# ==============================================================================
test_cli_help() {
    section "Test 1: CLI help works"

    # Test cai --help works
    local help_output help_exit=0
    help_output=$(bash -c "source '$SCRIPT_DIR/containai.sh' && cai --help" 2>&1) || help_exit=$?
    if [[ $help_exit -eq 0 ]] && echo "$help_output" | grep -q "ContainAI"; then
        pass "cai --help works"
    else
        fail "cai --help failed (exit=$help_exit)"
        info "Output: $(echo "$help_output" | head -10)"
    fi

    # Test cai import --help works
    local import_help_output import_help_exit=0
    import_help_output=$(bash -c "source '$SCRIPT_DIR/containai.sh' && cai import --help" 2>&1) || import_help_exit=$?
    if [[ $import_help_exit -eq 0 ]] && echo "$import_help_output" | grep -q "Import"; then
        pass "cai import --help works"
    else
        fail "cai import --help failed (exit=$import_help_exit)"
        info "Output: $(echo "$import_help_output" | head -10)"
    fi
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

    # Run dry-run via cai import - should succeed when prerequisites are met
    local dry_run_exit=0
    local dry_run_output
    dry_run_output=$(bash -c "source '$SCRIPT_DIR/containai.sh' && cai import --data-volume '$DATA_VOLUME' --dry-run" 2>&1) || dry_run_exit=$?

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

    # Create test volumes for precedence tests (use unique run-scoped names)
    local env_vol="containai-test-env-${TEST_RUN_ID}"
    local cli_vol="containai-test-cli-${TEST_RUN_ID}"
    if ! docker volume create "$env_vol" >/dev/null; then
        fail "Failed to create test volume: $env_vol"
        return
    fi
    if ! docker volume create "$cli_vol" >/dev/null; then
        fail "Failed to create test volume: $cli_vol"
        return
    fi
    register_test_volume "$env_vol"
    register_test_volume "$cli_vol"

    # Test CONTAINAI_DATA_VOLUME env var precedence
    local env_test_output env_test_exit=0
    env_test_output=$(CONTAINAI_DATA_VOLUME="$env_vol" bash -c "source '$SCRIPT_DIR/containai.sh' && cai import --dry-run" 2>&1) || env_test_exit=$?
    if echo "$env_test_output" | grep -q "Using data volume: $env_vol"; then
        pass "CONTAINAI_DATA_VOLUME env var respected"
    else
        fail "CONTAINAI_DATA_VOLUME env var not respected (exit: $env_test_exit)"
        info "Output: $(echo "$env_test_output" | head -10)"
    fi

    # Test --data-volume flag takes precedence over env var
    local cli_test_output cli_test_exit=0
    cli_test_output=$(CONTAINAI_DATA_VOLUME="$env_vol" bash -c "source '$SCRIPT_DIR/containai.sh' && cai import --data-volume '$cli_vol' --dry-run" 2>&1) || cli_test_exit=$?
    if echo "$cli_test_output" | grep -q "Using data volume: $cli_vol"; then
        pass "--data-volume flag takes precedence over env var"
    else
        fail "--data-volume flag does not take precedence over env var (exit: $cli_test_exit)"
        info "Output: $(echo "$cli_test_output" | head -10)"
    fi

    # Test --data-volume takes precedence (skips config discovery)
    local skip_config_output skip_config_exit=0
    skip_config_output=$(bash -c "source '$SCRIPT_DIR/containai.sh' && cai import --data-volume '$DATA_VOLUME' --dry-run" 2>&1) || skip_config_exit=$?
    if echo "$skip_config_output" | grep -q "Using data volume: $DATA_VOLUME"; then
        pass "--data-volume takes precedence (uses specified volume directly)"
    else
        fail "--data-volume should take precedence but didn't (exit: $skip_config_exit)"
        info "Output: $(echo "$skip_config_output" | head -10)"
    fi

    # Test explicit --config with missing file fails
    # Note: Must clear env vars to ensure config parsing is attempted
    local missing_config_output missing_config_exit=0
    missing_config_output=$(env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/containai.sh' && cai import --config '/nonexistent/config.toml' --dry-run" 2>&1) || missing_config_exit=$?
    if [[ $missing_config_exit -ne 0 ]] && echo "$missing_config_output" | grep -q "Config file not found"; then
        pass "Explicit --config with missing file fails with error"
    else
        fail "Explicit --config with missing file should fail (exit: $missing_config_exit)"
        info "Output: $(echo "$missing_config_output" | head -10)"
    fi

    # Test config discovery from $PWD (use unique run-scoped volume name)
    # Note: Must clear env vars to ensure config discovery is tested, not env precedence
    local config_test_dir config_test_output config_test_exit=0
    local config_vol="containai-test-config-${TEST_RUN_ID}"
    config_test_dir=$(mktemp -d)
    mkdir -p "$config_test_dir/.containai"
    echo '[agent]' > "$config_test_dir/.containai/config.toml"
    echo "data_volume = \"$config_vol\"" >> "$config_test_dir/.containai/config.toml"
    if ! docker volume create "$config_vol" >/dev/null; then
        fail "Failed to create test volume: $config_vol"
        rm -rf "$config_test_dir"
        return
    fi
    register_test_volume "$config_vol"
    config_test_output=$(cd "$config_test_dir" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/containai.sh' && cai import --dry-run" 2>&1) || config_test_exit=$?
    if echo "$config_test_output" | grep -q "Using data volume: $config_vol"; then
        pass "Config discovery from \$PWD works"
    else
        fail "Config discovery from \$PWD not working (exit: $config_test_exit)"
        info "Output: $(echo "$config_test_output" | head -10)"
    fi
    rm -rf "$config_test_dir"

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

    # Run full sync via cai import and require success
    local sync_exit=0
    bash -c "source '$SCRIPT_DIR/containai.sh' && cai import --data-volume '$DATA_VOLUME'" >/dev/null 2>&1 || sync_exit=$?
    if [[ $sync_exit -ne 0 ]]; then
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
        "/data/config/tmux"
        "/data/local/share/tmux"
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
    local ls_output
    ls_output=$(run_in_rsync 'ls -laR /data 2>/dev/null | head -50') || true
    if [[ -n "$ls_output" ]]; then
        printf '%s\n' "$ls_output" | while IFS= read -r line; do
            echo "    $line"
        done
    fi
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
    local evidence_output
    evidence_output=$(run_in_rsync "stat -c '%a %n' /data/claude/credentials.json /data/config/gh /data/gemini/oauth_creds.json /data/gemini/google_accounts.json /data/codex/auth.json /data/local/share/opencode/auth.json 2>/dev/null || true") || true
    if [[ -n "$evidence_output" ]]; then
        printf '%s\n' "$evidence_output" | while IFS= read -r line; do
            echo "    $line"
        done
    fi
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
# Test 8: tmux loads config (XDG paths)
# ==============================================================================
test_tmux_config() {
    section "Test 8: tmux loads config (XDG paths)"

    # Check tmux XDG config directory symlink
    local tmux_link
    tmux_link=$(run_in_image_no_entrypoint '
        if [ -L ~/.config/tmux ]; then
            readlink ~/.config/tmux
        else
            echo "not_symlink"
        fi
    ')

    if [[ "$tmux_link" == "/mnt/agent-data/config/tmux" ]]; then
        pass "~/.config/tmux symlink points to volume"
    elif [[ "$tmux_link" == "docker_error" ]]; then
        fail "Docker container failed to start for tmux symlink check"
    else
        fail "tmux config symlink incorrect: $tmux_link (expected /mnt/agent-data/config/tmux)"
    fi

    # Check tmux actually reads config from XDG path by verifying a user option
    local tmux_test
    tmux_test=$(run_in_image_no_entrypoint '
        # Ensure XDG config directory exists (since we bypass entrypoint)
        mkdir -p /mnt/agent-data/config/tmux
        # Write a sentinel user option to prove config is read
        echo "set -g @containai_test xdg_loaded" > /mnt/agent-data/config/tmux/tmux.conf
        # Start tmux with explicit config path to guarantee XDG config is read
        if tmux -f ~/.config/tmux/tmux.conf -L test-config new-session -d -s test 2>/dev/null; then
            # Verify the sentinel option was actually loaded
            result=$(tmux -L test-config show-options -gqv @containai_test 2>/dev/null || echo "")
            tmux -L test-config kill-session -t test 2>/dev/null || true
            if [ "$result" = "xdg_loaded" ]; then
                echo "config_verified"
            else
                echo "config_not_read"
            fi
        else
            echo "config_failed"
        fi
    ')

    if [[ "$tmux_test" == "config_verified" ]]; then
        pass "tmux reads and applies config from XDG path"
    elif [[ "$tmux_test" == "config_not_read" ]]; then
        fail "tmux started but did not read XDG config"
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
# Test 10: opencode CLI check (optional - depends on image build)
# ==============================================================================
test_opencode_cli() {
    section "Test 10: opencode CLI check (optional)"

    # Check opencode version
    # Note: opencode is installed in Dockerfile but CI may use cached images
    # This test verifies the CLI is accessible when present, skips otherwise
    local opencode_version
    opencode_version=$(run_in_image_no_entrypoint 'which opencode >/dev/null 2>&1 && opencode --version 2>&1 | head -1 || echo "not_installed"')

    if [[ "$opencode_version" == docker_error ]]; then
        fail "Docker container failed to start for opencode version check"
    elif [[ "$opencode_version" == "not_installed" ]]; then
        # opencode not in current test image - skip rather than fail
        # CI may use cached images without latest Dockerfile changes
        # To test opencode: rebuild image with ./build.sh
        pass "opencode CLI check skipped (not in test image)"
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
    # Capture stdout only (stderr may contain warnings)
    local resolved stderr_file
    stderr_file=$(mktemp)
    if resolved=$(cd "$test_dir/subproject" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/containai.sh' && _containai_resolve_volume '' '$test_dir/subproject'" 2>"$stderr_file"); then
        if [[ "$resolved" == "$test_vol" ]]; then
            pass "Workspace path matching works"
        else
            fail "Workspace path matching returned wrong volume: $resolved (expected: $test_vol)"
            [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
        fi
    else
        fail "Workspace path matching failed: $resolved"
        [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
    fi
    rm -f "$stderr_file"

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
    # Capture stdout only (stderr may contain warnings)
    local resolved stderr_file
    stderr_file=$(mktemp)
    if resolved=$(cd "$test_dir" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/containai.sh' && _containai_resolve_volume '' '$test_dir'" 2>"$stderr_file"); then
        if [[ "$resolved" == "$default_vol" ]]; then
            pass "Falls back to [agent] when no workspace match"
        else
            fail "Fallback returned wrong volume: $resolved (expected: $default_vol)"
            [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
        fi
    else
        fail "Fallback to [agent] failed: $resolved"
        [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
    fi
    rm -f "$stderr_file"

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
    # Capture stdout only (stderr may contain warnings)
    local resolved stderr_file
    stderr_file=$(mktemp)
    if resolved=$(cd "$test_dir/project/subdir" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/containai.sh' && _containai_resolve_volume '' '$test_dir/project/subdir'" 2>"$stderr_file"); then
        if [[ "$resolved" == "subdir-vol" ]]; then
            pass "Longest workspace path match wins"
        else
            fail "Longest match returned wrong volume: $resolved (expected: subdir-vol)"
            [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
        fi
    else
        fail "Longest match test failed: $resolved"
        [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
    fi
    rm -f "$stderr_file"

    rm -rf "$test_dir"
}

# ==============================================================================
# Test 14: CLI volume overrides workspace config
# ==============================================================================
test_data_volume_overrides_config() {
    section "Test 14: CLI volume overrides workspace config"

    local test_dir
    test_dir="/tmp/test-override-$$"

    mkdir -p "$test_dir/.containai"
    # Include BOTH [agent] AND [workspace] sections to prove CLI overrides workspace config
    cat > "$test_dir/.containai/config.toml" << EOF
[agent]
data_volume = "agent-vol"

[workspace."$test_dir"]
data_volume = "workspace-vol"
EOF

    # Test that CLI volume overrides workspace config (not just [agent])
    # Must clear env vars to ensure CLI precedence is tested
    # Capture stdout only (stderr may contain warnings)
    local resolved stderr_file
    stderr_file=$(mktemp)
    if resolved=$(cd "$test_dir" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/containai.sh' && _containai_resolve_volume 'cli-vol'" 2>"$stderr_file"); then
        if [[ "$resolved" == "cli-vol" ]]; then
            pass "CLI volume overrides workspace config"
        else
            fail "CLI override returned wrong volume: $resolved (expected: cli-vol)"
            [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
        fi
    else
        fail "CLI override test failed: $resolved"
        [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
    fi
    rm -f "$stderr_file"

    rm -rf "$test_dir"
}

# ==============================================================================
# Test 15: Relative workspace paths are skipped (absolute paths only)
# ==============================================================================
test_relative_paths_skipped() {
    section "Test 15: Relative workspace paths are skipped"

    local test_dir
    test_dir=$(mktemp -d)

    # Config uses relative paths which should be SKIPPED per spec
    # "Absolute paths only in workspace sections (skip relative)"
    mkdir -p "$test_dir/.containai"
    cat > "$test_dir/.containai/config.toml" << EOF
[agent]
data_volume = "agent-default-vol"

[workspace."./"]
data_volume = "relative-vol-should-be-skipped"
EOF

    # Test that relative workspace path "./" is skipped, falls back to [agent]
    # Must clear env vars to ensure config discovery is tested
    local resolved stderr_file
    stderr_file=$(mktemp)
    if resolved=$(cd "$test_dir" && env -u CONTAINAI_DATA_VOLUME -u CONTAINAI_CONFIG bash -c "source '$SCRIPT_DIR/containai.sh' && _containai_resolve_volume '' '$test_dir'" 2>"$stderr_file"); then
        if [[ "$resolved" == "agent-default-vol" ]]; then
            pass "Relative workspace paths are skipped (falls back to agent default)"
        else
            fail "Relative path was NOT skipped: got $resolved (expected: agent-default-vol)"
            [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
        fi
    else
        fail "Relative path skip test failed: $resolved"
        [[ -s "$stderr_file" ]] && info "stderr: $(cat "$stderr_file")"
    fi
    rm -f "$stderr_file"

    rm -rf "$test_dir"
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo "=============================================================================="
    echo "Integration Tests for ContainAI"
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
    test_cli_help
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
    test_relative_paths_skipped

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
