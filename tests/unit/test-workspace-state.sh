#!/usr/bin/env bash
# Unit tests for workspace state persistence functions
set -euo pipefail

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required libraries
# shellcheck source=../../src/lib/core.sh
source "$REPO_ROOT/src/lib/core.sh"
# shellcheck source=../../src/lib/platform.sh
source "$REPO_ROOT/src/lib/platform.sh"
# shellcheck source=../../src/lib/config.sh
source "$REPO_ROOT/src/lib/config.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temp directory for test isolation
TEST_TMPDIR=""

# Test helper functions
test_start() {
    printf 'Testing: %s\n' "$1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
    printf '  PASS\n'
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    printf '  FAIL: %s\n' "$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    export XDG_CONFIG_HOME="$TEST_TMPDIR/config"
}

teardown() {
    if [[ -n "$TEST_TMPDIR" ]] && [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# ==============================================================================
# Test: _containai_user_config_path
# ==============================================================================

test_start "_containai_user_config_path returns XDG path"
setup
expected="$TEST_TMPDIR/config/containai/config.toml"
actual=$(_containai_user_config_path)
if [[ "$actual" == "$expected" ]]; then
    test_pass
else
    test_fail "expected '$expected', got '$actual'"
fi
teardown

# ==============================================================================
# Test: _containai_write_workspace_state creates directory with 0700
# ==============================================================================

test_start "_containai_write_workspace_state creates config directory with 0700"
setup
_containai_write_workspace_state "/tmp/test-workspace" "data_volume" "test-vol"
dir_perms=$(stat -c '%a' "$TEST_TMPDIR/config/containai" 2>/dev/null || stat -f '%Lp' "$TEST_TMPDIR/config/containai")
if [[ "$dir_perms" == "700" ]]; then
    test_pass
else
    test_fail "expected 700, got $dir_perms"
fi
teardown

# ==============================================================================
# Test: _containai_write_workspace_state creates file with 0600
# ==============================================================================

test_start "_containai_write_workspace_state creates config file with 0600"
setup
_containai_write_workspace_state "/tmp/test-workspace" "data_volume" "test-vol"
file_perms=$(stat -c '%a' "$TEST_TMPDIR/config/containai/config.toml" 2>/dev/null || stat -f '%Lp' "$TEST_TMPDIR/config/containai/config.toml")
if [[ "$file_perms" == "600" ]]; then
    test_pass
else
    test_fail "expected 600, got $file_perms"
fi
teardown

# ==============================================================================
# Test: _containai_write_workspace_state creates correct TOML structure
# ==============================================================================

test_start "_containai_write_workspace_state creates [workspace.\"path\"] table"
setup
_containai_write_workspace_state "/tmp/test-workspace" "data_volume" "test-vol"
if grep -q '^\[workspace\."/tmp/test-workspace"\]' "$TEST_TMPDIR/config/containai/config.toml"; then
    test_pass
else
    test_fail "workspace table not found in config"
    cat "$TEST_TMPDIR/config/containai/config.toml" >&2
fi
teardown

# ==============================================================================
# Test: _containai_read_workspace_state reads back written value
# ==============================================================================

test_start "_containai_read_workspace_state reads written value"
setup
_containai_write_workspace_state "/tmp/test-workspace" "data_volume" "test-vol"
result=$(_containai_read_workspace_state "/tmp/test-workspace")
if printf '%s' "$result" | grep -q '"data_volume":"test-vol"'; then
    test_pass
else
    test_fail "expected data_volume:test-vol, got: $result"
fi
teardown

# ==============================================================================
# Test: _containai_read_workspace_key convenience wrapper
# ==============================================================================

test_start "_containai_read_workspace_key returns specific key"
setup
_containai_write_workspace_state "/tmp/test-workspace" "container_name" "my-container"
result=$(_containai_read_workspace_key "/tmp/test-workspace" "container_name")
if [[ "$result" == "my-container" ]]; then
    test_pass
else
    test_fail "expected 'my-container', got '$result'"
fi
teardown

# ==============================================================================
# Test: parse-toml.py --set-workspace-key preserves comments
# ==============================================================================

test_start "parse-toml.py --set-workspace-key preserves comments"
setup
mkdir -p "$TEST_TMPDIR/config/containai"
cat > "$TEST_TMPDIR/config/containai/config.toml" << 'EOF'
# This is a comment that should be preserved
[agent]
default = "claude"

# Another comment
EOF
python3 "$REPO_ROOT/src/parse-toml.py" --file "$TEST_TMPDIR/config/containai/config.toml" \
    --set-workspace-key "/tmp/ws" "key1" "value1"
if grep -q '# This is a comment that should be preserved' "$TEST_TMPDIR/config/containai/config.toml" && \
   grep -q '# Another comment' "$TEST_TMPDIR/config/containai/config.toml"; then
    test_pass
else
    test_fail "comments were not preserved"
    cat "$TEST_TMPDIR/config/containai/config.toml" >&2
fi
teardown

# ==============================================================================
# Test: parse-toml.py --set-workspace-key preserves other sections
# ==============================================================================

test_start "parse-toml.py --set-workspace-key preserves other sections"
setup
mkdir -p "$TEST_TMPDIR/config/containai"
cat > "$TEST_TMPDIR/config/containai/config.toml" << 'EOF'
[agent]
default = "claude"
data_volume = "my-data"

[env]
FOO = "bar"
EOF
python3 "$REPO_ROOT/src/parse-toml.py" --file "$TEST_TMPDIR/config/containai/config.toml" \
    --set-workspace-key "/tmp/ws" "container" "test-container"
# Check agent section preserved
if grep -q 'default = "claude"' "$TEST_TMPDIR/config/containai/config.toml" && \
   grep -q 'data_volume = "my-data"' "$TEST_TMPDIR/config/containai/config.toml" && \
   grep -q 'FOO = "bar"' "$TEST_TMPDIR/config/containai/config.toml"; then
    test_pass
else
    test_fail "other sections were not preserved"
    cat "$TEST_TMPDIR/config/containai/config.toml" >&2
fi
teardown

# ==============================================================================
# Test: parse-toml.py --set-workspace-key updates existing key
# ==============================================================================

test_start "parse-toml.py --set-workspace-key updates existing key"
setup
mkdir -p "$TEST_TMPDIR/config/containai"
cat > "$TEST_TMPDIR/config/containai/config.toml" << 'EOF'
[workspace."/tmp/ws"]
container = "old-value"
EOF
python3 "$REPO_ROOT/src/parse-toml.py" --file "$TEST_TMPDIR/config/containai/config.toml" \
    --set-workspace-key "/tmp/ws" "container" "new-value"
if grep -q 'container = "new-value"' "$TEST_TMPDIR/config/containai/config.toml" && \
   ! grep -q 'container = "old-value"' "$TEST_TMPDIR/config/containai/config.toml"; then
    test_pass
else
    test_fail "key was not updated correctly"
    cat "$TEST_TMPDIR/config/containai/config.toml" >&2
fi
teardown

# ==============================================================================
# Test: Empty value is allowed
# ==============================================================================

test_start "_containai_write_workspace_state allows empty value"
setup
if _containai_write_workspace_state "/tmp/test-workspace" "agent" ""; then
    # Verify it was written
    if grep -q 'agent = ""' "$TEST_TMPDIR/config/containai/config.toml"; then
        test_pass
    else
        test_fail "empty value not written correctly"
        cat "$TEST_TMPDIR/config/containai/config.toml" >&2
    fi
else
    test_fail "function returned error for empty value"
fi
teardown

# ==============================================================================
# Test: Mutual exclusion of options
# ==============================================================================

test_start "parse-toml.py rejects --set-workspace-key with --json"
setup
mkdir -p "$TEST_TMPDIR/config/containai"
touch "$TEST_TMPDIR/config/containai/config.toml"
if python3 "$REPO_ROOT/src/parse-toml.py" --file "$TEST_TMPDIR/config/containai/config.toml" \
    --set-workspace-key "/tmp/ws" "key" "val" --json 2>/dev/null; then
    test_fail "should have rejected mutually exclusive options"
else
    test_pass
fi
teardown

# ==============================================================================
# Summary
# ==============================================================================

printf '\n========================================\n'
printf 'Tests run: %d\n' "$TESTS_RUN"
printf 'Passed: %d\n' "$TESTS_PASSED"
printf 'Failed: %d\n' "$TESTS_FAILED"
printf '========================================\n'

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
