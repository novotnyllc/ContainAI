#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# test-devcontainer-feature.sh - Unit tests for ContainAI devcontainer feature
#
# Tests feature structure, script syntax, and configuration.
# Does NOT require Docker (integration tests do).
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FEATURE_DIR="$REPO_ROOT/src/devcontainer/feature"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

passed=0
failed=0

pass() {
    printf "${GREEN}✓${NC} %s\n" "$1"
    ((passed++)) || true
}

fail() {
    printf "${RED}✗${NC} %s\n" "$1"
    ((failed++)) || true
}

# ══════════════════════════════════════════════════════════════════════
# Test: Feature directory structure
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Feature Structure Tests ===\n'

required_files=(
    "devcontainer-feature.json"
    "install.sh"
    "verify-sysbox.sh"
    "init.sh"
    "start.sh"
    "link-spec.json"
)

for file in "${required_files[@]}"; do
    if [[ -f "$FEATURE_DIR/$file" ]]; then
        pass "File exists: $file"
    else
        fail "Missing file: $file"
    fi
done

# ══════════════════════════════════════════════════════════════════════
# Test: Scripts are executable
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Executable Tests ===\n'

executable_scripts=(
    "install.sh"
    "verify-sysbox.sh"
    "init.sh"
    "start.sh"
)

for script in "${executable_scripts[@]}"; do
    if [[ -x "$FEATURE_DIR/$script" ]]; then
        pass "Executable: $script"
    else
        fail "Not executable: $script"
    fi
done

# ══════════════════════════════════════════════════════════════════════
# Test: devcontainer-feature.json validity
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Feature JSON Tests ===\n'

if python3 -c "import json; json.load(open('$FEATURE_DIR/devcontainer-feature.json'))" 2>/dev/null; then
    pass "devcontainer-feature.json is valid JSON"
else
    fail "devcontainer-feature.json is invalid JSON"
fi

# Check required fields
feature_json="$FEATURE_DIR/devcontainer-feature.json"

check_json_field() {
    local field="$1"
    if python3 -c "import json; d=json.load(open('$feature_json')); assert d.get('$field'), 'missing'" 2>/dev/null; then
        pass "Has field: $field"
    else
        fail "Missing field: $field"
    fi
}

check_json_field "id"
check_json_field "version"
check_json_field "name"
check_json_field "options"
check_json_field "postCreateCommand"
check_json_field "postStartCommand"

# Check option defaults
if python3 -c "
import json
d = json.load(open('$feature_json'))
opts = d.get('options', {})
assert opts.get('enableCredentials', {}).get('default') == False, 'enableCredentials should default to false'
" 2>/dev/null; then
    pass "enableCredentials defaults to false (SECURITY)"
else
    fail "enableCredentials should default to false"
fi

# ══════════════════════════════════════════════════════════════════════
# Test: link-spec.json validity
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Link Spec Tests ===\n'

link_spec="$FEATURE_DIR/link-spec.json"

if python3 -c "import json; json.load(open('$link_spec'))" 2>/dev/null; then
    pass "link-spec.json is valid JSON"
else
    fail "link-spec.json is invalid JSON"
fi

# Check structure
if python3 -c "
import json
d = json.load(open('$link_spec'))
assert 'links' in d, 'missing links array'
assert isinstance(d['links'], list), 'links should be array'
assert len(d['links']) > 0, 'links should not be empty'
" 2>/dev/null; then
    pass "link-spec.json has links array"
else
    fail "link-spec.json missing links array"
fi

# Check link entries have required fields
if python3 -c "
import json
d = json.load(open('$link_spec'))
for link in d['links']:
    assert 'link' in link, 'link entry missing link field'
    assert 'target' in link, 'link entry missing target field'
" 2>/dev/null; then
    pass "All link entries have link and target fields"
else
    fail "Some link entries missing required fields"
fi

# ══════════════════════════════════════════════════════════════════════
# Test: Script syntax (bash -n)
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Syntax Tests ===\n'

for script in "${executable_scripts[@]}"; do
    if bash -n "$FEATURE_DIR/$script" 2>/dev/null; then
        pass "Valid bash syntax: $script"
    else
        fail "Invalid bash syntax: $script"
    fi
done

# ══════════════════════════════════════════════════════════════════════
# Test: Shellcheck (if available)
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Shellcheck Tests ===\n'

if command -v shellcheck &>/dev/null; then
    for script in "${executable_scripts[@]}"; do
        if shellcheck -x "$FEATURE_DIR/$script" 2>/dev/null; then
            pass "Shellcheck: $script"
        else
            fail "Shellcheck warnings: $script"
        fi
    done
else
    printf 'Skipping shellcheck (not installed)\n'
fi

# ══════════════════════════════════════════════════════════════════════
# Test: Credential files are in skip list
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Security Tests ===\n'

# Check init.sh contains credential skip list
if grep -q 'CREDENTIAL_TARGETS' "$FEATURE_DIR/init.sh"; then
    pass "init.sh has CREDENTIAL_TARGETS list"
else
    fail "init.sh missing CREDENTIAL_TARGETS list"
fi

# Check that gh/hosts.yml is in the skip list
if grep -q 'hosts.yml' "$FEATURE_DIR/init.sh"; then
    pass "GitHub token file in credential skip list"
else
    fail "GitHub token file NOT in credential skip list"
fi

# Check that credentials.json is in the skip list
if grep -q 'credentials.json' "$FEATURE_DIR/init.sh"; then
    pass "Claude credentials in credential skip list"
else
    fail "Claude credentials NOT in credential skip list"
fi

# ══════════════════════════════════════════════════════════════════════
# Test: Platform check in install.sh
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Platform Check Tests ===\n'

if grep -q 'apt-get' "$FEATURE_DIR/install.sh" && grep -q 'Debian/Ubuntu' "$FEATURE_DIR/install.sh"; then
    pass "install.sh checks for Debian/Ubuntu"
else
    fail "install.sh missing platform check"
fi

# ══════════════════════════════════════════════════════════════════════
# Test: Sysbox verification requirements
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Sysbox Verification Tests ===\n'

verify_script="$FEATURE_DIR/verify-sysbox.sh"

# Check for sysboxfs mount check (MANDATORY)
if grep -q 'sysboxfs' "$verify_script"; then
    pass "verify-sysbox.sh checks for sysboxfs mount"
else
    fail "verify-sysbox.sh missing sysboxfs check"
fi

# Check for UID mapping check
if grep -q 'uid_map' "$verify_script"; then
    pass "verify-sysbox.sh checks UID mapping"
else
    fail "verify-sysbox.sh missing UID mapping check"
fi

# Check for nested userns check
if grep -q 'unshare.*--user' "$verify_script"; then
    pass "verify-sysbox.sh checks nested userns"
else
    fail "verify-sysbox.sh missing nested userns check"
fi

# Check for hard fail requirement
if grep -q 'sysboxfs_found.*true' "$verify_script"; then
    pass "verify-sysbox.sh requires sysboxfs (mandatory)"
else
    fail "verify-sysbox.sh missing mandatory sysboxfs requirement"
fi

# ══════════════════════════════════════════════════════════════════════
# Test: Path rewriting in init.sh
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Path Rewrite Tests ===\n'

# Check for SPEC_HOME extraction
if grep -q 'SPEC_HOME' "$FEATURE_DIR/init.sh"; then
    pass "init.sh extracts home_dir from link-spec.json"
else
    fail "init.sh missing SPEC_HOME extraction"
fi

# Check for path rewriting
if grep -qE 'link=.*\$SPEC_HOME.*\$USER_HOME' "$FEATURE_DIR/init.sh"; then
    pass "init.sh rewrites paths from SPEC_HOME to USER_HOME"
else
    fail "init.sh missing path rewrite logic"
fi

# ══════════════════════════════════════════════════════════════════════
# Test: remove_first handling
# ══════════════════════════════════════════════════════════════════════
printf '\n=== remove_first Tests ===\n'

if grep -q 'remove_first' "$FEATURE_DIR/init.sh" && grep -q 'rm -rf' "$FEATURE_DIR/init.sh"; then
    pass "init.sh handles remove_first for directories"
else
    fail "init.sh missing remove_first handling"
fi

# ══════════════════════════════════════════════════════════════════════
# Test: SSH port from env var
# ══════════════════════════════════════════════════════════════════════
printf '\n=== SSH Port Tests ===\n'

if grep -q 'CONTAINAI_SSH_PORT' "$FEATURE_DIR/start.sh"; then
    pass "start.sh reads SSH port from CONTAINAI_SSH_PORT env var"
else
    fail "start.sh missing CONTAINAI_SSH_PORT env var support"
fi

# ══════════════════════════════════════════════════════════════════════
# Test: Idempotency checks
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Idempotency Tests ===\n'

# SSH idempotency
if grep -q 'already running' "$FEATURE_DIR/start.sh" && grep -q 'kill -0' "$FEATURE_DIR/start.sh"; then
    pass "start.sh has sshd idempotency check"
else
    fail "start.sh missing sshd idempotency check"
fi

# Docker idempotency
if grep -q 'dockerd already running' "$FEATURE_DIR/start.sh"; then
    pass "start.sh has dockerd idempotency check"
else
    fail "start.sh missing dockerd idempotency check"
fi

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
printf '\n=== Summary ===\n'
printf 'Passed: %d\n' "$passed"
printf 'Failed: %d\n' "$failed"

if [[ $failed -gt 0 ]]; then
    exit 1
fi
exit 0
