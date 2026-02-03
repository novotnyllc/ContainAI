#!/usr/bin/env bash
# Unit tests for Docker context sync functions
set -euo pipefail

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source required libraries
# shellcheck source=../../src/lib/core.sh
source "$REPO_ROOT/src/lib/core.sh"
# shellcheck source=../../src/lib/platform.sh
source "$REPO_ROOT/src/lib/platform.sh"
# shellcheck source=../../src/lib/docker-context-sync.sh
source "$REPO_ROOT/src/lib/docker-context-sync.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temp directory for test isolation
TEST_TMPDIR=""
ORIG_HOME=""

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
    ORIG_HOME="$HOME"
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME"
}

teardown() {
    export HOME="$ORIG_HOME"
    if [[ -n "$TEST_TMPDIR" ]] && [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Create a mock Docker context in a directory
# Arguments: $1 = contexts dir, $2 = context name
create_mock_context() {
    local contexts_dir="$1"
    local context_name="$2"
    local hash
    hash=$(printf '%s' "$context_name" | sha256sum | cut -c1-64)

    mkdir -p "${contexts_dir}/meta/${hash}"
    cat > "${contexts_dir}/meta/${hash}/meta.json" <<EOF
{
    "Name": "${context_name}",
    "Metadata": {"Description": "Test context"},
    "Endpoints": {"docker": {"Host": "unix:///var/run/docker.sock"}}
}
EOF

    # Optionally create TLS dir
    mkdir -p "${contexts_dir}/tls/${hash}"
    touch "${contexts_dir}/tls/${hash}/ca.pem"
}

# ==============================================================================
# Test: _cai_is_containai_docker_context identifies containai-docker
# ==============================================================================

test_start "_cai_is_containai_docker_context returns 0 for containai-docker"
setup
contexts_dir="$TEST_TMPDIR/contexts"
create_mock_context "$contexts_dir" "containai-docker"
hash=$(printf '%s' "containai-docker" | sha256sum | cut -c1-64)
if _cai_is_containai_docker_context "${contexts_dir}/meta/${hash}"; then
    test_pass
else
    test_fail "should have identified containai-docker context"
fi
teardown

# ==============================================================================
# Test: _cai_is_containai_docker_context returns 1 for other contexts
# ==============================================================================

test_start "_cai_is_containai_docker_context returns 1 for other contexts"
setup
contexts_dir="$TEST_TMPDIR/contexts"
create_mock_context "$contexts_dir" "my-other-context"
hash=$(printf '%s' "my-other-context" | sha256sum | cut -c1-64)
if _cai_is_containai_docker_context "${contexts_dir}/meta/${hash}"; then
    test_fail "should not have identified my-other-context as containai-docker"
else
    test_pass
fi
teardown

# ==============================================================================
# Test: _cai_get_context_name extracts name from meta.json
# ==============================================================================

test_start "_cai_get_context_name extracts context name"
setup
contexts_dir="$TEST_TMPDIR/contexts"
create_mock_context "$contexts_dir" "test-context-name"
hash=$(printf '%s' "test-context-name" | sha256sum | cut -c1-64)
result=$(_cai_get_context_name "${contexts_dir}/meta/${hash}")
if [[ "$result" == "test-context-name" ]]; then
    test_pass
else
    test_fail "expected 'test-context-name', got '$result'"
fi
teardown

# ==============================================================================
# Test: _cai_sync_docker_contexts_once syncs contexts (excluding containai-docker)
# ==============================================================================

test_start "_cai_sync_docker_contexts_once syncs regular contexts"
setup
source_dir="$TEST_TMPDIR/source-contexts"
target_dir="$TEST_TMPDIR/target-contexts"

# Create source contexts
create_mock_context "$source_dir" "context-one"
create_mock_context "$source_dir" "context-two"

# Run sync
_cai_sync_docker_contexts_once "$source_dir" "$target_dir" "host-to-cai" >/dev/null 2>&1

# Verify contexts were synced
hash1=$(printf '%s' "context-one" | sha256sum | cut -c1-64)
hash2=$(printf '%s' "context-two" | sha256sum | cut -c1-64)

if [[ -f "${target_dir}/meta/${hash1}/meta.json" ]] && \
   [[ -f "${target_dir}/meta/${hash2}/meta.json" ]]; then
    test_pass
else
    test_fail "contexts were not synced"
fi
teardown

# ==============================================================================
# Test: _cai_sync_docker_contexts_once excludes containai-docker
# ==============================================================================

test_start "_cai_sync_docker_contexts_once excludes containai-docker"
setup
source_dir="$TEST_TMPDIR/source-contexts"
target_dir="$TEST_TMPDIR/target-contexts"

# Create source contexts including containai-docker
create_mock_context "$source_dir" "regular-context"
create_mock_context "$source_dir" "containai-docker"

# Run sync
_cai_sync_docker_contexts_once "$source_dir" "$target_dir" "host-to-cai" >/dev/null 2>&1

# Verify containai-docker was NOT synced
regular_hash=$(printf '%s' "regular-context" | sha256sum | cut -c1-64)
cai_hash=$(printf '%s' "containai-docker" | sha256sum | cut -c1-64)

if [[ -f "${target_dir}/meta/${regular_hash}/meta.json" ]] && \
   [[ ! -f "${target_dir}/meta/${cai_hash}/meta.json" ]]; then
    test_pass
else
    test_fail "containai-docker should not have been synced"
fi
teardown

# ==============================================================================
# Test: _cai_sync_docker_contexts_once syncs TLS certs
# ==============================================================================

test_start "_cai_sync_docker_contexts_once syncs TLS certificates"
setup
source_dir="$TEST_TMPDIR/source-contexts"
target_dir="$TEST_TMPDIR/target-contexts"

# Create source context with TLS
create_mock_context "$source_dir" "tls-context"
hash=$(printf '%s' "tls-context" | sha256sum | cut -c1-64)

# Run sync
_cai_sync_docker_contexts_once "$source_dir" "$target_dir" "host-to-cai" >/dev/null 2>&1

# Verify TLS was synced
if [[ -f "${target_dir}/tls/${hash}/ca.pem" ]]; then
    test_pass
else
    test_fail "TLS certificates were not synced"
fi
teardown

# ==============================================================================
# Test: _cai_sync_docker_contexts_once handles deletions
# ==============================================================================

test_start "_cai_sync_docker_contexts_once removes deleted contexts from target"
setup
source_dir="$TEST_TMPDIR/source-contexts"
target_dir="$TEST_TMPDIR/target-contexts"

# Create contexts in both source and target
create_mock_context "$source_dir" "keep-me"
create_mock_context "$target_dir" "keep-me"
create_mock_context "$target_dir" "delete-me"

# Run sync (source only has keep-me)
_cai_sync_docker_contexts_once "$source_dir" "$target_dir" "host-to-cai" >/dev/null 2>&1

# Verify delete-me was removed
keep_hash=$(printf '%s' "keep-me" | sha256sum | cut -c1-64)
delete_hash=$(printf '%s' "delete-me" | sha256sum | cut -c1-64)

if [[ -f "${target_dir}/meta/${keep_hash}/meta.json" ]] && \
   [[ ! -d "${target_dir}/meta/${delete_hash}" ]]; then
    test_pass
else
    test_fail "deleted context should have been removed"
fi
teardown

# ==============================================================================
# Test: _cai_create_containai_docker_context creates valid context
# ==============================================================================

test_start "_cai_create_containai_docker_context creates context with correct socket"
# NOTE: Don't call setup() here because _CAI_DOCKER_CAI_CONTEXTS_DIR is set
# at library source time with the original HOME value
TEST_TMPDIR="$(mktemp -d)"

# The function uses the readonly _CAI_DOCKER_CAI_CONTEXTS_DIR which was set
# when the library was sourced (with original HOME). We test it there.
cai_contexts_dir="$_CAI_DOCKER_CAI_CONTEXTS_DIR"

# Ensure parent dirs exist (may need sudo in real scenario, skip if no permission)
if mkdir -p "${cai_contexts_dir}/meta" "${cai_contexts_dir}/tls" 2>/dev/null; then
    # Call function
    _cai_create_containai_docker_context >/dev/null 2>&1 || true

    # Check if context was created with unix socket
    hash=$(printf '%s' "containai-docker" | sha256sum | cut -c1-64)
    if [[ -f "${cai_contexts_dir}/meta/${hash}/meta.json" ]]; then
        if grep -q 'unix:///var/run/docker.sock' "${cai_contexts_dir}/meta/${hash}/meta.json"; then
            test_pass
            # Clean up the created context
            rm -rf "${cai_contexts_dir}/meta/${hash}" 2>/dev/null || true
        else
            test_fail "context should use unix socket"
        fi
    else
        test_fail "context meta.json was not created"
    fi
else
    printf '  SKIP (cannot create test directories)\n'
    TESTS_RUN=$((TESTS_RUN - 1))
fi
rm -rf "$TEST_TMPDIR" 2>/dev/null || true

# ==============================================================================
# Test: _cai_docker_context_sync_available detects tools
# ==============================================================================

test_start "_cai_docker_context_sync_available detects inotifywait or fswatch"
setup
if _cai_docker_context_sync_available; then
    if [[ "$_CAI_CONTEXT_WATCHER" == "inotifywait" ]] || \
       [[ "$_CAI_CONTEXT_WATCHER" == "fswatch" ]]; then
        test_pass
    else
        test_fail "unexpected watcher: $_CAI_CONTEXT_WATCHER"
    fi
else
    # This is OK - tools may not be installed
    printf '  SKIP (no watcher tools installed)\n'
    TESTS_RUN=$((TESTS_RUN - 1))  # Don't count as run
fi
teardown

# ==============================================================================
# Test: Sync handles non-existent source gracefully
# ==============================================================================

test_start "_cai_sync_docker_contexts_once handles non-existent source"
setup
source_dir="$TEST_TMPDIR/nonexistent"
target_dir="$TEST_TMPDIR/target-contexts"

# Run sync (source doesn't exist)
if _cai_sync_docker_contexts_once "$source_dir" "$target_dir" "host-to-cai" >/dev/null 2>&1; then
    test_pass
else
    test_fail "should handle non-existent source gracefully"
fi
teardown

# ==============================================================================
# Test: Invalid direction is rejected
# ==============================================================================

test_start "_cai_sync_docker_contexts_once rejects invalid direction"
setup
source_dir="$TEST_TMPDIR/source"
target_dir="$TEST_TMPDIR/target"
mkdir -p "$source_dir" "$target_dir"

if _cai_sync_docker_contexts_once "$source_dir" "$target_dir" "invalid-direction" 2>/dev/null; then
    test_fail "should have rejected invalid direction"
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
