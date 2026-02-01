#!/usr/bin/env bash
# Unit tests for template path functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source full CLI to ensure _CAI_CONFIG_DIR is available before template.sh
# shellcheck source=../../src/containai.sh
source "$REPO_ROOT/src/containai.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TEST_TMPDIR=""
ORIGINAL_HOME=""

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

setup_tmpdir() {
    TEST_TMPDIR="$(mktemp -d)"
    ORIGINAL_HOME="$HOME"
}

teardown_tmpdir() {
    if [[ -n "$TEST_TMPDIR" ]] && [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
    if [[ -n "$ORIGINAL_HOME" ]]; then
        HOME="$ORIGINAL_HOME"
    fi
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [[ "$actual" == "$expected" ]]; then
        test_pass
    else
        test_fail "$label: expected '$expected', got '$actual'"
    fi
}

assert_success() {
    local result="$1"
    local label="$2"
    if [[ "$result" -eq 0 ]]; then
        test_pass
    else
        test_fail "$label: expected success (0), got $result"
    fi
}

assert_failure() {
    local result="$1"
    local label="$2"
    if [[ "$result" -ne 0 ]]; then
        test_pass
    else
        test_fail "$label: expected failure (non-zero), got 0"
    fi
}

# ==============================================================================
# Test: _cai_get_template_dir returns correct path
# ==============================================================================

test_start "_cai_get_template_dir returns templates directory"
result=$(_cai_get_template_dir)
expected="$HOME/.config/containai/templates"
assert_equal "$expected" "$result" "template dir path"

# ==============================================================================
# Test: _cai_get_template_path with default template
# ==============================================================================

test_start "_cai_get_template_path returns default template path"
result=$(_cai_get_template_path)
expected="$HOME/.config/containai/templates/default/Dockerfile"
assert_equal "$expected" "$result" "default template path"

# ==============================================================================
# Test: _cai_get_template_path with custom template name
# ==============================================================================

test_start "_cai_get_template_path returns custom template path"
result=$(_cai_get_template_path "my-custom-template")
expected="$HOME/.config/containai/templates/my-custom-template/Dockerfile"
assert_equal "$expected" "$result" "custom template path"

# ==============================================================================
# Test: _cai_validate_template_name accepts valid names
# ==============================================================================

test_start "_cai_validate_template_name accepts valid names"
valid_names=("default" "my-template" "template_v1" "Template.1" "a1b2c3")
all_passed=true
for name in "${valid_names[@]}"; do
    if ! _cai_validate_template_name "$name"; then
        test_fail "rejected valid name: $name"
        all_passed=false
        break
    fi
done
if $all_passed; then
    test_pass
fi

# ==============================================================================
# Test: _cai_validate_template_name rejects path traversal
# ==============================================================================

test_start "_cai_validate_template_name rejects path traversal"
invalid_names=("../etc" "a/b" ".." "." "/etc" "foo/bar/baz")
all_rejected=true
for name in "${invalid_names[@]}"; do
    if _cai_validate_template_name "$name" 2>/dev/null; then
        test_fail "accepted invalid name: $name"
        all_rejected=false
        break
    fi
done
if $all_rejected; then
    test_pass
fi

# ==============================================================================
# Test: _cai_validate_template_name rejects empty and invalid patterns
# ==============================================================================

test_start "_cai_validate_template_name rejects invalid patterns"
invalid_patterns=("" "_invalid" "-invalid" ".invalid" "in valid" "name@123")
all_rejected=true
for name in "${invalid_patterns[@]}"; do
    if _cai_validate_template_name "$name" 2>/dev/null; then
        test_fail "accepted invalid pattern: '$name'"
        all_rejected=false
        break
    fi
done
if $all_rejected; then
    test_pass
fi

# ==============================================================================
# Test: _cai_get_template_path rejects invalid names
# ==============================================================================

test_start "_cai_get_template_path rejects invalid names"
if _cai_get_template_path "../etc" 2>/dev/null; then
    test_fail "accepted path traversal"
else
    test_pass
fi

# ==============================================================================
# Test: _cai_ensure_template_dir creates base directory
# ==============================================================================

test_start "_cai_ensure_template_dir creates base directory"
setup_tmpdir
# Override _CAI_TEMPLATE_DIR for this test
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
_cai_ensure_template_dir
if [[ -d "$TEST_TMPDIR/templates" ]]; then
    test_pass
else
    test_fail "directory not created"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_ensure_template_dir creates named template directory
# ==============================================================================

test_start "_cai_ensure_template_dir creates named template directory"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
_cai_ensure_template_dir "mytest"
if [[ -d "$TEST_TMPDIR/templates/mytest" ]]; then
    test_pass
else
    test_fail "named directory not created"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_ensure_template_dir rejects invalid names
# ==============================================================================

test_start "_cai_ensure_template_dir rejects invalid names"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_ensure_template_dir "../escape" 2>/dev/null; then
    test_fail "accepted path traversal"
else
    test_pass
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_template_exists returns false for non-existent template
# ==============================================================================

test_start "_cai_template_exists returns false for non-existent"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
if _cai_template_exists "nonexistent"; then
    test_fail "returned true for non-existent"
else
    test_pass
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_template_exists returns true for existing template
# ==============================================================================

test_start "_cai_template_exists returns true for existing template"
setup_tmpdir
_CAI_TEMPLATE_DIR="$TEST_TMPDIR/templates"
mkdir -p "$TEST_TMPDIR/templates/existing"
printf '%s\n' "FROM scratch" > "$TEST_TMPDIR/templates/existing/Dockerfile"
if _cai_template_exists "existing"; then
    test_pass
else
    test_fail "returned false for existing template"
fi
teardown_tmpdir

# ==============================================================================
# Test: _cai_template_exists rejects invalid names
# ==============================================================================

test_start "_cai_template_exists rejects invalid names"
if _cai_template_exists "../etc" 2>/dev/null; then
    test_fail "accepted path traversal"
else
    test_pass
fi

# ==============================================================================
# Summary
# ==============================================================================

printf '\n==========================================\n'
printf 'Tests run: %s\n' "$TESTS_RUN"
printf 'Passed:    %s\n' "$TESTS_PASSED"
printf 'Failed:    %s\n' "$TESTS_FAILED"
printf '==========================================\n'

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
