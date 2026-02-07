#!/usr/bin/env bash
# ==============================================================================
# Integration tests for agent launch wrappers
# ==============================================================================
# Verifies:
# 1. Wrapper file exists and is sourced via BASH_ENV
# 2. Wrappers work in non-interactive shell (via docker exec bash -c)
# 3. Wrappers work when .bashrc is sourced
# 4. Wrappers prepend default args to commands
# 5. Alias functions (e.g., kimi-cli) work correctly
# 6. Optional agent wrappers are guarded with command -v
#
# Limitation: These tests use `docker exec` which inherits Docker ENV variables.
# Real SSH sessions may not inherit Docker ENV unless PATH/BASH_ENV are set in
# shell init files. The Dockerfile sets BASH_ENV in the image, and these tests
# verify that bash -c respects it.
#
# For true SSH-based E2E tests with systemd/containai-init runtime:
# - See test-startup-hooks.sh (Tests 6-7) which require Sysbox
# - These tests verify user manifest processing and SSH wrapper behavior
#
# Prerequisites:
#   - Docker daemon running
#   - Test image built: dotnet msbuild src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source test helpers
source "$SCRIPT_DIR/sync-test-helpers.sh"

# ==============================================================================
# Test configuration
# ==============================================================================
WRAPPER_TEST_RUN_ID="wrapper-$(date +%s)-$$"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    printf '[PASS] %s\n' "$*"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    printf '[FAIL] %s\n' "$*" >&2
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_info() {
    printf '[INFO] %s\n' "$*"
}

# ==============================================================================
# Early guards
# ==============================================================================
docker_status=0
check_docker_available || docker_status=$?
if [[ "$docker_status" == "2" ]]; then
    # Docker binary not found - skip
    test_info "Docker binary not found - skipping launch wrapper tests"
    exit 0
elif [[ "$docker_status" != "0" ]]; then
    # Docker daemon not running - fail
    test_fail "Docker daemon not running"
    exit 1
fi

if ! check_test_image; then
    test_info "Test image not available - skipping launch wrapper tests"
    test_info "Run 'dotnet msbuild src/cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest' first to build the test image"
    exit 0
fi

# ==============================================================================
# Setup and cleanup
# ==============================================================================
WRAPPER_TEST_CONTAINER=""
WRAPPER_TEST_VOLUME=""

cleanup_wrapper_test() {
    if [[ -n "$WRAPPER_TEST_CONTAINER" ]]; then
        "${DOCKER_CMD[@]}" stop -- "$WRAPPER_TEST_CONTAINER" 2>/dev/null || true
        "${DOCKER_CMD[@]}" rm -- "$WRAPPER_TEST_CONTAINER" 2>/dev/null || true
    fi
    if [[ -n "$WRAPPER_TEST_VOLUME" ]]; then
        "${DOCKER_CMD[@]}" volume rm -- "$WRAPPER_TEST_VOLUME" 2>/dev/null || true
    fi
}
trap cleanup_wrapper_test EXIT

# Helper: wait for container file to exist
wait_for_file() {
    local container="$1"
    local path="$2"
    local timeout="${3:-30}"
    local count=0

    while [[ $count -lt $timeout ]]; do
        if "${DOCKER_CMD[@]}" exec "$container" test -f "$path" 2>/dev/null; then
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    return 1
}

# Create test volume and container
WRAPPER_TEST_VOLUME="test-wrapper-data-${WRAPPER_TEST_RUN_ID}"
"${DOCKER_CMD[@]}" volume create --label "containai.test=1" "$WRAPPER_TEST_VOLUME" >/dev/null

WRAPPER_TEST_CONTAINER="test-wrapper-${WRAPPER_TEST_RUN_ID}"
"${DOCKER_CMD[@]}" create \
    --label "containai.test=1" \
    --name "$WRAPPER_TEST_CONTAINER" \
    --volume "$WRAPPER_TEST_VOLUME:/mnt/agent-data" \
    --entrypoint /bin/bash \
    "$SYNC_TEST_IMAGE_NAME" -lc "tail -f /dev/null" >/dev/null

"${DOCKER_CMD[@]}" start "$WRAPPER_TEST_CONTAINER" >/dev/null

# Wait for container to be ready by polling for expected file
if ! wait_for_file "$WRAPPER_TEST_CONTAINER" "/home/agent/.bash_env" 10; then
    test_fail "Container did not become ready (timeout waiting for .bash_env)"
    exit 1
fi

test_info "Test container: $WRAPPER_TEST_CONTAINER"
test_info "Test volume: $WRAPPER_TEST_VOLUME"

# ==============================================================================
# Helper: Execute command in container via bash -c (BASH_ENV sourced)
# ==============================================================================
# This simulates non-interactive SSH: ssh container 'command'
# BASH_ENV is sourced by bash before running the command
exec_bash_cmd() {
    local cmd="$1"
    "${DOCKER_CMD[@]}" exec -u agent -e HOME=/home/agent "$WRAPPER_TEST_CONTAINER" \
        bash -c "$cmd"
}

# ==============================================================================
# Helper: Execute command with explicit .bashrc sourcing
# ==============================================================================
# This simulates interactive shell behavior (sources .bashrc)
# Note: We don't use -t flag to avoid TTY issues in CI
exec_with_bashrc() {
    local cmd="$1"
    "${DOCKER_CMD[@]}" exec -u agent -e HOME=/home/agent "$WRAPPER_TEST_CONTAINER" \
        bash -c "source ~/.bashrc 2>/dev/null; $cmd"
}

# ==============================================================================
# Test 1: Wrapper file exists
# ==============================================================================
printf '\n=== Test: Wrapper file exists ===\n'
if "${DOCKER_CMD[@]}" exec "$WRAPPER_TEST_CONTAINER" test -f /home/agent/.bash_env.d/containai-agents.sh; then
    test_pass "Wrapper file exists at /home/agent/.bash_env.d/containai-agents.sh"
else
    test_fail "Wrapper file not found at /home/agent/.bash_env.d/containai-agents.sh"
fi

# ==============================================================================
# Test 2: .bash_env sources .bash_env.d scripts
# ==============================================================================
printf '\n=== Test: .bash_env sources .bash_env.d scripts ===\n'
bash_env_content=$("${DOCKER_CMD[@]}" exec "$WRAPPER_TEST_CONTAINER" cat /home/agent/.bash_env 2>&1 || true)
# Match the actual sourcing loop, not just any mention of .bash_env.d
# The file should contain: for f in "$HOME"/.bash_env.d/*.sh; do
if [[ "$bash_env_content" == *'for f in'*'.bash_env.d/'*'.sh'* ]] || \
   [[ "$bash_env_content" == *'source'*'.bash_env.d/'* ]] || \
   [[ "$bash_env_content" == *'. "'*'.bash_env.d/'* ]]; then
    test_pass ".bash_env sources .bash_env.d scripts"
else
    test_fail ".bash_env does not source .bash_env.d scripts"
fi

# ==============================================================================
# Test 3: .bashrc sources .bash_env
# ==============================================================================
printf '\n=== Test: .bashrc sources .bash_env ===\n'
bashrc_content=$("${DOCKER_CMD[@]}" exec "$WRAPPER_TEST_CONTAINER" cat /home/agent/.bashrc 2>&1 || true)
# Match actual sourcing line, not just any mention of .bash_env
# The file should contain: [ -f ~/.bash_env ] && . ~/.bash_env
if [[ "$bashrc_content" == *'. ~/.bash_env'* ]] || \
   [[ "$bashrc_content" == *'source ~/.bash_env'* ]] || \
   [[ "$bashrc_content" == *'. "$HOME/.bash_env"'* ]]; then
    test_pass ".bashrc sources .bash_env"
else
    test_fail ".bashrc does not source .bash_env"
fi

# ==============================================================================
# Test 4: BASH_ENV is set in container environment (as agent user)
# ==============================================================================
printf '\n=== Test: BASH_ENV environment variable ===\n'
# Run as agent user to ensure we see the agent's environment
bash_env_var=$("${DOCKER_CMD[@]}" exec -u agent "$WRAPPER_TEST_CONTAINER" printenv BASH_ENV 2>&1 || true)
if [[ "$bash_env_var" == "/etc/containai/bash_env" ]]; then
    test_pass "BASH_ENV is set to /etc/containai/bash_env"
else
    test_fail "BASH_ENV not correctly set, got: '$bash_env_var'"
fi

# ==============================================================================
# Test 5: Claude wrapper is a function (via BASH_ENV)
# ==============================================================================
printf '\n=== Test: Claude wrapper is a function (via BASH_ENV) ===\n'
type_output=$(exec_bash_cmd 'type claude 2>&1' || true)
if [[ "$type_output" == *"function"* ]]; then
    test_pass "Claude is a function via BASH_ENV sourcing"
else
    test_fail "Claude is not a function via BASH_ENV, got: $type_output"
fi

# ==============================================================================
# Test 6: Claude wrapper is a function (via .bashrc)
# ==============================================================================
printf '\n=== Test: Claude wrapper is a function (via .bashrc) ===\n'
type_output=$(exec_with_bashrc 'type claude 2>&1' || true)
if [[ "$type_output" == *"function"* ]]; then
    test_pass "Claude is a function via .bashrc sourcing"
else
    test_fail "Claude is not a function via .bashrc, got: $type_output"
fi

# ==============================================================================
# Test 7: Claude wrapper includes --dangerously-skip-permissions
# ==============================================================================
printf '\n=== Test: Claude wrapper includes default args ===\n'
wrapper_def=$(exec_bash_cmd 'declare -f claude 2>&1' || true)
if [[ "$wrapper_def" == *'--dangerously-skip-permissions'* ]]; then
    test_pass "Claude wrapper includes --dangerously-skip-permissions"
else
    test_fail "Claude wrapper missing --dangerously-skip-permissions, got: $wrapper_def"
fi

# ==============================================================================
# Test 8: Codex wrapper is a function
# ==============================================================================
printf '\n=== Test: Codex wrapper is a function ===\n'
type_output=$(exec_bash_cmd 'type codex 2>&1' || true)
if [[ "$type_output" == *"function"* ]]; then
    test_pass "Codex is a function"
else
    test_fail "Codex is not a function, got: $type_output"
fi

# ==============================================================================
# Test 9: Codex wrapper includes default args
# ==============================================================================
printf '\n=== Test: Codex wrapper includes default args ===\n'
wrapper_def=$(exec_bash_cmd 'declare -f codex 2>&1' || true)
if [[ "$wrapper_def" == *'--dangerously-bypass-approvals-and-sandbox'* ]]; then
    test_pass "Codex wrapper includes --dangerously-bypass-approvals-and-sandbox"
else
    test_fail "Codex wrapper missing --dangerously-bypass-approvals-and-sandbox, got: $wrapper_def"
fi

# ==============================================================================
# Test 10: Optional agent wrappers have command -v guard (kimi)
# ==============================================================================
printf '\n=== Test: Optional agent wrappers have command -v guard ===\n'
wrapper_file=$("${DOCKER_CMD[@]}" exec "$WRAPPER_TEST_CONTAINER" cat /home/agent/.bash_env.d/containai-agents.sh 2>&1 || true)
# Kimi is optional, should have command -v guard
if [[ "$wrapper_file" == *'if command -v kimi'* ]]; then
    test_pass "Kimi wrapper has command -v guard (optional agent)"
else
    test_fail "Kimi wrapper missing command -v guard"
fi

# ==============================================================================
# Test 11: Required agent wrappers do NOT have command -v guard (claude)
# ==============================================================================
printf '\n=== Test: Required agent wrappers do NOT have command -v guard ===\n'
# Claude is NOT optional, should NOT be wrapped in command -v guard
# Look for the claude function section - it should be direct, not guarded
# Extract lines around claude() definition
claude_section=$(printf '%s' "$wrapper_file" | grep -A5 '^claude()' || true)
if [[ -n "$claude_section" && "$claude_section" != *'if command -v'* ]]; then
    test_pass "Claude wrapper does NOT have command -v guard (required agent)"
else
    test_fail "Claude wrapper incorrectly has command -v guard or is missing"
fi

# ==============================================================================
# Test 12: Kimi aliases work (kimi-cli)
# ==============================================================================
printf '\n=== Test: Kimi aliases work (kimi-cli) ===\n'
# Check if kimi-cli function is defined in the wrapper file
if [[ "$wrapper_file" == *'kimi-cli()'* ]]; then
    test_pass "kimi-cli alias function is defined"
else
    test_fail "kimi-cli alias function is not defined"
fi

# ==============================================================================
# Test 13: Kimi alias includes --yolo flag
# ==============================================================================
printf '\n=== Test: Kimi alias includes --yolo flag ===\n'
# Extract kimi-cli function definition (get lines after kimi-cli())
kimi_cli_def=$(printf '%s' "$wrapper_file" | grep -A5 'kimi-cli()' || true)
if [[ "$kimi_cli_def" == *'--yolo'* ]]; then
    test_pass "kimi-cli alias includes --yolo flag"
else
    test_fail "kimi-cli alias missing --yolo flag"
fi

# ==============================================================================
# Test 14: Wrapper function calls binary with 'command' builtin
# ==============================================================================
printf '\n=== Test: Wrapper functions use command builtin ===\n'
# Wrappers should use `command <binary>` to avoid recursion
claude_def=$(printf '%s' "$wrapper_file" | grep -A5 'claude()' | head -5 || true)
if [[ "$claude_def" == *'command claude'* ]]; then
    test_pass "Wrapper uses 'command' builtin to call binary"
else
    test_fail "Wrapper does not use 'command' builtin, got: $claude_def"
fi

# ==============================================================================
# Test 15: Wrapper file is sourced via BASH_ENV in non-interactive mode
# ==============================================================================
printf '\n=== Test: BASH_ENV sources wrapper in non-interactive mode ===\n'
# Check if wrapper function is available via BASH_ENV sourcing
marker_check=$(exec_bash_cmd 'if type claude >/dev/null 2>&1; then echo "wrapper_loaded"; fi' || true)
if [[ "$marker_check" == *"wrapper_loaded"* ]]; then
    test_pass "Wrapper is loaded via BASH_ENV"
else
    test_fail "Wrapper not loaded via BASH_ENV"
fi

# ==============================================================================
# Summary
# ==============================================================================
printf '\n==========================================\n'
printf 'Tests run:   %s\n' "$TESTS_RUN"
printf 'Passed:      %s\n' "$TESTS_PASSED"
printf 'Failed:      %s\n' "$TESTS_FAILED"
printf '==========================================\n'

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
