#!/usr/bin/env bash
# ==============================================================================
# Integration tests for ACP Proxy
# ==============================================================================
# Tests the ACP terminating proxy with a mock ACP server.
#
# Verifies:
# 1. NDJSON framing (newline-delimited, not Content-Length)
# 2. Stdout purity (no diagnostic output leaks, even with verbose mode)
# 3. Initialize response
# 4. Single session lifecycle (session/new -> session/prompt -> session/update)
# 5. Multiple simultaneous sessions
# 6. Concurrent output serialization (no byte interleaving with prompts)
# 7. Session ID namespacing
# 8. Session routing by proxySessionId (prompts routed to correct session)
# 9. Workspace resolution (subdirectory -> git root)
# 10. MCP path translation (host paths -> container paths)
# 11. Session cleanup on session/end (create, end, verify prompt fails)
# 12. Stdin EOF graceful shutdown
#
# Usage: ./tests/integration/test-acp-proxy.sh
#
# Environment:
#   Automatically sets CAI_ACP_TEST_MODE=1 and CAI_ACP_DIRECT_SPAWN=1
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SRC_DIR="$REPO_ROOT/src"

# ==============================================================================
# Test configuration
# ==============================================================================

# Test mode - bypass containers, spawn mock directly
export CAI_ACP_TEST_MODE=1
export CAI_ACP_DIRECT_SPAWN=1

# Add mock server to PATH
export PATH="$SCRIPT_DIR:$PATH"

# Proxy command resolution
PROXY_CAI_BIN="$SRC_DIR/bin/cai"
PROXY_LEGACY_BIN="$SRC_DIR/bin/acp-proxy"
PROXY_CMD=()

if [[ -x "$PROXY_CAI_BIN" ]]; then
    PROXY_CMD=("$PROXY_CAI_BIN" "acp" "proxy")
elif [[ -x "$PROXY_LEGACY_BIN" ]]; then
    PROXY_CMD=("$PROXY_LEGACY_BIN" "proxy")
else
    PROXY_CMD=("dotnet" "run" "--project" "$SRC_DIR/cai" "--" "acp" "proxy")
fi

# Test timeout (seconds)
TEST_TIMEOUT=30

# ==============================================================================
# Test helpers
# ==============================================================================

FAILED=0
TEST_COUNT=0
PASS_COUNT=0
TEMP_FILES=()

pass() { printf '%s\n' "[PASS] $*"; ((PASS_COUNT++)) || true; }
fail() {
    printf '%s\n' "[FAIL] $*" >&2
    FAILED=1
}
info() { printf '%s\n' "[INFO] $*"; }
section() {
    printf '\n'
    printf '%s\n' "=== $* ==="
    ((TEST_COUNT++)) || true
}

# Track all PIDs started by this test
TEST_PIDS=()

cleanup() {
    # Stop interactive proxy if running
    if [[ -n "${PROXY_PID:-}" ]] && kill -0 "$PROXY_PID" 2>/dev/null; then
        kill "$PROXY_PID" 2>/dev/null || true
        wait "$PROXY_PID" 2>/dev/null || true
    fi
    # Kill all tracked PIDs
    local pid
    for pid in "${TEST_PIDS[@]:-}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    # Close file descriptors
    exec 3>&- 2>/dev/null || true
    exec 4<&- 2>/dev/null || true
    # Clean up temp files
    local file
    for file in "${TEMP_FILES[@]:-}"; do
        rm -rf "$file" 2>/dev/null || true
    done
}
trap cleanup EXIT

# Create temp directory
make_temp_dir() {
    local dir
    dir=$(mktemp -d)
    TEMP_FILES+=("$dir")
    printf '%s' "$dir"
}

# Portable timeout wrapper
# Returns: 0 on success, 124 on timeout, other on command failure
run_with_timeout() {
    local secs="$1"
    shift

    # Prefer 'timeout' (Linux, coreutils)
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
        return $?
    fi

    # Try 'gtimeout' (macOS with coreutils installed via brew)
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
        return $?
    fi

    # No timeout mechanism - run without timeout
    "$@"
}

# Run proxy with input and capture all output (single-shot mode)
# Usage: run_proxy "input" [num_lines]
# Sets global PROXY_OUTPUT with the result and PROXY_EXIT_CODE with exit code
PROXY_OUTPUT=""
PROXY_EXIT_CODE=0
run_proxy() {
    local input="$1"
    local num_lines="${2:-}"

    # Use a temporary file to capture output reliably
    local tmpfile
    tmpfile=$(mktemp)
    TEMP_FILES+=("$tmpfile")

    # Send input with a small delay before EOF
    # This gives the proxy time to process and write output
    # The subshell sends input, sleeps briefly, then closes stdin
    PROXY_EXIT_CODE=0
    (printf '%s\n' "$input"; sleep 0.1) | run_with_timeout "$TEST_TIMEOUT" "${PROXY_CMD[@]}" mock-acp-server 2>/dev/null > "$tmpfile" || PROXY_EXIT_CODE=$?

    PROXY_OUTPUT=$(< "$tmpfile")

    if [[ -n "$num_lines" ]]; then
        PROXY_OUTPUT=$(printf '%s' "$PROXY_OUTPUT" | head -"$num_lines")
    fi
}

# Get line N from PROXY_OUTPUT (1-indexed)
get_line() {
    local n="$1"
    printf '%s' "$PROXY_OUTPUT" | sed -n "${n}p"
}

# ==============================================================================
# Interactive proxy helpers (using FIFOs for bidirectional communication)
# ==============================================================================

# Global variables for interactive proxy
PROXY_PID=""
PROXY_IN_FIFO=""
PROXY_OUT_FIFO=""
PROXY_ERR_FILE=""

# Start an interactive proxy session
# This allows sending messages and reading responses dynamically
start_interactive_proxy() {
    PROXY_IN_FIFO=$(mktemp -u)
    PROXY_OUT_FIFO=$(mktemp -u)
    PROXY_ERR_FILE=$(mktemp)
    TEMP_FILES+=("$PROXY_IN_FIFO" "$PROXY_OUT_FIFO" "$PROXY_ERR_FILE")

    mkfifo "$PROXY_IN_FIFO"
    mkfifo "$PROXY_OUT_FIFO"

    # Start proxy with FIFOs, capture stderr for mock server logs
    (
        "${PROXY_CMD[@]}" mock-acp-server < "$PROXY_IN_FIFO" > "$PROXY_OUT_FIFO" 2>"$PROXY_ERR_FILE"
    ) &
    PROXY_PID=$!

    # Open FIFOs for reading/writing (must open write end first to avoid blocking)
    exec 3>"$PROXY_IN_FIFO"
    exec 4<"$PROXY_OUT_FIFO"

    # Give the proxy time to start
    sleep 0.2
}

# Get stderr output from the proxy (includes mock server logs)
get_proxy_stderr() {
    if [[ -f "$PROXY_ERR_FILE" ]]; then
        cat "$PROXY_ERR_FILE"
    fi
}

# Send a message to the interactive proxy and read the response
# Usage: send_and_receive "json message"
# Returns: response line (or empty on timeout)
send_and_receive() {
    local message="$1"
    local timeout_secs="${2:-5}"

    # Send message
    printf '%s\n' "$message" >&3

    # Read response with timeout
    local response=""
    if read -r -t "$timeout_secs" response <&4; then
        printf '%s' "$response"
    fi
}

# Send a message without waiting for response (for notifications)
send_message() {
    local message="$1"
    printf '%s\n' "$message" >&3
}

# Read next response line with timeout
read_response() {
    local timeout_secs="${1:-5}"
    local response=""
    if read -r -t "$timeout_secs" response <&4; then
        printf '%s' "$response"
    fi
}

# Stop the interactive proxy
stop_interactive_proxy() {
    # Close our file descriptors
    exec 3>&- 2>/dev/null || true
    exec 4<&- 2>/dev/null || true

    # Kill the proxy process
    if [[ -n "$PROXY_PID" ]] && kill -0 "$PROXY_PID" 2>/dev/null; then
        kill "$PROXY_PID" 2>/dev/null || true
        wait "$PROXY_PID" 2>/dev/null || true
    fi

    PROXY_PID=""
}

# ==============================================================================
# Prerequisites check
# ==============================================================================

check_prerequisites() {
    section "Prerequisites"

    # Check for jq
    if ! command -v jq >/dev/null 2>&1; then
        fail "jq is required for ACP tests"
        exit 1
    fi
    pass "jq is available"

    # Check for git (needed for workspace resolution test)
    if ! command -v git >/dev/null 2>&1; then
        fail "git is required for ACP tests"
        exit 1
    fi
    pass "git is available"

    # Check mock server is executable
    if [[ ! -x "$SCRIPT_DIR/mock-acp-server" ]]; then
        fail "mock-acp-server not executable"
        exit 1
    fi
    pass "mock-acp-server is executable"

    # Check proxy command source is available
    if [[ ! -x "$PROXY_CAI_BIN" && ! -x "$PROXY_LEGACY_BIN" ]] && ! command -v dotnet >/dev/null 2>&1; then
        fail "No ACP proxy command source found (missing src/bin/cai, src/bin/acp-proxy, and dotnet)"
        info "Build with: dotnet publish src/cai -r linux-x64 -c Release --self-contained"
        exit 1
    fi
    pass "ACP proxy command source found"

    # Verify mock server works
    local mock_output
    mock_output=$(printf '%s\n' '{"jsonrpc":"2.0","id":"test","method":"initialize","params":{"protocolVersion":"2025-01-01"}}' | \
        run_with_timeout 5 "$SCRIPT_DIR/mock-acp-server" 2>/dev/null) || true
    mock_output=$(printf '%s' "$mock_output" | head -1)
    if ! printf '%s' "$mock_output" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        fail "mock-acp-server not working correctly"
        info "Output: $mock_output"
        exit 1
    fi
    pass "mock-acp-server responds correctly"
}

# ==============================================================================
# Test 1: NDJSON Framing
# ==============================================================================

test_ndjson_framing() {
    section "Test 1: NDJSON framing"

    # Send single-line JSON and verify response is also single-line JSON
    run_proxy '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}' 1
    local response="$PROXY_OUTPUT"

    # Must be valid JSON on single line
    if [[ -z "$response" ]]; then
        fail "No response received"
        return
    fi

    if ! printf '%s' "$response" | jq -e . >/dev/null 2>&1; then
        fail "Response is not valid JSON: $response"
        return
    fi

    # Must NOT contain Content-Length header (that would be LSP, not NDJSON)
    if printf '%s' "$response" | grep -qi "Content-Length"; then
        fail "Response contains Content-Length header (should be NDJSON)"
        return
    fi

    # Verify it's an initialize response
    if ! printf '%s' "$response" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        fail "Expected initialize response, got: $response"
        return
    fi

    pass "NDJSON framing works correctly"
}

# ==============================================================================
# Test 2: Stdout Purity (with verbose mode)
# ==============================================================================

test_stdout_purity() {
    section "Test 2: Stdout purity"

    # Test that stdout contains only NDJSON, no diagnostic output
    # Enable verbose mode to try to trigger diagnostic output leaks
    local tmpfile
    tmpfile=$(mktemp)
    TEMP_FILES+=("$tmpfile")

    # Set environment variables for the subshell
    (
        export CONTAINAI_VERBOSE=1
        export CAI_NO_UPDATE_CHECK=1
        (printf '%s\n' '{"jsonrpc":"2.0","id":"purity-test","method":"initialize","params":{"protocolVersion":"2025-01-01"}}'; sleep 0.1) \
            | run_with_timeout "$TEST_TIMEOUT" "${PROXY_CMD[@]}" mock-acp-server 2>/dev/null > "$tmpfile"
    )

    # Count total lines in output
    local line_count
    line_count=$(wc -l < "$tmpfile" | tr -d ' ')

    # Should have exactly 1 line (the JSON response)
    if [[ "$line_count" -ne 1 ]]; then
        fail "Expected exactly 1 line of output, got $line_count lines"
        info "Full output:"
        head -5 < "$tmpfile" | while IFS= read -r line; do info "  $line"; done
        return
    fi

    local response
    response=$(< "$tmpfile")

    # Must receive a response
    if [[ -z "$response" ]]; then
        fail "No response received"
        return
    fi

    # Must be valid JSON (no diagnostic output mixed in)
    if ! printf '%s' "$response" | jq -e . >/dev/null 2>&1; then
        fail "stdout contains non-JSON content: $response"
        return
    fi

    # Must be our initialize response with matching ID
    local response_id
    response_id=$(printf '%s' "$response" | jq -r '.id // empty')
    if [[ "$response_id" != "purity-test" ]]; then
        fail "Response ID mismatch: expected 'purity-test', got '$response_id'"
        return
    fi

    if ! printf '%s' "$response" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        fail "Expected initialize response, got: $response"
        return
    fi

    pass "stdout purity maintained (no diagnostic leaks, even with CONTAINAI_VERBOSE=1)"
}

# ==============================================================================
# Test 3: Initialize Response
# ==============================================================================

test_initialize_response() {
    section "Test 3: Initialize response"

    run_proxy '{"jsonrpc":"2.0","id":"init-1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}' 1
    local response="$PROXY_OUTPUT"

    # Verify response structure
    local id version has_capabilities
    id=$(printf '%s' "$response" | jq -r '.id // empty')
    version=$(printf '%s' "$response" | jq -r '.result.protocolVersion // empty')
    has_capabilities=$(printf '%s' "$response" | jq -e '.result.capabilities' >/dev/null 2>&1 && printf 'true' || printf 'false')

    if [[ "$id" != "init-1" ]]; then
        fail "Response ID mismatch: expected 'init-1', got '$id'"
        return
    fi

    if [[ -z "$version" ]]; then
        fail "Missing protocolVersion in response"
        return
    fi

    if [[ "$has_capabilities" != "true" ]]; then
        fail "Missing capabilities in response"
        return
    fi

    pass "Initialize response is correct (id=$id, version=$version)"
}

# ==============================================================================
# Test 4: Single Session Lifecycle (session/new -> session/prompt -> session/update)
# ==============================================================================

test_single_session() {
    section "Test 4: Single session lifecycle"

    local ws
    ws=$(make_temp_dir)

    start_interactive_proxy

    # Initialize
    local init_response
    init_response=$(send_and_receive '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}')
    if ! printf '%s' "$init_response" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        stop_interactive_proxy
        fail "Initialize failed: $init_response"
        return
    fi

    # Create session
    local session_response session_id
    session_response=$(send_and_receive '{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws"'"}}')
    session_id=$(printf '%s' "$session_response" | jq -r '.result.sessionId // empty')
    if [[ -z "$session_id" ]]; then
        stop_interactive_proxy
        fail "session/new did not return sessionId: $session_response"
        return
    fi

    # Verify sessionId is a UUID
    if [[ ${#session_id} -ne 36 ]] || [[ ! "$session_id" =~ ^[0-9a-f-]+$ ]]; then
        stop_interactive_proxy
        fail "Session ID doesn't look like UUID: $session_id"
        return
    fi

    # Send prompt using the obtained session ID
    send_message '{"jsonrpc":"2.0","id":"3","method":"session/prompt","params":{"sessionId":"'"$session_id"'","message":"test prompt"}}'

    # Read the session/update notification
    local update_response update_method update_session_id
    update_response=$(read_response 5)
    update_method=$(printf '%s' "$update_response" | jq -r '.method // empty')

    if [[ "$update_method" != "session/update" ]]; then
        stop_interactive_proxy
        fail "Expected session/update notification, got: $update_response"
        return
    fi

    update_session_id=$(printf '%s' "$update_response" | jq -r '.params.sessionId // empty')
    if [[ "$update_session_id" != "$session_id" ]]; then
        stop_interactive_proxy
        fail "session/update has wrong sessionId: expected $session_id, got $update_session_id"
        return
    fi

    stop_interactive_proxy
    pass "Single session lifecycle works (sessionId=$session_id, prompt -> update verified)"
}

# ==============================================================================
# Test 5: Multiple Simultaneous Sessions
# ==============================================================================

test_multiple_sessions() {
    section "Test 5: Multiple simultaneous sessions"

    local ws1 ws2
    ws1=$(make_temp_dir)
    ws2=$(make_temp_dir)

    local input
    input='{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}
{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws1"'"}}
{"jsonrpc":"2.0","id":"3","method":"session/new","params":{"cwd":"'"$ws2"'"}}'

    run_proxy "$input" 3

    # Parse session IDs
    local s1 s2
    s1=$(get_line 2 | jq -r '.result.sessionId // empty')
    s2=$(get_line 3 | jq -r '.result.sessionId // empty')

    if [[ -z "$s1" ]] || [[ -z "$s2" ]]; then
        fail "Failed to create multiple sessions"
        info "Session 1: $s1"
        info "Session 2: $s2"
        return
    fi

    if [[ "$s1" == "$s2" ]]; then
        fail "Session IDs should be different: $s1 == $s2"
        return
    fi

    pass "Multiple sessions created successfully (s1=$s1, s2=$s2)"
}

# ==============================================================================
# Test 6: Concurrent Output Serialization (with prompts)
# ==============================================================================

test_concurrent_output_serialization() {
    section "Test 6: Concurrent output serialization"

    local ws1 ws2
    ws1=$(make_temp_dir)
    ws2=$(make_temp_dir)

    start_interactive_proxy

    # Initialize
    local init_response
    init_response=$(send_and_receive '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}')
    if ! printf '%s' "$init_response" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        stop_interactive_proxy
        fail "Initialize failed: $init_response"
        return
    fi

    # Create two sessions
    local s1_response s2_response s1 s2
    s1_response=$(send_and_receive '{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws1"'"}}')
    s1=$(printf '%s' "$s1_response" | jq -r '.result.sessionId // empty')

    s2_response=$(send_and_receive '{"jsonrpc":"2.0","id":"3","method":"session/new","params":{"cwd":"'"$ws2"'"}}')
    s2=$(printf '%s' "$s2_response" | jq -r '.result.sessionId // empty')

    if [[ -z "$s1" ]] || [[ -z "$s2" ]]; then
        stop_interactive_proxy
        fail "Could not create sessions for concurrency test"
        return
    fi

    # Send interleaved prompts to both sessions rapidly
    local i
    for i in 1 2 3 4 5; do
        send_message '{"jsonrpc":"2.0","id":"p'"$i"'a","method":"session/prompt","params":{"sessionId":"'"$s1"'","message":"msg'"$i"'"}}'
        send_message '{"jsonrpc":"2.0","id":"p'"$i"'b","method":"session/prompt","params":{"sessionId":"'"$s2"'","message":"msg'"$i"'"}}'
    done

    # Read all responses and verify they're valid JSON (no interleaving)
    local line all_valid=true line_count=0
    while [[ $line_count -lt 10 ]]; do
        line=$(read_response 2)
        if [[ -z "$line" ]]; then
            break
        fi
        ((line_count++)) || true
        if ! printf '%s' "$line" | jq -e . >/dev/null 2>&1; then
            fail "Line $line_count is not valid JSON (interleaving?): $line"
            all_valid=false
            break
        fi
    done

    stop_interactive_proxy

    if $all_valid && [[ $line_count -ge 10 ]]; then
        pass "Concurrent output serialization correct ($line_count session/update notifications, no interleaving)"
    elif $all_valid; then
        fail "Expected at least 10 session/update notifications, got $line_count"
    fi
}

# ==============================================================================
# Test 7: Session ID Namespacing
# ==============================================================================

test_session_id_namespacing() {
    section "Test 7: Session ID namespacing"

    local ws1 ws2
    ws1=$(make_temp_dir)
    ws2=$(make_temp_dir)

    local input
    input='{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}
{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws1"'"}}
{"jsonrpc":"2.0","id":"3","method":"session/new","params":{"cwd":"'"$ws2"'"}}'

    run_proxy "$input" 3

    local s1 s2
    s1=$(get_line 2 | jq -r '.result.sessionId // empty')
    s2=$(get_line 3 | jq -r '.result.sessionId // empty')

    # Session IDs must be different
    if [[ "$s1" == "$s2" ]]; then
        fail "Session IDs are identical (no namespacing): $s1 == $s2"
        return
    fi

    # Session IDs should be UUIDs (proxy-generated), not "mock-session-N"
    if [[ "$s1" == mock-session-* ]]; then
        fail "Session ID is raw agent ID (not namespaced): $s1"
        return
    fi

    # Verify UUIDs look like UUIDs (36 chars with dashes)
    if [[ ${#s1} -ne 36 ]] || [[ ! "$s1" =~ ^[0-9a-f-]+$ ]]; then
        fail "Session ID doesn't look like UUID: $s1"
        return
    fi

    pass "Session IDs are namespaced (UUIDs, not raw agent IDs)"
}

# ==============================================================================
# Test 8: Session Routing by proxySessionId
# ==============================================================================

test_session_routing() {
    section "Test 8: Session routing by proxySessionId"

    local ws1 ws2
    ws1=$(make_temp_dir)
    ws2=$(make_temp_dir)

    start_interactive_proxy

    # Initialize
    local init_response
    init_response=$(send_and_receive '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}')
    if ! printf '%s' "$init_response" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        stop_interactive_proxy
        fail "Initialize failed: $init_response"
        return
    fi

    # Create two sessions
    local s1_response s2_response s1 s2
    s1_response=$(send_and_receive '{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws1"'"}}')
    s1=$(printf '%s' "$s1_response" | jq -r '.result.sessionId // empty')

    s2_response=$(send_and_receive '{"jsonrpc":"2.0","id":"3","method":"session/new","params":{"cwd":"'"$ws2"'"}}')
    s2=$(printf '%s' "$s2_response" | jq -r '.result.sessionId // empty')

    if [[ -z "$s1" ]] || [[ -z "$s2" ]]; then
        stop_interactive_proxy
        fail "Could not create sessions for routing test"
        return
    fi

    # Send prompts to both sessions
    send_message '{"jsonrpc":"2.0","id":"4","method":"session/prompt","params":{"sessionId":"'"$s1"'","message":"msg-for-session1"}}'
    send_message '{"jsonrpc":"2.0","id":"5","method":"session/prompt","params":{"sessionId":"'"$s2"'","message":"msg-for-session2"}}'

    # Read both responses (order may vary)
    local update1 update2 update1_sid update2_sid
    local got_s1=false got_s2=false
    local response i
    for i in 1 2; do
        response=$(read_response 5)
        local sid
        sid=$(printf '%s' "$response" | jq -r '.params.sessionId // empty')
        if [[ "$sid" == "$s1" ]]; then
            got_s1=true
            update1="$response"
            update1_sid="$sid"
        elif [[ "$sid" == "$s2" ]]; then
            got_s2=true
            update2="$response"
            update2_sid="$sid"
        fi
    done

    if ! $got_s1; then
        stop_interactive_proxy
        fail "Did not receive update for session 1 ($s1)"
        return
    fi

    if ! $got_s2; then
        stop_interactive_proxy
        fail "Did not receive update for session 2 ($s2)"
        return
    fi

    stop_interactive_proxy
    pass "Session routing works correctly (prompts routed to correct sessions)"
}

# ==============================================================================
# Test 9: Workspace Resolution
# ==============================================================================

test_workspace_resolution() {
    section "Test 9: Workspace resolution"

    local git_root subdir
    git_root=$(make_temp_dir)
    subdir="$git_root/src/components"

    # Initialize git repo
    mkdir -p "$subdir"
    git -C "$git_root" init >/dev/null 2>&1

    start_interactive_proxy

    # Initialize
    local init_response
    init_response=$(send_and_receive '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}')
    if ! printf '%s' "$init_response" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        stop_interactive_proxy
        fail "Initialize failed: $init_response"
        return
    fi

    # Create session from subdirectory
    local session_response session_id
    session_response=$(send_and_receive '{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$subdir"'"}}')
    session_id=$(printf '%s' "$session_response" | jq -r '.result.sessionId // empty')

    if [[ -z "$session_id" ]]; then
        stop_interactive_proxy
        fail "Failed to create session from subdirectory"
        info "Response: $session_response"
        return
    fi

    # Verify session ID is a valid UUID (proxy generated)
    if [[ ${#session_id} -ne 36 ]] || [[ ! "$session_id" =~ ^[0-9a-f-]+$ ]]; then
        stop_interactive_proxy
        fail "Session ID is not a valid UUID: $session_id"
        return
    fi

    # Check the mock server's stderr log for what cwd it received
    # The proxy should normalize the subdirectory to the container workspace with relative path
    # Expected format: /home/agent/workspace/src/components (container path with relative subdir)
    local mock_log received_cwd
    mock_log=$(get_proxy_stderr)
    # Parse from log line like: "[mock-acp-server] Creating session: mock-session-1 (cwd=/home/agent/workspace/src/components)"
    received_cwd=$(printf '%s' "$mock_log" | grep -o 'cwd=[^)]*' | head -1 | sed 's/cwd=//')

    if [[ -z "$received_cwd" ]]; then
        stop_interactive_proxy
        fail "Could not find received cwd in mock server log"
        info "Mock log: $mock_log"
        return
    fi

    # The proxy should have translated the subdirectory to container workspace + relative path
    # In test mode (direct spawn), the proxy calculates container cwd as:
    # /home/agent/workspace + relative path from git root
    # Since we're in direct spawn mode, it should have normalized to container path
    local expected_container_cwd="/home/agent/workspace/src/components"
    if [[ "$received_cwd" != "$expected_container_cwd" ]]; then
        stop_interactive_proxy
        fail "Workspace not normalized correctly: expected $expected_container_cwd, got $received_cwd"
        return
    fi

    # Send a prompt to verify the session works
    send_message '{"jsonrpc":"2.0","id":"3","method":"session/prompt","params":{"sessionId":"'"$session_id"'","message":"test"}}'
    local update_response update_method
    update_response=$(read_response 5)
    update_method=$(printf '%s' "$update_response" | jq -r '.method // empty')

    if [[ "$update_method" != "session/update" ]]; then
        stop_interactive_proxy
        fail "Session created from subdirectory doesn't work: $update_response"
        return
    fi

    stop_interactive_proxy
    pass "Workspace resolution works (session from subdirectory functional, id=$session_id)"
}

# ==============================================================================
# Test 10: MCP Path Translation
# ==============================================================================

test_mcp_path_translation() {
    section "Test 10: MCP path translation"

    local ws
    ws=$(make_temp_dir)

    start_interactive_proxy

    # Initialize
    local init_response
    init_response=$(send_and_receive '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}')
    if ! printf '%s' "$init_response" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        stop_interactive_proxy
        fail "Initialize failed: $init_response"
        return
    fi

    # Create session with mcpServers config containing absolute and relative paths
    # The proxy should translate absolute paths (starting with $ws) to container paths
    # but preserve relative paths unchanged
    local session_response session_id
    session_response=$(send_and_receive '{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws"'","mcpServers":{"test-server":{"command":"test-mcp","args":["--config","relative/path","--workspace","'"$ws"'","--data","'"$ws"'/data"]}}}}')
    session_id=$(printf '%s' "$session_response" | jq -r '.result.sessionId // empty')

    if [[ -z "$session_id" ]]; then
        stop_interactive_proxy
        fail "Failed to create session with MCP config"
        info "Response: $session_response"
        return
    fi

    # Verify session ID is a valid UUID
    if [[ ${#session_id} -ne 36 ]] || [[ ! "$session_id" =~ ^[0-9a-f-]+$ ]]; then
        stop_interactive_proxy
        fail "Session ID is not a valid UUID: $session_id"
        return
    fi

    # Check the mock server's stderr log for what mcpServers it received
    local mock_log received_mcp
    mock_log=$(get_proxy_stderr)
    # Parse from log line like: "[mock-acp-server] mcpServers: {...}"
    received_mcp=$(printf '%s' "$mock_log" | grep 'mcpServers:' | head -1 | sed 's/.*mcpServers: //')

    if [[ -z "$received_mcp" ]]; then
        stop_interactive_proxy
        fail "Could not find received mcpServers in mock server log"
        info "Mock log: $mock_log"
        return
    fi

    # Validate that relative paths are preserved
    local relative_path
    relative_path=$(printf '%s' "$received_mcp" | jq -r '."test-server".args[1] // empty')
    if [[ "$relative_path" != "relative/path" ]]; then
        stop_interactive_proxy
        fail "Relative path was incorrectly modified: expected 'relative/path', got '$relative_path'"
        return
    fi

    # Validate that absolute paths were translated to container paths
    local workspace_path data_path
    workspace_path=$(printf '%s' "$received_mcp" | jq -r '."test-server".args[3] // empty')
    data_path=$(printf '%s' "$received_mcp" | jq -r '."test-server".args[5] // empty')

    # In test mode, the proxy translates host paths to container paths
    # Host path $ws should become /home/agent/workspace
    if [[ "$workspace_path" != "/home/agent/workspace" ]]; then
        stop_interactive_proxy
        fail "Absolute path not translated: expected '/home/agent/workspace', got '$workspace_path'"
        return
    fi

    if [[ "$data_path" != "/home/agent/workspace/data" ]]; then
        stop_interactive_proxy
        fail "Absolute path with subdir not translated: expected '/home/agent/workspace/data', got '$data_path'"
        return
    fi

    # Send a prompt to verify the session works with MCP config
    send_message '{"jsonrpc":"2.0","id":"3","method":"session/prompt","params":{"sessionId":"'"$session_id"'","message":"test"}}'
    local update_response update_method
    update_response=$(read_response 5)
    update_method=$(printf '%s' "$update_response" | jq -r '.method // empty')

    if [[ "$update_method" != "session/update" ]]; then
        stop_interactive_proxy
        fail "Session with MCP config doesn't work: $update_response"
        return
    fi

    stop_interactive_proxy
    pass "MCP path translation works (session with mcpServers config functional, id=$session_id)"
}

# ==============================================================================
# Test 11: Session Cleanup on session/end
# ==============================================================================

test_session_cleanup() {
    section "Test 11: Session cleanup on session/end"

    local ws
    ws=$(make_temp_dir)

    start_interactive_proxy

    # Initialize
    local init_response
    init_response=$(send_and_receive '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}')
    if ! printf '%s' "$init_response" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        stop_interactive_proxy
        fail "Initialize failed: $init_response"
        return
    fi

    # Create session
    local session_response session_id
    session_response=$(send_and_receive '{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws"'"}}')
    session_id=$(printf '%s' "$session_response" | jq -r '.result.sessionId // empty')

    if [[ -z "$session_id" ]]; then
        stop_interactive_proxy
        fail "Could not create session for cleanup test"
        return
    fi

    # Verify session works before ending it
    send_message '{"jsonrpc":"2.0","id":"3","method":"session/prompt","params":{"sessionId":"'"$session_id"'","message":"before-end"}}'
    local update_before
    update_before=$(read_response 5)
    if ! printf '%s' "$update_before" | jq -e '.method == "session/update"' >/dev/null 2>&1; then
        stop_interactive_proxy
        fail "Session didn't work before ending: $update_before"
        return
    fi

    # End the session (use longer timeout as session/end may wait for agent cleanup)
    local end_response
    end_response=$(send_and_receive '{"jsonrpc":"2.0","id":"4","method":"session/end","params":{"sessionId":"'"$session_id"'"}}' 10)

    # Verify session/end was acknowledged (either result or acceptable error)
    if ! printf '%s' "$end_response" | jq -e '.result or .error' >/dev/null 2>&1; then
        stop_interactive_proxy
        fail "Unexpected session/end response: $end_response"
        return
    fi

    # Try to use the ended session - should fail with "session not found"
    local error_response
    error_response=$(send_and_receive '{"jsonrpc":"2.0","id":"5","method":"session/prompt","params":{"sessionId":"'"$session_id"'","message":"after-end"}}' 5)

    if ! printf '%s' "$error_response" | jq -e '.error' >/dev/null 2>&1; then
        stop_interactive_proxy
        fail "Session still works after session/end: $error_response"
        return
    fi

    stop_interactive_proxy
    pass "Session cleanup works (session/end acknowledged, subsequent prompt fails)"
}

# ==============================================================================
# Test 12: Stdin EOF Graceful Shutdown
# ==============================================================================

test_stdin_eof_shutdown() {
    section "Test 12: Stdin EOF graceful shutdown"

    local ws
    ws=$(make_temp_dir)

    # Send initialize, create session, then EOF - proxy should exit cleanly
    local input
    input='{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}
{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws"'"}}'

    run_proxy "$input"

    # Check exit code - should be 0 or at least not timeout (124)
    if [[ $PROXY_EXIT_CODE -eq 124 ]]; then
        fail "Proxy did not exit on stdin EOF (timed out)"
        return
    fi

    # Verify we got responses before shutdown
    local init_response session_response
    init_response=$(get_line 1)
    session_response=$(get_line 2)

    if ! printf '%s' "$init_response" | jq -e '.result' >/dev/null 2>&1; then
        fail "No initialize response before shutdown"
        return
    fi

    if ! printf '%s' "$session_response" | jq -e '.result.sessionId' >/dev/null 2>&1; then
        fail "No session/new response before shutdown"
        return
    fi

    pass "Proxy handles stdin EOF gracefully (exit code: $PROXY_EXIT_CODE)"
}

# ==============================================================================
# Test 13: Error Handling - Session Not Found
# ==============================================================================

test_error_session_not_found() {
    section "Test 13: Error handling - session not found"

    local input
    input='{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}
{"jsonrpc":"2.0","id":"2","method":"session/prompt","params":{"sessionId":"nonexistent-session","message":"test"}}'

    run_proxy "$input" 2

    local error_response
    error_response=$(get_line 2)

    # Should have an error
    if ! printf '%s' "$error_response" | jq -e '.error' >/dev/null 2>&1; then
        fail "Expected error for nonexistent session: $error_response"
        return
    fi

    local error_code
    error_code=$(printf '%s' "$error_response" | jq -r '.error.code // empty')

    if [[ -z "$error_code" ]]; then
        fail "Error response missing code: $error_response"
        return
    fi

    pass "Session not found returns proper error (code=$error_code)"
}

# ==============================================================================
# Test 14: Numeric JSON-RPC IDs
# ==============================================================================

test_numeric_ids() {
    section "Test 14: Numeric JSON-RPC IDs"

    run_proxy '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-01-01"}}' 1
    local response="$PROXY_OUTPUT"

    # Verify response has same ID (numeric)
    local response_id
    response_id=$(printf '%s' "$response" | jq '.id')

    if [[ "$response_id" != "1" ]]; then
        fail "Numeric ID not preserved: expected 1, got $response_id"
        return
    fi

    pass "Numeric JSON-RPC IDs handled correctly"
}

# ==============================================================================
# Test 15: Unknown Method Returns Error
# ==============================================================================

test_unknown_method() {
    section "Test 15: Unknown method returns error"

    run_proxy '{"jsonrpc":"2.0","id":"1","method":"unknown/method","params":{}}' 1
    local response="$PROXY_OUTPUT"

    # Should have an error
    if ! printf '%s' "$response" | jq -e '.error' >/dev/null 2>&1; then
        fail "Expected error for unknown method: $response"
        return
    fi

    local error_code
    error_code=$(printf '%s' "$response" | jq -r '.error.code // empty')

    # -32601 is "Method not found" in JSON-RPC
    if [[ "$error_code" != "-32601" ]]; then
        info "Got error code: $error_code (expected -32601)"
    fi

    pass "Unknown method returns proper error"
}

# ==============================================================================
# Test 16: Generic Agent Support - Accepts Any Agent Name
# ==============================================================================

test_generic_agent_accepts_any_name() {
    section "Test 16: Generic agent support - accepts any name"

    # The proxy should accept any agent name without hardcoded validation.
    # In test mode with direct spawn, the proxy will try to run the agent binary.
    # We use "my-custom-agent" which doesn't exist to verify:
    # 1. The proxy ACCEPTS the agent name (no ArgumentException)
    # 2. Session creation fails gracefully with a clear error message

    local tmpfile
    tmpfile=$(mktemp)
    TEMP_FILES+=("$tmpfile")

    local tmpstderr
    tmpstderr=$(mktemp)
    TEMP_FILES+=("$tmpstderr")

    # Try a custom agent name - proxy should accept it
    # Note: we're testing that it doesn't reject the name upfront
    local exit_code=0
    (printf '%s\n' '{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}'; sleep 0.1) \
        | run_with_timeout "$TEST_TIMEOUT" "${PROXY_CMD[@]}" "my-custom-agent" 2>"$tmpstderr" > "$tmpfile" || exit_code=$?

    local response
    response=$(< "$tmpfile")

    # The proxy should start and respond to initialize (not reject the agent name)
    if [[ -z "$response" ]]; then
        # Check if it failed with "Unsupported agent" - that means validation wasn't removed
        local stderr_output
        stderr_output=$(< "$tmpstderr")
        if printf '%s' "$stderr_output" | grep -q "Unsupported agent"; then
            fail "Proxy still has hardcoded agent validation: $stderr_output"
            return
        fi
        fail "No response from proxy with custom agent"
        return
    fi

    # Should be valid JSON
    if ! printf '%s' "$response" | jq -e . >/dev/null 2>&1; then
        fail "Response is not valid JSON: $response"
        return
    fi

    # Should be an initialize response (proxy accepted the agent name)
    if printf '%s' "$response" | jq -e '.result.protocolVersion' >/dev/null 2>&1; then
        pass "Proxy accepts any agent name (custom agent 'my-custom-agent' allowed)"
    else
        fail "Unexpected response: $response"
    fi
}

# ==============================================================================
# Test 17: Generic Agent Support - Clear Error for Missing Agent
# ==============================================================================

test_generic_agent_missing_error() {
    section "Test 17: Generic agent support - clear error for missing agent"

    # Test that when session/new is called with a nonexistent agent,
    # the error message clearly indicates the agent is not found.

    local ws
    ws=$(make_temp_dir)

    local tmpfile
    tmpfile=$(mktemp)
    TEMP_FILES+=("$tmpfile")

    local tmpstderr
    tmpstderr=$(mktemp)
    TEMP_FILES+=("$tmpstderr")

    # Initialize and create session with nonexistent agent
    local input
    input='{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}
{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws"'"}}'

    (printf '%s\n' "$input"; sleep 0.5) \
        | run_with_timeout "$TEST_TIMEOUT" "${PROXY_CMD[@]}" "nonexistent-agent-xyz" 2>"$tmpstderr" > "$tmpfile" || true

    # Check stderr for the error message
    local stderr_output
    stderr_output=$(< "$tmpstderr")

    # The error should mention the agent name clearly
    # It could be from direct spawn (Win32Exception) or container preflight check
    if printf '%s' "$stderr_output" | grep -qi "nonexistent-agent-xyz"; then
        pass "Missing agent produces clear error mentioning agent name"
    else
        # Also check if session/new response has a clear error
        local output
        output=$(< "$tmpfile")
        local session_response
        session_response=$(printf '%s' "$output" | sed -n '2p')

        if printf '%s' "$session_response" | jq -e '.error.message' 2>/dev/null | grep -qi "nonexistent-agent-xyz\|not found"; then
            pass "Missing agent produces clear error in JSON-RPC response"
        else
            info "stderr: $stderr_output"
            info "stdout: $output"
            fail "Error message doesn't clearly indicate missing agent"
        fi
    fi
}

# ==============================================================================
# Test 18: Generic Agent Support - No Shell Injection (Direct Spawn)
# ==============================================================================

test_generic_agent_no_injection() {
    section "Test 18: Generic agent support - no shell injection (direct spawn)"

    # Test that agent names with shell metacharacters don't cause injection.
    # We use a carefully crafted agent name that would cause issues if improperly quoted.
    #
    # NOTE: This test runs with CAI_ACP_DIRECT_SPAWN=1 (direct spawn mode), which uses
    # Process.Start() with ArgumentList (safe from injection by design).
    #
    # The containerized path (bash -c wrapper via cai exec) is protected by:
    # 1. Process.Start() with ArgumentList for cai exec invocation
    # 2. Agent passed as positional parameter $1, not interpolated into shell string
    # 3. 'exec -- "$1"' uses -- to handle agent names starting with dash
    #
    # Testing containerized injection would require a full container environment;
    # the wrapper design is audited in code review instead.

    local ws
    ws=$(make_temp_dir)

    local tmpfile
    tmpfile=$(mktemp)
    TEMP_FILES+=("$tmpfile")

    local tmpstderr
    tmpstderr=$(mktemp)
    TEMP_FILES+=("$tmpstderr")

    # Agent name with shell metacharacters
    # If improperly handled, this could execute "touch /tmp/pwned"
    local malicious_agent='agent; touch /tmp/test-injection-pwned; #'

    # Initialize and try to create session
    local input
    input='{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-01-01"}}
{"jsonrpc":"2.0","id":"2","method":"session/new","params":{"cwd":"'"$ws"'"}}'

    rm -f /tmp/test-injection-pwned 2>/dev/null || true

    (printf '%s\n' "$input"; sleep 0.5) \
        | run_with_timeout "$TEST_TIMEOUT" "${PROXY_CMD[@]}" "$malicious_agent" 2>"$tmpstderr" > "$tmpfile" || true

    # Check that the injection file was NOT created
    if [[ -f /tmp/test-injection-pwned ]]; then
        rm -f /tmp/test-injection-pwned
        fail "Shell injection vulnerability detected!"
        return
    fi

    pass "Shell metacharacters in agent name are safely handled (no injection)"
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    printf '%s\n' "=============================================================================="
    printf '%s\n' "Integration Tests for ACP Proxy"
    printf '%s\n' "=============================================================================="

    check_prerequisites

    # Run all tests
    test_ndjson_framing
    test_stdout_purity
    test_initialize_response
    test_single_session
    test_multiple_sessions
    test_concurrent_output_serialization
    test_session_id_namespacing
    test_session_routing
    test_workspace_resolution
    test_mcp_path_translation
    test_session_cleanup
    test_stdin_eof_shutdown
    test_error_session_not_found
    test_numeric_ids
    test_unknown_method
    test_generic_agent_accepts_any_name
    test_generic_agent_missing_error
    test_generic_agent_no_injection

    # Summary
    # TEST_COUNT includes prerequisites as a section, subtract 1 for actual test count
    local actual_tests=$((TEST_COUNT - 1))
    # PASS_COUNT includes prereq checks (5), subtract for actual test passes
    local actual_passes=$((PASS_COUNT - 5))
    printf '\n'
    printf '%s\n' "=============================================================================="
    printf '%s\n' "Results: $actual_passes/$actual_tests tests passed"
    if [[ "$FAILED" -eq 0 ]]; then
        printf '%s\n' "All tests passed!"
        exit 0
    else
        printf '%s\n' "Some tests failed!"
        exit 1
    fi
}

main "$@"
