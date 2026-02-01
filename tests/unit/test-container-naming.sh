#!/usr/bin/env bash
# Unit tests for container naming
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../src/lib/container.sh
source "$REPO_ROOT/src/lib/container.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TEST_TMPDIR=""

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
}

teardown_tmpdir() {
    if [[ -n "$TEST_TMPDIR" ]] && [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
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

# ==============================================================================
# Test: git repo uses branch name
# ==============================================================================

test_start "_containai_container_name uses repo and branch leaf"
setup_tmpdir
repo_dir="$TEST_TMPDIR/MyRepo"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q
git -C "$repo_dir" config user.email "test@example.com"
git -C "$repo_dir" config user.name "Test User"
git -C "$repo_dir" config commit.gpgsign false
printf '%s\n' "test" > "$repo_dir/file.txt"
git -C "$repo_dir" add file.txt
git -C "$repo_dir" commit -q -m "init"
git -C "$repo_dir" checkout -q -b "feature/One"
result=$(_containai_container_name "$repo_dir")
# New format: {repo}-{branch_leaf} (no containai- prefix, branch leaf = last segment)
assert_equal "myrepo-one" "$result" "repo/branch leaf name"
teardown_tmpdir

# ==============================================================================
# Test: detached HEAD uses short SHA
# ==============================================================================

test_start "_containai_container_name uses 'detached' token on detached HEAD"
setup_tmpdir
repo_dir="$TEST_TMPDIR/MyRepo"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q
git -C "$repo_dir" config user.email "test@example.com"
git -C "$repo_dir" config user.name "Test User"
git -C "$repo_dir" config commit.gpgsign false
printf '%s\n' "test" > "$repo_dir/file.txt"
git -C "$repo_dir" add file.txt
git -C "$repo_dir" commit -q -m "init"
git -C "$repo_dir" checkout -q --detach
result=$(_containai_container_name "$repo_dir")
# New format: {repo}-detached (no hashes per spec)
assert_equal "myrepo-detached" "$result" "detached HEAD"
teardown_tmpdir

# ==============================================================================
# Test: non-git directory uses nogit branch
# ==============================================================================

test_start "_containai_container_name uses nogit for non-git directory"
setup_tmpdir
nogit_dir="$TEST_TMPDIR/NoGit"
mkdir -p "$nogit_dir"
result=$(_containai_container_name "$nogit_dir")
# New format: {repo}-nogit (no containai- prefix)
assert_equal "nogit-nogit" "$result" "non-git directory"
teardown_tmpdir

# ==============================================================================
# Test: long names truncate to 24 chars
# ==============================================================================

test_start "_containai_container_name truncates to 24 chars"
setup_tmpdir
long_repo="$(printf 'r%.0s' {1..40})"
long_branch="$(printf 'b%.0s' {1..40})"
repo_dir="$TEST_TMPDIR/$long_repo"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q
git -C "$repo_dir" config user.email "test@example.com"
git -C "$repo_dir" config user.name "Test User"
git -C "$repo_dir" config commit.gpgsign false
printf '%s\n' "test" > "$repo_dir/file.txt"
git -C "$repo_dir" add file.txt
git -C "$repo_dir" commit -q -m "init"
git -C "$repo_dir" checkout -q -b "$long_branch"
result=$(_containai_container_name "$repo_dir")
# New format: {repo}-{branch} max 24 chars (no containai- prefix)
if [[ ${#result} -le 24 ]]; then
    if [[ "$result" != *- && "$result" == *-* ]]; then
        repo_part="${result%%-*}"
        branch_part="${result#*-}"
        if [[ -n "$repo_part" && -n "$branch_part" ]]; then
            test_pass
        else
            test_fail "expected {repo}-{branch}, got $result"
        fi
    else
        test_fail "truncation format invalid: $result"
    fi
else
    test_fail "expected length <= 24, got ${#result} ($result)"
fi
teardown_tmpdir

# ==============================================================================
# Test: sanitization preserves format with empty segments
# ==============================================================================

test_start "_containai_container_name preserves format when sanitization empties segments"
setup_tmpdir
repo_dir="$TEST_TMPDIR/___"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q
git -C "$repo_dir" config user.email "test@example.com"
git -C "$repo_dir" config user.name "Test User"
git -C "$repo_dir" config commit.gpgsign false
printf '%s\n' "test" > "$repo_dir/file.txt"
git -C "$repo_dir" add file.txt
git -C "$repo_dir" commit -q -m "init"
git -C "$repo_dir" checkout -q -b "___"
result=$(_containai_container_name "$repo_dir")
# New format: {repo}-{branch} (no containai- prefix)
assert_equal "repo-branch" "$result" "sanitization fallback"
teardown_tmpdir

# ==============================================================================
# Test: branch leaf extraction from multi-segment branch
# ==============================================================================

test_start "_containai_container_name extracts branch leaf from multi-segment branches"
setup_tmpdir
repo_dir="$TEST_TMPDIR/my-app"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q
git -C "$repo_dir" config user.email "test@example.com"
git -C "$repo_dir" config user.name "Test User"
git -C "$repo_dir" config commit.gpgsign false
printf '%s\n' "test" > "$repo_dir/file.txt"
git -C "$repo_dir" add file.txt
git -C "$repo_dir" commit -q -m "init"
git -C "$repo_dir" checkout -q -b "feat/ui/button"
result=$(_containai_container_name "$repo_dir")
# Branch feat/ui/button → leaf = button
assert_equal "my-app-button" "$result" "multi-segment branch leaf"
teardown_tmpdir

# ==============================================================================
# Test: simple branch (no slashes) preserved
# ==============================================================================

test_start "_containai_container_name preserves simple branch names"
setup_tmpdir
repo_dir="$TEST_TMPDIR/project"
mkdir -p "$repo_dir"
git -C "$repo_dir" init -q
git -C "$repo_dir" config user.email "test@example.com"
git -C "$repo_dir" config user.name "Test User"
git -C "$repo_dir" config commit.gpgsign false
printf '%s\n' "test" > "$repo_dir/file.txt"
git -C "$repo_dir" add file.txt
git -C "$repo_dir" commit -q -m "init"
git -C "$repo_dir" checkout -q -b "develop"
result=$(_containai_container_name "$repo_dir")
# Branch develop → leaf = develop
assert_equal "project-develop" "$result" "simple branch name"
teardown_tmpdir

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
