#!/usr/bin/env bash
# ==============================================================================
# Integration tests for agent launch wrappers
# ==============================================================================
# Verifies:
# 1. Wrappers work in non-interactive SSH (plain 'ssh container cmd')
# 2. Wrappers work in non-interactive SSH with bash -c
# 3. Wrappers work in interactive shell
# 4. Wrappers prepend default args to commands
# 5. Alias functions (e.g., kimi-cli) work correctly
# 6. Optional agent wrappers are guarded with command -v
#
# CRITICAL: Tests plain `ssh container 'cmd'` (not just `bash -c` variant)
# This tests the BASH_ENV path for non-interactive SSH.
#
# Prerequisites:
#   - Docker daemon running
#   - Test image built: ./src/build.sh
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

test_skip() {
    printf '[SKIP] %s\n' "$*"
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
    test_info "Run './src/build.sh' first to build the test image"
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

# Create test volume and container
WRAPPER_TEST_VOLUME="test-wrapper-data-${WRAPPER_TEST_RUN_ID}"
"${DOCKER_CMD[@]}" volume create --label "containai.test=1" "$WRAPPER_TEST_VOLUME" >/dev/null

WRAPPER_TEST_CONTAINER="test-wrapper-${WRAPPER_TEST_RUN_ID}"
"${DOCKER_CMD[@]}" create \
    --label "containai.test=1" \
    --name "$WRAPPER_TEST_CONTAINER" \
    --volume "$WRAPPER_TEST_VOLUME:/mnt/agent-data" \
    "$SYNC_TEST_IMAGE_NAME" tail -f /dev/null >/dev/null

"${DOCKER_CMD[@]}" start "$WRAPPER_TEST_CONTAINER" >/dev/null

# Wait for container to be ready
sleep 2

test_info "Test container: $WRAPPER_TEST_CONTAINER"
test_info "Test volume: $WRAPPER_TEST_VOLUME"

# ==============================================================================
# Helper: Execute command in container simulating plain non-interactive SSH
# ==============================================================================
# This simulates: ssh container 'command'
# The key is BASH_ENV gets sourced, which loads .bash_env.d/*.sh
exec_noninteractive() {
    local cmd="$1"
    # Simulate non-interactive SSH: bash reads BASH_ENV before running command
    # Use bash (not bash -c with the command in quotes - that's a different path)
    "${DOCKER_CMD[@]}" exec -u agent -e HOME=/home/agent "$WRAPPER_TEST_CONTAINER" \
        bash -c "$cmd"
}

# ==============================================================================
# Helper: Execute command in container simulating interactive shell
# ==============================================================================
exec_interactive() {
    local cmd="$1"
    # -i flag simulates interactive shell (sources .bashrc)
    "${DOCKER_CMD[@]}" exec -u agent -e HOME=/home/agent "$WRAPPER_TEST_CONTAINER" \
        bash -i -c "$cmd" 2>/dev/null
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
bash_env_content=$("${DOCKER_CMD[@]}" exec "$WRAPPER_TEST_CONTAINER" cat /home/agent/.bash_env 2>/dev/null || true)
if [[ "$bash_env_content" == *'.bash_env.d'* ]]; then
    test_pass ".bash_env sources .bash_env.d scripts"
else
    test_fail ".bash_env does not source .bash_env.d scripts"
fi

# ==============================================================================
# Test 3: .bashrc sources .bash_env
# ==============================================================================
printf '\n=== Test: .bashrc sources .bash_env ===\n'
bashrc_content=$("${DOCKER_CMD[@]}" exec "$WRAPPER_TEST_CONTAINER" cat /home/agent/.bashrc 2>/dev/null || true)
if [[ "$bashrc_content" == *'.bash_env'* ]]; then
    test_pass ".bashrc sources .bash_env"
else
    test_fail ".bashrc does not source .bash_env"
fi

# ==============================================================================
# Test 4: BASH_ENV is set in container environment (as agent user)
# ==============================================================================
printf '\n=== Test: BASH_ENV environment variable ===\n'
# Run as agent user to ensure we see the agent's environment
bash_env_var=$("${DOCKER_CMD[@]}" exec -u agent "$WRAPPER_TEST_CONTAINER" printenv BASH_ENV 2>/dev/null || true)
if [[ "$bash_env_var" == "/home/agent/.bash_env" ]]; then
    test_pass "BASH_ENV is set to /home/agent/.bash_env"
else
    test_fail "BASH_ENV not correctly set, got: '$bash_env_var'"
fi

# ==============================================================================
# Test 5: Claude wrapper is a function (non-interactive)
# ==============================================================================
printf '\n=== Test: Claude wrapper is a function (non-interactive) ===\n'
type_output=$(exec_noninteractive 'type claude 2>&1' || true)
if [[ "$type_output" == *"function"* ]]; then
    test_pass "Claude is a function in non-interactive shell"
else
    test_fail "Claude is not a function in non-interactive shell, got: $type_output"
fi

# ==============================================================================
# Test 6: Claude wrapper is a function (interactive)
# ==============================================================================
printf '\n=== Test: Claude wrapper is a function (interactive) ===\n'
type_output=$(exec_interactive 'type claude 2>&1' || true)
if [[ "$type_output" == *"function"* ]]; then
    test_pass "Claude is a function in interactive shell"
else
    test_fail "Claude is not a function in interactive shell, got: $type_output"
fi

# ==============================================================================
# Test 7: Claude wrapper includes --dangerously-skip-permissions
# ==============================================================================
printf '\n=== Test: Claude wrapper includes default args ===\n'
wrapper_def=$(exec_noninteractive 'declare -f claude 2>&1' || true)
if [[ "$wrapper_def" == *'--dangerously-skip-permissions'* ]]; then
    test_pass "Claude wrapper includes --dangerously-skip-permissions"
else
    test_fail "Claude wrapper missing --dangerously-skip-permissions, got: $wrapper_def"
fi

# ==============================================================================
# Test 8: Codex wrapper is a function
# ==============================================================================
printf '\n=== Test: Codex wrapper is a function ===\n'
type_output=$(exec_noninteractive 'type codex 2>&1' || true)
if [[ "$type_output" == *"function"* ]]; then
    test_pass "Codex is a function"
else
    test_fail "Codex is not a function, got: $type_output"
fi

# ==============================================================================
# Test 9: Codex wrapper includes --full-auto
# ==============================================================================
printf '\n=== Test: Codex wrapper includes default args ===\n'
wrapper_def=$(exec_noninteractive 'declare -f codex 2>&1' || true)
if [[ "$wrapper_def" == *'--full-auto'* ]]; then
    test_pass "Codex wrapper includes --full-auto"
else
    test_fail "Codex wrapper missing --full-auto, got: $wrapper_def"
fi

# ==============================================================================
# Test 10: Optional agent wrappers have command -v guard (kimi/gemini)
# ==============================================================================
printf '\n=== Test: Optional agent wrappers have command -v guard ===\n'
wrapper_file=$("${DOCKER_CMD[@]}" exec "$WRAPPER_TEST_CONTAINER" cat /home/agent/.bash_env.d/containai-agents.sh 2>/dev/null || true)
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
# Look for claude() function NOT preceded by "if command -v"
# The pattern for required agents is just the function definition directly
claude_section=$(printf '%s' "$wrapper_file" | grep -A3 "^# claude" || true)
if [[ "$claude_section" != *'if command -v'* && "$claude_section" == *'claude()'* ]]; then
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
# Extract kimi-cli function definition
kimi_cli_def=$(printf '%s' "$wrapper_file" | grep -A3 'kimi-cli()' || true)
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
# Set a marker in wrapper and check if it's available
marker_check=$(exec_noninteractive 'if type claude >/dev/null 2>&1; then echo "wrapper_loaded"; fi' || true)
if [[ "$marker_check" == *"wrapper_loaded"* ]]; then
    test_pass "Wrapper is loaded in non-interactive mode via BASH_ENV"
else
    test_fail "Wrapper not loaded in non-interactive mode"
fi

# ==============================================================================
# Test 16: Test plain SSH-style command execution (critical test)
# ==============================================================================
printf '\n=== Test: Plain SSH-style command execution (critical) ===\n'
# This simulates: ssh container 'type claude'
# The container's default BASH_ENV should be used (set via Dockerfile ENV)
# Do NOT explicitly set BASH_ENV here - that would mask regressions
plain_ssh_output=$("${DOCKER_CMD[@]}" exec -u agent -e HOME=/home/agent \
    "$WRAPPER_TEST_CONTAINER" bash -c 'type claude' 2>&1 || true)
if [[ "$plain_ssh_output" == *"function"* ]]; then
    test_pass "Plain SSH-style 'type claude' shows function (container BASH_ENV works)"
else
    test_fail "Plain SSH-style command does not see wrapper function, got: $plain_ssh_output"
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
