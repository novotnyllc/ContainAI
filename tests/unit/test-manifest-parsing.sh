#!/usr/bin/env bash
# ==============================================================================
# Unit tests for per-agent manifest parsing
# ==============================================================================
# Verifies:
# 1. parse-manifest.sh correctly parses entries from per-agent manifest files
# 2. parse-manifest.sh handles directory input (iterates *.toml in sorted order)
# 3. [agent] section parsing extracts name, binary, default_args, aliases, optional
# 4. parse-toml.py rejects invalid TOML syntax (validation layer)
# 5. gen-agent-wrappers.sh produces expected output for agents with default_args
# 6. gen-agent-wrappers.sh skips agents without default_args
# 7. gen-import-map.sh produces expected _IMPORT_SYNC_MAP format
# 8. check-manifest-consistency.sh validates manifests
#
# Note: parse-manifest.sh is a regex-based parser for speed; TOML validation
# is handled by parse-toml.py which check-manifest-consistency.sh invokes.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

assert_contains() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        test_pass
    else
        test_fail "$label: expected to contain '$expected', got '$actual'"
    fi
}

assert_not_contains() {
    local unexpected="$1"
    local actual="$2"
    local label="$3"
    if [[ "$actual" != *"$unexpected"* ]]; then
        test_pass
    else
        test_fail "$label: expected NOT to contain '$unexpected', got '$actual'"
    fi
}

# ==============================================================================
# Test: parse-manifest.sh parses single manifest file
# ==============================================================================
test_start "parse-manifest.sh parses single manifest file"
setup_tmpdir
cat > "$TEST_TMPDIR/test.toml" << 'EOF'
[agent]
name = "test-agent"
binary = "test-binary"
default_args = ["--arg1", "--arg2"]
aliases = ["alias1"]
optional = true

[[entries]]
source = ".test/config.json"
target = "test/config.json"
container_link = ".test/config.json"
flags = "fj"

[[entries]]
source = ".test/secret.json"
target = "test/secret.json"
container_link = ".test/secret.json"
flags = "fso"
EOF

output=$("$REPO_ROOT/src/scripts/parse-manifest.sh" "$TEST_TMPDIR/test.toml")
# Count non-empty lines to avoid miscounting empty output
entry_count=$(printf '%s\n' "$output" | sed '/^$/d' | wc -l | tr -d ' ')
if [[ "$entry_count" == "2" ]]; then
    test_pass
else
    test_fail "expected 2 entries, got $entry_count"
fi
teardown_tmpdir

# ==============================================================================
# Test: parse-manifest.sh handles directory input
# ==============================================================================
test_start "parse-manifest.sh handles directory input (sorted order)"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/manifests"
cat > "$TEST_TMPDIR/manifests/01-first.toml" << 'EOF'
[[entries]]
source = ".first/config"
target = "first/config"
container_link = ".first/config"
flags = "f"
EOF
cat > "$TEST_TMPDIR/manifests/02-second.toml" << 'EOF'
[[entries]]
source = ".second/config"
target = "second/config"
container_link = ".second/config"
flags = "f"
EOF

output=$("$REPO_ROOT/src/scripts/parse-manifest.sh" "$TEST_TMPDIR/manifests")
# First entry should be from 01-first.toml
first_line=$(printf '%s\n' "$output" | head -1)
if [[ "$first_line" == *".first/config"* ]]; then
    test_pass
else
    test_fail "expected first entry from 01-first.toml, got: $first_line"
fi
teardown_tmpdir

# ==============================================================================
# Test: parse-manifest.sh extracts optional flag
# ==============================================================================
test_start "parse-manifest.sh extracts optional flag from 'o' in flags"
setup_tmpdir
cat > "$TEST_TMPDIR/test.toml" << 'EOF'
[[entries]]
source = ".optional/config"
target = "optional/config"
container_link = ".optional/config"
flags = "fso"
EOF

output=$("$REPO_ROOT/src/scripts/parse-manifest.sh" "$TEST_TMPDIR/test.toml")
# Output format: source|target|container_link|flags|disabled|type|optional
optional_field=$(printf '%s' "$output" | cut -d'|' -f7)
if [[ "$optional_field" == "true" ]]; then
    test_pass
else
    test_fail "expected optional=true, got: $optional_field"
fi
teardown_tmpdir

# ==============================================================================
# Test: parse-manifest.sh skips [agent] section (doesn't emit it as entry)
# ==============================================================================
test_start "parse-manifest.sh skips [agent] section content"
setup_tmpdir
cat > "$TEST_TMPDIR/test.toml" << 'EOF'
[agent]
name = "test"
binary = "test"
default_args = ["--flag"]

[[entries]]
source = ".test/file"
target = "test/file"
container_link = ".test/file"
flags = "f"
EOF

output=$("$REPO_ROOT/src/scripts/parse-manifest.sh" "$TEST_TMPDIR/test.toml")
# Count non-empty lines to avoid miscounting empty output
entry_count=$(printf '%s\n' "$output" | sed '/^$/d' | wc -l | tr -d ' ')
# Should only have 1 entry (the [[entries]] section, not [agent])
if [[ "$entry_count" == "1" ]]; then
    test_pass
else
    test_fail "expected 1 entry (agent section skipped), got $entry_count"
fi
teardown_tmpdir

# ==============================================================================
# Test: gen-agent-wrappers.sh generates wrapper for agent with default_args
# ==============================================================================
test_start "gen-agent-wrappers.sh generates wrapper for agent with default_args"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/manifests"
cat > "$TEST_TMPDIR/manifests/10-test.toml" << 'EOF'
[agent]
name = "testagent"
binary = "testagent"
default_args = ["--autonomous"]
aliases = []
optional = false
EOF

output_file="$TEST_TMPDIR/output.sh"
gen_stderr="$TEST_TMPDIR/gen_stderr.txt"
if "$REPO_ROOT/src/scripts/gen-agent-wrappers.sh" "$TEST_TMPDIR/manifests" "$output_file" 2>"$gen_stderr"; then
    output=$(cat "$output_file")
    if [[ "$output" == *"testagent()"* && "$output" == *"--autonomous"* ]]; then
        test_pass
    else
        test_fail "expected testagent() function with --autonomous flag"
    fi
else
    test_fail "gen-agent-wrappers.sh failed: $(cat "$gen_stderr")"
fi
teardown_tmpdir

# ==============================================================================
# Test: gen-agent-wrappers.sh skips agent without default_args
# ==============================================================================
test_start "gen-agent-wrappers.sh skips agent without default_args"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/manifests"
cat > "$TEST_TMPDIR/manifests/10-no-args.toml" << 'EOF'
[agent]
name = "noargs"
binary = "noargs"
default_args = []
aliases = []
optional = false
EOF

output_file="$TEST_TMPDIR/output.sh"
gen_stderr="$TEST_TMPDIR/gen_stderr.txt"
if "$REPO_ROOT/src/scripts/gen-agent-wrappers.sh" "$TEST_TMPDIR/manifests" "$output_file" 2>"$gen_stderr"; then
    output=$(cat "$output_file")
    if [[ "$output" != *"noargs()"* ]]; then
        test_pass
    else
        test_fail "expected no noargs() function (empty default_args)"
    fi
else
    test_fail "gen-agent-wrappers.sh failed: $(cat "$gen_stderr")"
fi
teardown_tmpdir

# ==============================================================================
# Test: gen-agent-wrappers.sh handles optional agents with command -v guard
# ==============================================================================
test_start "gen-agent-wrappers.sh wraps optional agent with command -v guard"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/manifests"
cat > "$TEST_TMPDIR/manifests/10-optional.toml" << 'EOF'
[agent]
name = "optionalagent"
binary = "optionalagent"
default_args = ["--yolo"]
aliases = []
optional = true
EOF

output_file="$TEST_TMPDIR/output.sh"
gen_stderr="$TEST_TMPDIR/gen_stderr.txt"
if "$REPO_ROOT/src/scripts/gen-agent-wrappers.sh" "$TEST_TMPDIR/manifests" "$output_file" 2>"$gen_stderr"; then
    output=$(cat "$output_file")
    if [[ "$output" == *"if command -v optionalagent"* && "$output" == *"fi"* ]]; then
        test_pass
    else
        test_fail "expected command -v guard for optional agent"
    fi
else
    test_fail "gen-agent-wrappers.sh failed: $(cat "$gen_stderr")"
fi
teardown_tmpdir

# ==============================================================================
# Test: gen-agent-wrappers.sh generates alias functions
# ==============================================================================
test_start "gen-agent-wrappers.sh generates alias functions"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/manifests"
cat > "$TEST_TMPDIR/manifests/15-kimi.toml" << 'EOF'
[agent]
name = "kimi"
binary = "kimi"
default_args = ["--yolo"]
aliases = ["kimi-cli"]
optional = true
EOF

output_file="$TEST_TMPDIR/output.sh"
gen_stderr="$TEST_TMPDIR/gen_stderr.txt"
if "$REPO_ROOT/src/scripts/gen-agent-wrappers.sh" "$TEST_TMPDIR/manifests" "$output_file" 2>"$gen_stderr"; then
    output=$(cat "$output_file")
    # Should have both kimi() and kimi-cli() functions
    if [[ "$output" == *"kimi()"* && "$output" == *"kimi-cli()"* ]]; then
        test_pass
    else
        test_fail "expected both kimi() and kimi-cli() functions"
    fi
else
    test_fail "gen-agent-wrappers.sh failed: $(cat "$gen_stderr")"
fi
teardown_tmpdir

# ==============================================================================
# Test: gen-import-map.sh generates correct _IMPORT_SYNC_MAP format
# ==============================================================================
test_start "gen-import-map.sh generates correct _IMPORT_SYNC_MAP format"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/manifests"
cat > "$TEST_TMPDIR/manifests/10-test.toml" << 'EOF'
[[entries]]
source = ".test/config.json"
target = "test/config.json"
container_link = ".test/config.json"
flags = "fj"
EOF

output=$("$REPO_ROOT/src/scripts/gen-import-map.sh" "$TEST_TMPDIR/manifests")
if [[ "$output" == *'_IMPORT_SYNC_MAP=('* && "$output" == *'/source/.test/config.json:/target/test/config.json:fj'* ]]; then
    test_pass
else
    test_fail "expected _IMPORT_SYNC_MAP with correct entry format"
fi
teardown_tmpdir

# ==============================================================================
# Test: gen-import-map.sh skips disabled entries
# ==============================================================================
test_start "gen-import-map.sh skips disabled entries"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/manifests"
cat > "$TEST_TMPDIR/manifests/10-test.toml" << 'EOF'
[[entries]]
source = ".disabled/config"
target = "disabled/config"
container_link = ".disabled/config"
flags = "f"
disabled = true

[[entries]]
source = ".enabled/config"
target = "enabled/config"
container_link = ".enabled/config"
flags = "f"
EOF

output=$("$REPO_ROOT/src/scripts/gen-import-map.sh" "$TEST_TMPDIR/manifests")
if [[ "$output" != *"disabled/config"* && "$output" == *"enabled/config"* ]]; then
    test_pass
else
    test_fail "expected disabled entry to be skipped"
fi
teardown_tmpdir

# ==============================================================================
# Test: gen-import-map.sh skips g-flag entries (handled by git-config import)
# ==============================================================================
test_start "gen-import-map.sh skips g-flag entries (git-filter)"
setup_tmpdir
mkdir -p "$TEST_TMPDIR/manifests"
cat > "$TEST_TMPDIR/manifests/02-git.toml" << 'EOF'
[[entries]]
source = ".gitconfig"
target = "git/gitconfig"
container_link = ".gitconfig_imported"
flags = "fg"
EOF

output=$("$REPO_ROOT/src/scripts/gen-import-map.sh" "$TEST_TMPDIR/manifests")
if [[ "$output" != *"gitconfig"* ]]; then
    test_pass
else
    test_fail "expected g-flag entry to be skipped (handled by git-config import)"
fi
teardown_tmpdir

# ==============================================================================
# Test: parse-toml.py validates TOML syntax
# ==============================================================================
test_start "parse-toml.py validates TOML syntax (rejects invalid)"
setup_tmpdir
cat > "$TEST_TMPDIR/invalid.toml" << 'EOF'
[agent
name = "broken"
EOF

if ! python3 "$REPO_ROOT/src/parse-toml.py" --file "$TEST_TMPDIR/invalid.toml" --json 2>/dev/null; then
    test_pass
else
    test_fail "expected invalid TOML to be rejected"
fi
teardown_tmpdir

# ==============================================================================
# Test: parse-toml.py --emit-agents extracts agent section
# ==============================================================================
test_start "parse-toml.py --emit-agents extracts agent section"
setup_tmpdir
cat > "$TEST_TMPDIR/test.toml" << 'EOF'
[agent]
name = "testagent"
binary = "testagent"
default_args = ["--flag1", "--flag2"]
aliases = ["alt1", "alt2"]
optional = true
EOF

output=$(python3 "$REPO_ROOT/src/parse-toml.py" --file "$TEST_TMPDIR/test.toml" --emit-agents)
# JSON output uses compact format: "name":"testagent" (no spaces after colon)
if [[ "$output" == *'"name":"testagent"'* && "$output" == *'"optional":true'* ]]; then
    test_pass
else
    test_fail "expected agent section to be extracted correctly, got: $output"
fi
teardown_tmpdir

# ==============================================================================
# Test: parse-toml.py --emit-agents returns null for manifest without [agent]
# ==============================================================================
test_start "parse-toml.py --emit-agents returns null for manifest without [agent]"
setup_tmpdir
cat > "$TEST_TMPDIR/test.toml" << 'EOF'
[[entries]]
source = ".test/config"
target = "test/config"
container_link = ".test/config"
flags = "f"
EOF

output=$(python3 "$REPO_ROOT/src/parse-toml.py" --file "$TEST_TMPDIR/test.toml" --emit-agents)
if [[ "$output" == "null" ]]; then
    test_pass
else
    test_fail "expected 'null' for manifest without [agent] section, got: $output"
fi
teardown_tmpdir

# ==============================================================================
# Test: Real manifests are valid TOML (sanity check)
# ==============================================================================
test_start "Real manifests in src/manifests/ are valid TOML"
all_valid=1
manifest_found=0
# Use nullglob to handle empty directory case
shopt -s nullglob
for manifest in "$REPO_ROOT/src/manifests/"*.toml; do
    manifest_found=1
    if ! python3 "$REPO_ROOT/src/parse-toml.py" --file "$manifest" --json >/dev/null 2>&1; then
        all_valid=0
        printf '    Invalid: %s\n' "$(basename "$manifest")"
    fi
done
shopt -u nullglob
if [[ $manifest_found -eq 0 ]]; then
    test_fail "no manifest files found in src/manifests/"
elif [[ $all_valid -eq 1 ]]; then
    test_pass
else
    test_fail "some manifests have invalid TOML syntax"
fi

# ==============================================================================
# Test: check-manifest-consistency.sh passes
# ==============================================================================
test_start "check-manifest-consistency.sh passes on current manifests"
if "$REPO_ROOT/scripts/check-manifest-consistency.sh" >/dev/null 2>&1; then
    test_pass
else
    test_fail "check-manifest-consistency.sh failed"
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
