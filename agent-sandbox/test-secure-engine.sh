#!/usr/bin/env bash
# ==============================================================================
# Integration tests for ContainAI Secure Engine
# ==============================================================================
# Verifies:
# 1. containai-secure Docker context exists with correct endpoint
# 2. Engine is reachable via context
# 3. sysbox-runc runtime is available (NOT default - by design)
# 4. User namespace isolation works with --runtime=sysbox-runc
# 5. Test container runs successfully with --runtime=sysbox-runc
# 6. Platform-specific tests (WSL socket, macOS Lima VM)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Source containai library for platform detection, _cai_timeout, and constants
# Don't suppress stderr - show error output on failure
if ! source "$SCRIPT_DIR/containai.sh"; then
    printf '%s\n' "[ERROR] Failed to source containai.sh" >&2
    exit 1
fi

# ==============================================================================
# Test helpers - match test-sync-integration.sh pattern
# ==============================================================================

# Color output helpers
pass() { printf '%s\n' "[PASS] $*"; }
fail() { printf '%s\n' "[FAIL] $*" >&2; FAILED=1; }
warn() { printf '%s\n' "[WARN] $*"; }
info() { printf '%s\n' "[INFO] $*"; }
section() { printf '\n'; printf '%s\n' "=== $* ==="; }

FAILED=0

# Context name constant
CONTEXT_NAME="containai-secure"

# Default timeout for docker commands (seconds)
TEST_TIMEOUT=30

# Pinned image for reproducibility
TEST_IMAGE="alpine:3.20"

# Portable timeout wrapper (uses _cai_timeout from containai.sh)
# Returns 124 on timeout, 125 if no timeout mechanism available
run_with_timeout() {
    local secs="$1"
    shift
    _cai_timeout "$secs" "$@"
}

# ==============================================================================
# Test 1: Context exists with correct endpoint
# ==============================================================================
test_context_exists() {
    section "Test 1: Context exists with correct endpoint"

    # Determine expected socket based on platform
    local platform expected_socket
    platform=$(_cai_detect_platform)
    case "$platform" in
        wsl|linux)
            expected_socket="unix://$_CAI_SECURE_SOCKET"
            ;;
        macos)
            expected_socket="unix://$_CAI_LIMA_SOCKET_PATH"
            ;;
        *)
            warn "Unknown platform: $platform - skipping endpoint check"
            expected_socket=""
            ;;
    esac

    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        fail "Context '$CONTEXT_NAME' not found"
        info "  Remediation: Run 'cai setup' to create the context"
        return
    fi

    local actual_endpoint
    actual_endpoint=$(docker context inspect "$CONTEXT_NAME" --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)

    if [[ -n "$expected_socket" ]] && [[ "$actual_endpoint" != "$expected_socket" ]]; then
        fail "Context '$CONTEXT_NAME' has wrong endpoint"
        info "  Expected: $expected_socket"
        info "  Actual: $actual_endpoint"
        info "  Remediation: Run 'cai setup' to reconfigure the context"
    else
        pass "Context '$CONTEXT_NAME' exists with correct endpoint"
        info "  Endpoint: $actual_endpoint"
    fi
}

# ==============================================================================
# Test 2: Engine reachable
# ==============================================================================
test_engine_reachable() {
    section "Test 2: Engine is reachable"

    local info_output info_rc
    info_output=$(run_with_timeout "$TEST_TIMEOUT" docker --context "$CONTEXT_NAME" info 2>&1) && info_rc=0 || info_rc=$?

    # Handle no timeout mechanism available
    if [[ $info_rc -eq 125 ]]; then
        warn "No timeout mechanism available, running without timeout"
        info_output=$(docker --context "$CONTEXT_NAME" info 2>&1) && info_rc=0 || info_rc=$?
    fi

    if [[ $info_rc -eq 124 ]]; then
        fail "Engine connection timed out after ${TEST_TIMEOUT}s"
        info "  Remediation: Check if Docker daemon is responding"
    elif [[ $info_rc -eq 0 ]]; then
        pass "Engine is reachable via context '$CONTEXT_NAME'"
        # Store info_output for use by other tests
        _TEST_INFO_OUTPUT="$info_output"
        local server_version
        server_version=$(printf '%s' "$info_output" | grep "Server Version:" | head -1 | sed 's/.*Server Version:[[:space:]]*//' || true)
        [[ -n "$server_version" ]] && info "  Docker version: $server_version"
    else
        fail "Engine not reachable via context '$CONTEXT_NAME'"
        info "  Error: $(printf '%s' "$info_output" | head -3)"
    fi
}

# ==============================================================================
# Test 3: sysbox-runc runtime is available
# ==============================================================================
test_sysbox_runtime() {
    section "Test 3: sysbox-runc runtime is available"

    # Note: sysbox-runc is NOT the default runtime (by design) - we check availability
    local runtimes_json runtime_rc
    runtimes_json=$(run_with_timeout "$TEST_TIMEOUT" docker --context "$CONTEXT_NAME" info --format '{{json .Runtimes}}' 2>/dev/null) && runtime_rc=0 || runtime_rc=$?

    # Handle no timeout mechanism available
    if [[ $runtime_rc -eq 125 ]]; then
        runtimes_json=$(docker --context "$CONTEXT_NAME" info --format '{{json .Runtimes}}' 2>/dev/null || true)
    fi

    if [[ -z "$runtimes_json" ]] || [[ "$runtimes_json" == "null" ]]; then
        fail "Could not query available runtimes"
        return
    fi

    if printf '%s' "$runtimes_json" | grep -q "sysbox-runc"; then
        pass "sysbox-runc runtime is available"
        info "  Available runtimes: $runtimes_json"
    else
        fail "sysbox-runc runtime is NOT available"
        info "  Available runtimes: $runtimes_json"
        info "  Remediation: Run 'cai setup' to install Sysbox"
    fi
}

# ==============================================================================
# Test 4: User namespace enabled (with sysbox-runc)
# ==============================================================================
test_user_namespace() {
    section "Test 4: User namespace isolation (sysbox-runc)"

    local uid_map_output uid_map_rc
    # Use pinned image with --pull=never first, then try with pull if missing
    # Must use explicit --runtime=sysbox-runc since sysbox is NOT the default runtime
    uid_map_output=$(run_with_timeout "$TEST_TIMEOUT" docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc --pull=never "$TEST_IMAGE" cat /proc/self/uid_map 2>&1) && uid_map_rc=0 || uid_map_rc=$?

    # Handle no timeout mechanism available
    if [[ $uid_map_rc -eq 125 ]]; then
        uid_map_output=$(docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc --pull=never "$TEST_IMAGE" cat /proc/self/uid_map 2>&1) && uid_map_rc=0 || uid_map_rc=$?
    fi

    # Handle missing image - try with pull (use proper grouping to avoid precedence bug)
    if [[ $uid_map_rc -ne 0 ]] && { [[ "$uid_map_output" == *"image"*"not"*"found"* ]] || [[ "$uid_map_output" == *"No such image"* ]]; }; then
        info "  Pulling $TEST_IMAGE image..."
        uid_map_output=$(run_with_timeout 60 docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc "$TEST_IMAGE" cat /proc/self/uid_map 2>&1) && uid_map_rc=0 || uid_map_rc=$?
        [[ $uid_map_rc -eq 125 ]] && uid_map_output=$(docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc "$TEST_IMAGE" cat /proc/self/uid_map 2>&1) && uid_map_rc=0 || uid_map_rc=$?
    fi

    if [[ $uid_map_rc -eq 124 ]]; then
        fail "User namespace check timed out after ${TEST_TIMEOUT}s"
        return
    fi

    if [[ $uid_map_rc -ne 0 ]]; then
        fail "Could not run test container to check user namespace"
        info "  Error: $uid_map_output"
        return
    fi

    # Parse uid_map robustly: normalize whitespace and check for full range
    # Format: "         0          0 4294967295" or similar with variable whitespace
    local uid_map_normalized
    uid_map_normalized=$(printf '%s' "$uid_map_output" | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')

    # Check if first line shows full UID range (0 0 4294967295 = no remapping)
    # Sysbox should show mapped UIDs like "0 165536 65536" (container root mapped to host subuid)
    if printf '%s' "$uid_map_normalized" | head -1 | grep -qE '^0 0 4294967295'; then
        # Full UID range mapping = no user namespace remapping - this is a FAIL
        fail "User namespace isolation is NOT enabled"
        info "  uid_map shows full range (no remapping): $uid_map_normalized"
        info "  Remediation: Verify Sysbox is properly configured"
    else
        pass "User namespace isolation is enabled"
        info "  uid_map: $uid_map_normalized"
    fi
}

# ==============================================================================
# Test 5: Test container runs successfully (with sysbox-runc)
# ==============================================================================
test_container_runs() {
    section "Test 5: Test container runs successfully (sysbox-runc)"

    local test_output test_rc
    # Use pinned image with --pull=never first
    # Must use explicit --runtime=sysbox-runc since sysbox is NOT the default runtime
    test_output=$(run_with_timeout "$TEST_TIMEOUT" docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc --pull=never "$TEST_IMAGE" echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?

    # Handle no timeout mechanism available
    if [[ $test_rc -eq 125 ]]; then
        test_output=$(docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc --pull=never "$TEST_IMAGE" echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?
    fi

    # Handle missing image - try with pull (use proper grouping to avoid precedence bug)
    if [[ $test_rc -ne 0 ]] && { [[ "$test_output" == *"image"*"not"*"found"* ]] || [[ "$test_output" == *"No such image"* ]]; }; then
        test_output=$(run_with_timeout 60 docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc "$TEST_IMAGE" echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?
        [[ $test_rc -eq 125 ]] && test_output=$(docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc "$TEST_IMAGE" echo "sysbox-test-ok" 2>&1) && test_rc=0 || test_rc=$?
    fi

    if [[ $test_rc -eq 124 ]]; then
        fail "Test container timed out after ${TEST_TIMEOUT}s"
    elif [[ $test_rc -eq 0 ]] && [[ "$test_output" == *"sysbox-test-ok"* ]]; then
        pass "Test container ran successfully"
    else
        fail "Test container failed to run"
        info "  Exit code: $test_rc"
        info "  Output: $test_output"
    fi
}

# ==============================================================================
# Test 6: Platform-specific tests
# ==============================================================================
test_platform_specific() {
    section "Test 6: Platform-specific validation"

    local platform
    platform=$(_cai_detect_platform)
    info "Detected platform: $platform"

    case "$platform" in
        wsl)
            test_wsl_specific
            ;;
        macos)
            test_macos_specific
            ;;
        linux)
            test_linux_specific
            ;;
        *)
            warn "Unknown platform: $platform (skipping platform-specific tests)"
            ;;
    esac
}

# WSL-specific tests
test_wsl_specific() {
    info "Running WSL-specific tests"

    # Check socket path exists
    local socket_path="$_CAI_SECURE_SOCKET"
    if [[ -S "$socket_path" ]]; then
        pass "WSL socket exists: $socket_path"
    else
        fail "WSL socket not found: $socket_path"
        info "  Remediation: Run 'cai setup' to configure the Docker socket"
    fi

    # Verify WSL2 (not WSL1)
    if _cai_is_wsl2; then
        pass "Running on WSL2 (required for Sysbox)"
    else
        fail "Running on WSL1 - WSL2 is required for Sysbox"
        info "  Convert to WSL2: wsl --set-version <distro> 2"
    fi

    # Check systemd is running
    local pid1_cmd
    pid1_cmd=$(ps -p 1 -o comm= 2>/dev/null || true)
    if [[ "$pid1_cmd" == "systemd" ]]; then
        pass "Systemd is running as PID 1 (required for Sysbox service)"
    else
        warn "Systemd not running as PID 1 (found: $pid1_cmd)"
        info "  Configure WSL to boot with systemd via /etc/wsl.conf"
    fi

    # Check sysbox services
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet sysbox-mgr 2>/dev/null; then
            pass "sysbox-mgr service is running"
        else
            warn "sysbox-mgr service is not running"
            info "  Start with: sudo systemctl start sysbox-mgr"
        fi
        if systemctl is-active --quiet sysbox-fs 2>/dev/null; then
            pass "sysbox-fs service is running"
        else
            warn "sysbox-fs service is not running"
            info "  Start with: sudo systemctl start sysbox-fs"
        fi
    fi
}

# macOS-specific tests
test_macos_specific() {
    info "Running macOS-specific tests"

    # Check Lima is installed
    if command -v limactl >/dev/null 2>&1; then
        pass "Lima is installed"
        local lima_version
        lima_version=$(limactl --version 2>/dev/null | head -1 || true)
        info "  Version: $lima_version"
    else
        fail "Lima not installed"
        info "  Install with: brew install lima"
        return
    fi

    # Check Lima VM exists and is running
    local vm_name="$_CAI_LIMA_VM_NAME"
    if limactl list --format '{{.Name}}' 2>/dev/null | grep -qx "$vm_name"; then
        pass "Lima VM '$vm_name' exists"
        local vm_status
        vm_status=$(limactl list --format '{{.Name}}\t{{.Status}}' 2>/dev/null | grep "^${vm_name}[[:space:]]" | cut -f2 || true)
        if [[ "$vm_status" == "Running" ]]; then
            pass "Lima VM is running"
        else
            fail "Lima VM is not running (status: $vm_status)"
            info "  Start with: limactl start $vm_name"
        fi
    else
        fail "Lima VM '$vm_name' not found"
        info "  Remediation: Run 'cai setup' to create the VM"
    fi

    # Check Lima socket path
    local socket_path="$_CAI_LIMA_SOCKET_PATH"
    if [[ -S "$socket_path" ]]; then
        pass "Lima socket exists: $socket_path"
    else
        fail "Lima socket not found: $socket_path"
        info "  Remediation: Ensure Lima VM is running"
    fi

    # Verify Docker Desktop is still default context (safety check)
    local current_context
    current_context=$(docker context show 2>/dev/null || true)
    if [[ "$current_context" == "containai-secure" ]]; then
        warn "containai-secure is the active context - Docker Desktop should be default"
        info "  Switch back: docker context use default"
    elif [[ "$current_context" == "default" ]] || [[ "$current_context" == "desktop-linux" ]]; then
        pass "Docker Desktop remains the active context: $current_context"
    else
        info "Current context: $current_context (not containai-secure - acceptable)"
    fi
}

# Linux-specific tests (native Linux, not WSL)
test_linux_specific() {
    info "Running Linux-specific tests"

    # Check socket path
    local socket_path="$_CAI_SECURE_SOCKET"
    if [[ -S "$socket_path" ]]; then
        pass "Linux socket exists: $socket_path"
    else
        # Socket might be at default location if setup not run
        warn "Dedicated socket not found: $socket_path"
        info "  Note: Native Linux Sysbox setup may use different configuration"
    fi

    # Check sysbox binaries
    if command -v sysbox-runc >/dev/null 2>&1; then
        pass "sysbox-runc is installed"
        local sysbox_version
        sysbox_version=$(sysbox-runc --version 2>/dev/null | head -1 || true)
        info "  Version: $sysbox_version"
    else
        fail "sysbox-runc not found in PATH"
    fi

    # Check sysbox services (if systemd available)
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet sysbox-mgr 2>/dev/null; then
            pass "sysbox-mgr service is running"
        else
            warn "sysbox-mgr service is not running"
        fi
    fi
}

# ==============================================================================
# Test 7: Idempotency test (can run multiple times)
# ==============================================================================
test_idempotency() {
    section "Test 7: Idempotency (repeat key tests)"

    # Run the core test twice to ensure no state changes
    # Must use explicit --runtime=sysbox-runc since sysbox is NOT the default runtime
    local first_result second_result first_rc second_rc

    info "First run: checking container execution (sysbox-runc)"
    first_result=$(run_with_timeout "$TEST_TIMEOUT" docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc --pull=never "$TEST_IMAGE" echo "idempotency-test" 2>&1) && first_rc=0 || first_rc=$?
    [[ $first_rc -eq 125 ]] && first_result=$(docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc --pull=never "$TEST_IMAGE" echo "idempotency-test" 2>&1) && first_rc=0 || first_rc=$?

    info "Second run: checking container execution (sysbox-runc)"
    second_result=$(run_with_timeout "$TEST_TIMEOUT" docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc --pull=never "$TEST_IMAGE" echo "idempotency-test" 2>&1) && second_rc=0 || second_rc=$?
    [[ $second_rc -eq 125 ]] && second_result=$(docker --context "$CONTEXT_NAME" run --rm --runtime=sysbox-runc --pull=never "$TEST_IMAGE" echo "idempotency-test" 2>&1) && second_rc=0 || second_rc=$?

    if [[ $first_rc -eq $second_rc ]] && [[ "$first_result" == "$second_result" ]] && [[ "$first_result" == *"idempotency-test"* ]]; then
        pass "Tests are idempotent (same result on repeated runs)"
    else
        warn "Test results differ between runs"
        info "  First (rc=$first_rc): $first_result"
        info "  Second (rc=$second_rc): $second_result"
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    printf '%s\n' "=============================================================================="
    printf '%s\n' "Integration Tests for ContainAI Secure Engine"
    printf '%s\n' "=============================================================================="

    # Check prerequisites
    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] docker is required" >&2
        exit 1
    fi

    # Note: We use _cai_timeout from containai.sh which is portable (no hard timeout dependency)

    # Check if context exists before running tests
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        printf '\n'
        printf '%s\n' "[WARN] Context '$CONTEXT_NAME' does not exist"
        printf '%s\n' "[WARN] Run 'cai setup' first to configure Secure Engine"
        printf '%s\n' "[WARN] Running tests anyway to show expected failures..."
        printf '\n'
    fi

    # Run tests
    test_context_exists
    test_engine_reachable
    test_sysbox_runtime
    test_user_namespace
    test_container_runs
    test_platform_specific
    test_idempotency

    # Summary
    printf '\n'
    printf '%s\n' "=============================================================================="
    if [[ "$FAILED" -eq 0 ]]; then
        printf '%s\n' "All tests passed!"
        exit 0
    else
        printf '%s\n' "Some tests failed!"
        printf '%s\n' "Run 'cai setup' to configure Secure Engine, then re-run tests."
        exit 1
    fi
}

main "$@"
