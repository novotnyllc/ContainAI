#!/usr/bin/env bash
# Unit tests for _import_rewrite_excludes function
set -euo pipefail

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the import library
# shellcheck source=../../src/lib/import.sh
source "$REPO_ROOT/src/lib/import.sh"

# Cross-platform base64 decode helper (GNU uses -d, macOS uses -D)
b64decode() {
    if base64 --help 2>&1 | grep -q -- '-d'; then
        base64 -d
    else
        base64 -D
    fi
}

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
test_start() {
    echo "Testing: $1"
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_pass() {
    echo "  PASS"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    echo "  FAIL: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# ==============================================================================
# Test: _import_has_glob_metachar
# ==============================================================================

test_start "has_glob_metachar - asterisk"
if _import_has_glob_metachar "*.log"; then
    test_pass
else
    test_fail "*.log should have glob metachar"
fi

test_start "has_glob_metachar - question mark"
if _import_has_glob_metachar "file?.txt"; then
    test_pass
else
    test_fail "file?.txt should have glob metachar"
fi

test_start "has_glob_metachar - bracket"
if _import_has_glob_metachar "[abc].txt"; then
    test_pass
else
    test_fail "[abc].txt should have glob metachar"
fi

test_start "has_glob_metachar - no metachar"
if ! _import_has_glob_metachar "claude"; then
    test_pass
else
    test_fail "claude should NOT have glob metachar"
fi

test_start "has_glob_metachar - path without metachar"
if ! _import_has_glob_metachar "claude/plugins/.system"; then
    test_pass
else
    test_fail "claude/plugins/.system should NOT have glob metachar"
fi

# ==============================================================================
# Test: _import_rewrite_excludes - Global globs
# ==============================================================================

test_start "rewrite_excludes - global glob applies to all entries"
excludes="*.log"
entries="/source/.claude/plugins:/target/claude/plugins:d
/source/.codex/skills:/target/codex/skills:dx"
output=$(_import_rewrite_excludes "$excludes" "$entries" 2>/dev/null)
# Both entries should have *.log in their excludes (base64 encoded)
if echo "$output" | grep -q "^/source/.claude/plugins:/target/claude/plugins:d:" && \
   echo "$output" | grep -q "^/source/.codex/skills:/target/codex/skills:dx:"; then
    # Verify the base64-encoded excludes contain *.log
    first_excludes=$(echo "$output" | head -1 | cut -d: -f4)
    if [[ -n "$first_excludes" ]] && echo "$first_excludes" | b64decode | grep -q '^\*\.log$'; then
        test_pass
    else
        test_fail "Global glob *.log not found in per-entry excludes"
    fi
else
    test_fail "Expected both entries in output"
fi

# ==============================================================================
# Test: _import_rewrite_excludes - Root prefix skips entries
# ==============================================================================

test_start "rewrite_excludes - root prefix skips matching entries"
excludes="claude"
entries="/source/.claude/plugins:/target/claude/plugins:d
/source/.codex/skills:/target/codex/skills:dx"
output=$(_import_rewrite_excludes "$excludes" "$entries" 2>/dev/null)
# Only codex entry should remain (claude is skipped)
if echo "$output" | grep -q "^/source/.codex/skills:" && \
   ! echo "$output" | grep -q "^/source/.claude/plugins:"; then
    test_pass
else
    test_fail "Root prefix 'claude' should skip claude entries"
fi

test_start "rewrite_excludes - root prefix SKIP message"
excludes="claude"
entries="/source/.claude/plugins:/target/claude/plugins:d"
stderr_output=$(_import_rewrite_excludes "$excludes" "$entries" 2>&1 >/dev/null)
if echo "$stderr_output" | grep -q "\[SKIP\].*claude/plugins"; then
    test_pass
else
    test_fail "Expected [SKIP] message for claude entry"
fi

# ==============================================================================
# Test: _import_rewrite_excludes - Path pattern child rewrites
# ==============================================================================

test_start "rewrite_excludes - path pattern child rewrites to relative"
excludes="claude/plugins/.system"
entries="/source/.claude/plugins:/target/claude/plugins:d"
output=$(_import_rewrite_excludes "$excludes" "$entries" 2>/dev/null)
# Entry should have .system in its excludes (rewritten from claude/plugins/.system)
if echo "$output" | grep -q "^/source/.claude/plugins:/target/claude/plugins:d:"; then
    excludes_b64=$(echo "$output" | cut -d: -f4)
    if [[ -n "$excludes_b64" ]]; then
        decoded=$(echo "$excludes_b64" | b64decode)
        if echo "$decoded" | grep -q "^\.system$"; then
            test_pass
        else
            test_fail "Expected .system in rewritten excludes, got: $decoded"
        fi
    else
        test_fail "Expected non-empty excludes_b64"
    fi
else
    test_fail "Expected entry in output"
fi

# ==============================================================================
# Test: _import_rewrite_excludes - Path pattern exact match skips
# ==============================================================================

test_start "rewrite_excludes - path pattern exact match skips entry"
excludes="claude/plugins"
entries="/source/.claude/plugins:/target/claude/plugins:d"
output=$(_import_rewrite_excludes "$excludes" "$entries" 2>/dev/null)
# Entry should be skipped (exact match)
if [[ -z "$output" ]] || ! echo "$output" | grep -q "^/source/.claude/plugins:"; then
    test_pass
else
    test_fail "Expected entry to be skipped for exact path match"
fi

# ==============================================================================
# Test: _import_rewrite_excludes - Trailing slash handling
# ==============================================================================

test_start "rewrite_excludes - trailing slash pattern exact match skips entry"
excludes="claude/plugins/"
entries="/source/.claude/plugins:/target/claude/plugins:d"
output=$(_import_rewrite_excludes "$excludes" "$entries" 2>/dev/null)
# Entry should be skipped (exact match after trailing slash normalization)
if [[ -z "$output" ]] || ! echo "$output" | grep -q "^/source/.claude/plugins:"; then
    test_pass
else
    test_fail "Expected entry to be skipped for trailing slash pattern"
fi

test_start "rewrite_excludes - trailing slash in child pattern rewrites correctly"
excludes="claude/plugins/.system/"
entries="/source/.claude/plugins:/target/claude/plugins:d"
output=$(_import_rewrite_excludes "$excludes" "$entries" 2>/dev/null)
# Entry should have .system in its excludes (normalized from .system/)
if echo "$output" | grep -q "^/source/.claude/plugins:/target/claude/plugins:d:"; then
    excludes_b64=$(echo "$output" | cut -d: -f4)
    if [[ -n "$excludes_b64" ]]; then
        decoded=$(echo "$excludes_b64" | b64decode)
        if echo "$decoded" | grep -q "^\.system$"; then
            test_pass
        else
            test_fail "Expected .system (normalized), got: $decoded"
        fi
    else
        test_fail "Expected non-empty excludes_b64"
    fi
else
    test_fail "Expected entry in output"
fi

# ==============================================================================
# Test: _import_rewrite_excludes - Path pattern parent match skips
# ==============================================================================

test_start "rewrite_excludes - path pattern parent skips child entry"
excludes="claude"
entries="/source/.claude/plugins:/target/claude/plugins:d"
output=$(_import_rewrite_excludes "$excludes" "$entries" 2>/dev/null)
# Entry should be skipped (parent match)
if [[ -z "$output" ]] || ! echo "$output" | grep -q "^/source/.claude/plugins:"; then
    test_pass
else
    test_fail "Expected entry to be skipped when pattern is parent"
fi

# ==============================================================================
# Test: _import_rewrite_excludes - Unmatched pattern warning
# ==============================================================================

test_start "rewrite_excludes - unmatched pattern warning"
excludes="nonexistent/path"
entries="/source/.claude/plugins:/target/claude/plugins:d"
stderr_output=$(_import_rewrite_excludes "$excludes" "$entries" 2>&1 >/dev/null)
if echo "$stderr_output" | grep -q "\[WARN\].*Unmatched exclude pattern.*nonexistent/path"; then
    test_pass
else
    test_fail "Expected [WARN] for unmatched pattern"
fi

# ==============================================================================
# Test: _import_rewrite_excludes - Multiple patterns
# ==============================================================================

test_start "rewrite_excludes - multiple patterns combined"
excludes="*.log
*.tmp
codex/skills/.system"
entries="/source/.claude/plugins:/target/claude/plugins:d
/source/.codex/skills:/target/codex/skills:dx"
output=$(_import_rewrite_excludes "$excludes" "$entries" 2>/dev/null)
# Both entries should exist
if echo "$output" | grep -q "^/source/.claude/plugins:" && \
   echo "$output" | grep -q "^/source/.codex/skills:"; then
    # Claude entry should have *.log and *.tmp
    claude_excludes=$(echo "$output" | grep "^/source/.claude/plugins:" | cut -d: -f4)
    if [[ -n "$claude_excludes" ]]; then
        decoded=$(echo "$claude_excludes" | b64decode)
        if echo "$decoded" | grep -q '^\*\.log$' && echo "$decoded" | grep -q '^\*\.tmp$'; then
            # Codex entry should have *.log, *.tmp, and .system
            codex_excludes=$(echo "$output" | grep "^/source/.codex/skills:" | cut -d: -f4)
            if [[ -n "$codex_excludes" ]]; then
                decoded_codex=$(echo "$codex_excludes" | b64decode)
                if echo "$decoded_codex" | grep -q '^\*\.log$' && \
                   echo "$decoded_codex" | grep -q '^\*\.tmp$' && \
                   echo "$decoded_codex" | grep -q '^\.system$'; then
                    test_pass
                else
                    test_fail "Codex entry missing expected excludes: $decoded_codex"
                fi
            else
                test_fail "Codex entry has empty excludes"
            fi
        else
            test_fail "Claude entry missing expected excludes: $decoded"
        fi
    else
        test_fail "Claude entry has empty excludes"
    fi
else
    test_fail "Expected both entries in output"
fi

# ==============================================================================
# Test: _import_rewrite_excludes - No excludes passthrough
# ==============================================================================

test_start "rewrite_excludes - no excludes produces entries with empty field"
excludes=""
entries="/source/.claude/plugins:/target/claude/plugins:d"
output=$(_import_rewrite_excludes "$excludes" "$entries" 2>/dev/null)
if echo "$output" | grep -q "^/source/.claude/plugins:/target/claude/plugins:d:$"; then
    test_pass
else
    test_fail "Expected entry with empty 4th field when no excludes"
fi

# ==============================================================================
# Summary
# ==============================================================================

echo ""
echo "=========================================="
echo "Tests run: $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "=========================================="

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
