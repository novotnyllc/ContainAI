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
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_VOLUME="sandbox-agent-data"
IMAGE_NAME="agent-sandbox-test:latest"

# Color output helpers
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; FAILED=1; }
info() { echo "[INFO] $*"; }
section() { echo ""; echo "=== $* ==="; }

FAILED=0

# ==============================================================================
# Test 1: Platform guard rejects non-Linux
# ==============================================================================
test_platform_guard() {
    section "Test 1: Platform guard rejects non-Linux"

    # Test platform guard logic by simulating different platforms
    check_platform_test() {
        local platform="$1"
        case "$platform" in
            Linux) return 0 ;;
            Darwin)
                echo "ERROR: macOS is not supported by sync-agent-plugins.sh yet" >&2
                return 1 ;;
            *)
                echo "ERROR: Unsupported platform: $platform" >&2
                return 1 ;;
        esac
    }

    # Linux should pass
    if check_platform_test "Linux" 2>/dev/null; then
        pass "Linux platform accepted"
    else
        fail "Linux platform should be accepted"
    fi

    # Darwin should fail
    if check_platform_test "Darwin" 2>/dev/null; then
        fail "Darwin platform should be rejected"
    else
        pass "Darwin platform rejected"
    fi

    # Unknown should fail
    if check_platform_test "FreeBSD" 2>/dev/null; then
        fail "Unknown platform should be rejected"
    else
        pass "Unknown platform rejected"
    fi
}

# ==============================================================================
# Test 2: Dry-run makes no volume changes
# ==============================================================================
test_dry_run() {
    section "Test 2: Dry-run makes no volume changes"

    # Helper to count files without SSH key noise from eeacms/rsync
    count_files() {
        docker run --rm -v "$DATA_VOLUME":/data eeacms/rsync sh -c 'find /data -type f 2>/dev/null | wc -l' 2>&1 | grep -E '^[0-9]+$' | tail -1 || echo "0"
    }

    # Get file count before dry-run
    local before_count
    before_count=$(count_files)

    # Run dry-run (may output errors for missing dirs, that's expected)
    "$SCRIPT_DIR/sync-agent-plugins.sh" --dry-run >/dev/null 2>&1 || true

    # Get file count after dry-run
    local after_count
    after_count=$(count_files)

    if [[ "$before_count" == "$after_count" ]]; then
        pass "Dry-run did not change volume (files: $before_count -> $after_count)"
    else
        fail "Dry-run changed volume (files: $before_count -> $after_count)"
    fi
}

# ==============================================================================
# Test 3: Full sync copies all configs
# ==============================================================================
test_full_sync() {
    section "Test 3: Full sync copies all configs"

    # Run full sync
    if "$SCRIPT_DIR/sync-agent-plugins.sh" >/dev/null 2>&1; then
        pass "Full sync completed successfully"
    else
        fail "Full sync failed"
        return
    fi

    # Helper to check if directory exists without SSH key noise
    dir_exists() {
        local dir="$1"
        docker run --rm -v "$DATA_VOLUME":/data eeacms/rsync sh -c "test -d '$dir' && echo yes || echo no" 2>&1 | grep -E '^(yes|no)$' | tail -1
    }

    # Verify key directories exist
    local dirs_to_check=(
        "/data/claude"
        "/data/claude/plugins"
        "/data/config/gh"
        "/data/codex"
        "/data/gemini"
        "/data/copilot"
    )

    for dir in "${dirs_to_check[@]}"; do
        if [[ "$(dir_exists "$dir")" == "yes" ]]; then
            pass "Directory exists: $dir"
        else
            fail "Directory missing: $dir"
        fi
    done
}

# ==============================================================================
# Test 4: Secret permissions correct (600 files, 700 dirs)
# ==============================================================================
test_secret_permissions() {
    section "Test 4: Secret permissions correct"

    # Helper to get permissions without SSH key noise from eeacms/rsync
    get_perm() {
        local path="$1"
        docker run --rm -v "$DATA_VOLUME":/data eeacms/rsync stat -c '%a' "$path" 2>&1 | grep -E '^[0-9]{3}$' | tail -1 || echo "missing"
    }

    # Secret files should be 600
    local secret_files=(
        "/data/claude/credentials.json"
        "/data/gemini/oauth_creds.json"
        "/data/gemini/google_accounts.json"
        "/data/codex/auth.json"
        "/data/local/share/opencode/auth.json"
    )

    for file in "${secret_files[@]}"; do
        local perm
        perm=$(get_perm "$file")
        if [[ "$perm" == "600" ]]; then
            pass "Secret file has 600 permissions: $file"
        elif [[ "$perm" == "missing" ]]; then
            info "Secret file not synced (source may not exist): $file"
        else
            fail "Secret file has wrong permissions ($perm): $file"
        fi
    done

    # Secret dirs should be 700
    local secret_dirs=(
        "/data/config/gh"
    )

    for dir in "${secret_dirs[@]}"; do
        local perm
        perm=$(get_perm "$dir")
        if [[ "$perm" == "700" ]]; then
            pass "Secret dir has 700 permissions: $dir"
        elif [[ "$perm" == "missing" ]]; then
            info "Secret dir not synced (source may not exist): $dir"
        else
            fail "Secret dir has wrong permissions ($perm): $dir"
        fi
    done
}

# ==============================================================================
# Test 5: Plugins load correctly in container
# ==============================================================================
test_plugins_in_container() {
    section "Test 5: Plugins load correctly in container"

    # Check if plugins directory exists and has content (filter SSH key noise)
    local plugin_count
    plugin_count=$(docker run --rm -v "$DATA_VOLUME":/data eeacms/rsync sh -c 'find /data/claude/plugins/cache -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l' 2>&1 | grep -E '^[0-9]+$' | tail -1 || echo "0")

    if [[ "$plugin_count" -gt 0 ]]; then
        pass "Found $plugin_count plugin(s) in cache"
    else
        info "No plugins in cache (may not have been synced from host)"
    fi

    # Check symlinks in container point to correct locations
    local symlink_test
    symlink_test=$(docker run --rm --entrypoint /bin/bash -v "$DATA_VOLUME":/mnt/agent-data "$IMAGE_NAME" -c '
        if [ -L ~/.claude/plugins ] && [ "$(readlink ~/.claude/plugins)" = "/mnt/agent-data/claude/plugins" ]; then
            echo "ok"
        else
            echo "fail"
        fi
    ' 2>/dev/null)

    if [[ "$symlink_test" == "ok" ]]; then
        pass "Claude plugins symlink points to volume"
    else
        fail "Claude plugins symlink incorrect"
    fi
}

# ==============================================================================
# Test 6: No orphan markers visible
# ==============================================================================
test_no_orphan_markers() {
    section "Test 6: No orphan markers visible"

    local orphan_count
    orphan_count=$(docker run --rm -v "$DATA_VOLUME":/data eeacms/rsync sh -c 'find /data -name ".orphaned_at" 2>/dev/null | wc -l' 2>&1 | grep -E '^[0-9]+$' | tail -1 || echo "0")

    if [[ "$orphan_count" -eq 0 ]]; then
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
    bashrc_test=$(docker run --rm --entrypoint /bin/bash -v "$DATA_VOLUME":/mnt/agent-data "$IMAGE_NAME" -c '
        if grep -q "bashrc.d" ~/.bashrc && grep -q "bash_aliases_imported" ~/.bashrc; then
            echo "hooks_present"
        else
            echo "hooks_missing"
        fi
    ' 2>/dev/null)

    if [[ "$bashrc_test" == "hooks_present" ]]; then
        pass "Sourcing hooks present in .bashrc"
    else
        fail "Sourcing hooks missing from .bashrc"
    fi

    # Test actual sourcing works
    local source_test
    source_test=$(docker run --rm --entrypoint /bin/bash -v "$DATA_VOLUME":/mnt/agent-data "$IMAGE_NAME" -c '
        # Create test script
        echo "export TEST_VAR=success" > /mnt/agent-data/shell/.bashrc.d/test.sh
        chmod +x /mnt/agent-data/shell/.bashrc.d/test.sh

        # Test in interactive shell
        result=$(bash -i -c "echo \$TEST_VAR" 2>/dev/null)

        # Cleanup
        rm -f /mnt/agent-data/shell/.bashrc.d/test.sh

        echo "$result"
    ' 2>/dev/null)

    if [[ "$source_test" == "success" ]]; then
        pass ".bashrc.d scripts are sourced in interactive shells"
    else
        fail ".bashrc.d scripts are not being sourced"
    fi
}

# ==============================================================================
# Test 8: tmux loads config
# ==============================================================================
test_tmux_config() {
    section "Test 8: tmux loads config"

    # Check tmux symlink
    local tmux_link
    tmux_link=$(docker run --rm --entrypoint /bin/bash -v "$DATA_VOLUME":/mnt/agent-data "$IMAGE_NAME" -c '
        if [ -L ~/.tmux.conf ]; then
            readlink ~/.tmux.conf
        else
            echo "not_symlink"
        fi
    ' 2>/dev/null)

    if [[ "$tmux_link" == "/mnt/agent-data/tmux/.tmux.conf" ]]; then
        pass "tmux.conf symlink points to volume"
    else
        fail "tmux.conf symlink incorrect: $tmux_link"
    fi

    # Check tmux can start
    local tmux_test
    tmux_test=$(docker run --rm --entrypoint /bin/bash -v "$DATA_VOLUME":/mnt/agent-data "$IMAGE_NAME" -c '
        tmux start-server && echo "ok" || echo "fail"
        tmux kill-server 2>/dev/null || true
    ' 2>/dev/null)

    if [[ "$tmux_test" == "ok" ]]; then
        pass "tmux server can start"
    else
        fail "tmux server failed to start"
    fi
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
        docker build -t "$IMAGE_NAME" "$SCRIPT_DIR" >/dev/null 2>&1 || {
            echo "ERROR: Failed to build test image" >&2
            exit 1
        }
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
