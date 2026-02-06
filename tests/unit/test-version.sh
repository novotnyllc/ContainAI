#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

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

source_version_lib() {
    # shellcheck source=../../src/lib/version.sh
    source "$REPO_ROOT/src/lib/version.sh"
}

test_get_version_from_same_dir_layout() {
    test_start "_cai_get_version reads VERSION from _CAI_SCRIPT_DIR/VERSION"

    local tmpdir result
    tmpdir="$(mktemp -d)"
    printf '%s\n' "1.2.3-test" > "$tmpdir/VERSION"

    _CAI_SCRIPT_DIR="$tmpdir"
    if result="$(_cai_get_version)"; then
        if [[ "$result" == "1.2.3-test" ]]; then
            test_pass
        else
            test_fail "expected 1.2.3-test, got '$result'"
        fi
    else
        test_fail "_cai_get_version returned non-zero"
    fi

    rm -rf "$tmpdir"
}

test_get_version_from_parent_dir_layout() {
    test_start "_cai_get_version reads VERSION from _CAI_SCRIPT_DIR/../VERSION"

    local tmpdir srcdir result
    tmpdir="$(mktemp -d)"
    srcdir="$tmpdir/src"
    mkdir -p "$srcdir"
    printf '%s\n' "9.9.9-test" > "$tmpdir/VERSION"

    _CAI_SCRIPT_DIR="$srcdir"
    if result="$(_cai_get_version)"; then
        if [[ "$result" == "9.9.9-test" ]]; then
            test_pass
        else
            test_fail "expected 9.9.9-test, got '$result'"
        fi
    else
        test_fail "_cai_get_version returned non-zero"
    fi

    rm -rf "$tmpdir"
}

source_version_lib
test_get_version_from_same_dir_layout
test_get_version_from_parent_dir_layout

printf '\nSummary: %s run, %s passed, %s failed\n' "$TESTS_RUN" "$TESTS_PASSED" "$TESTS_FAILED"
if [[ "$TESTS_FAILED" -ne 0 ]]; then
    exit 1
fi
