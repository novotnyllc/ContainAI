#!/usr/bin/env bash
# ==============================================================================
# Integration tests for Docker-in-Docker (DinD) in Sysbox System Containers
# ==============================================================================
# Verifies:
# 1. System container starts with systemd as PID 1
# 2. Inner dockerd starts and becomes ready
# 3. docker run hello-world works inside container
# 4. docker build works inside container
# 5. Nested container networking works (can reach internet)
# 6. Clear error handling when dockerd fails
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SRC_DIR="$REPO_ROOT/src"

# Source containai library for platform detection, _cai_timeout, and constants
if ! source "$SRC_DIR/containai.sh"; then
    printf '%s\n' "[ERROR] Failed to source containai.sh" >&2
    exit 1
fi

# ==============================================================================
# Test helpers - match existing test patterns
# ==============================================================================

pass() { printf '%s\n' "[PASS] $*"; }
fail() {
    printf '%s\n' "[FAIL] $*" >&2
    FAILED=1
}
warn() { printf '%s\n' "[WARN] $*"; }
info() { printf '%s\n' "[INFO] $*"; }
section() {
    printf '\n'
    printf '%s\n' "=== $* ==="
}

FAILED=0

# Context name for sysbox containers - use from lib/docker.sh (sourced via containai.sh)
CONTEXT_NAME="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"

# Timeouts
DOCKERD_WAIT_TIMEOUT=60
TEST_TIMEOUT=60
CONTAINER_STOP_TIMEOUT=30

# Test container name (unique per run to avoid conflicts)
TEST_CONTAINER_NAME="containai-dind-test-$$"

# ContainAI base image for system container testing
# Use base image as it has everything needed (systemd + dockerd)
TEST_IMAGE="${CONTAINAI_TEST_IMAGE:-ghcr.io/novotnyllc/containai/base:latest}"

# Cleanup function
cleanup() {
    info "Cleaning up test container..."

    # Stop and remove test container (ignore errors)
    if docker --context "$CONTEXT_NAME" inspect --type container "$TEST_CONTAINER_NAME" >/dev/null 2>&1; then
        docker --context "$CONTEXT_NAME" stop --time "$CONTAINER_STOP_TIMEOUT" "$TEST_CONTAINER_NAME" 2>/dev/null || true
        docker --context "$CONTEXT_NAME" rm -f "$TEST_CONTAINER_NAME" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Portable timeout wrapper (uses _cai_timeout from containai.sh)
run_with_timeout() {
    local secs="$1"
    shift
    if [[ $# -eq 0 ]]; then
        return 0
    fi

    local cmd="$1"
    shift

    # If the command is a shell function, run it via bash -c so timeout can exec it
    if declare -F "$cmd" >/dev/null 2>&1; then
        local func_def
        func_def="$(declare -f "$cmd")"
        FUNC_DEF="$func_def" FUNC_NAME="$cmd" \
            _cai_timeout "$secs" bash -c 'eval "$FUNC_DEF"; "$FUNC_NAME" "$@"' -- "$@"
    else
        _cai_timeout "$secs" "$cmd" "$@"
    fi
}

# Wait for dockerd to be ready inside container
# Returns 0 when dockerd is ready, 1 on timeout
wait_for_dockerd() {
    local container="$1"
    local timeout="${2:-$DOCKERD_WAIT_TIMEOUT}"
    local elapsed=0
    local interval=2

    info "Waiting for inner dockerd to start (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        # Check if docker info succeeds inside the container
        if docker --context "$CONTEXT_NAME" exec "$container" docker info >/dev/null 2>&1; then
            info "Inner dockerd is ready (took ${elapsed}s)"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    return 1
}

# Execute command inside the system container
exec_in_container() {
    docker --context "$CONTEXT_NAME" exec "$TEST_CONTAINER_NAME" "$@"
}

# ==============================================================================
# Test 1: Start system container with sysbox-runc
# ==============================================================================
test_system_container_start() {
    section "Test 1: Start system container with sysbox-runc"

    # Check if context exists first
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        fail "Context '$CONTEXT_NAME' not found"
        info "  Remediation: Run 'cai setup' to configure Sysbox"
        return 1
    fi

    # Pull image if needed
    if ! docker --context "$CONTEXT_NAME" image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
        info "Pulling test image: $TEST_IMAGE"
        if ! run_with_timeout 120 docker --context "$CONTEXT_NAME" pull "$TEST_IMAGE"; then
            fail "Failed to pull test image: $TEST_IMAGE"
            return 1
        fi
    fi

    # Start system container with sysbox-runc runtime
    # The container runs systemd as PID 1 and auto-starts dockerd
    info "Starting system container with sysbox-runc runtime..."

    local run_output run_rc
    run_output=$(docker --context "$CONTEXT_NAME" run -d \
        --runtime=sysbox-runc \
        --name "$TEST_CONTAINER_NAME" \
        --stop-timeout "$CONTAINER_STOP_TIMEOUT" \
        "$TEST_IMAGE" 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -ne 0 ]]; then
        fail "Failed to start system container"
        info "  Error: $run_output"
        return 1
    fi

    # Verify container is running
    local container_status
    container_status=$(docker --context "$CONTEXT_NAME" inspect --format '{{.State.Status}}' "$TEST_CONTAINER_NAME" 2>/dev/null) || container_status=""

    if [[ "$container_status" != "running" ]]; then
        fail "Container not running (status: $container_status)"
        return 1
    fi

    pass "System container started successfully"
}

# ==============================================================================
# Test 2: Verify systemd is PID 1
# ==============================================================================
test_systemd_pid1() {
    section "Test 2: Verify systemd is PID 1"

    local pid1_cmd
    pid1_cmd=$(exec_in_container cat /proc/1/comm 2>/dev/null) || pid1_cmd=""

    if [[ "$pid1_cmd" == "systemd" ]]; then
        pass "systemd is running as PID 1"
    else
        fail "PID 1 is not systemd (found: $pid1_cmd)"
        info "  System containers require systemd as init"
        return 1
    fi
}

# ==============================================================================
# Test 3: Wait for inner dockerd to start
# ==============================================================================
test_dockerd_ready() {
    section "Test 3: Inner dockerd starts successfully"

    if wait_for_dockerd "$TEST_CONTAINER_NAME" "$DOCKERD_WAIT_TIMEOUT"; then
        pass "Inner dockerd is running and responsive"

        # Show docker version for debugging
        local docker_version
        docker_version=$(exec_in_container docker version --format '{{.Server.Version}}' 2>/dev/null) || docker_version="unknown"
        info "  Inner Docker version: $docker_version"
    else
        fail "Inner dockerd failed to start within ${DOCKERD_WAIT_TIMEOUT}s"

        # Collect diagnostic information
        info "Diagnostic information:"

        # Check docker service status
        # Note: systemctl status returns non-zero for failed/inactive services, so we
        # capture output first and only use "(unavailable)" if exec itself fails
        local service_status service_status_rc
        service_status=$(exec_in_container systemctl status docker.service --no-pager 2>&1 | head -20) && service_status_rc=0 || service_status_rc=$?
        if [[ -z "$service_status" ]]; then
            service_status="(unavailable - exec failed with rc=$service_status_rc)"
        fi
        info "  docker.service status:"
        printf '%s\n' "$service_status" | while IFS= read -r line; do
            info "    $line"
        done

        # Check journal logs for docker
        # Note: journalctl may return non-zero in some container environments
        local journal_logs journal_logs_rc
        journal_logs=$(exec_in_container journalctl -u docker.service --no-pager -n 20 2>&1) && journal_logs_rc=0 || journal_logs_rc=$?
        if [[ -z "$journal_logs" ]]; then
            journal_logs="(unavailable - exec failed with rc=$journal_logs_rc)"
        fi
        info "  Recent docker.service logs:"
        printf '%s\n' "$journal_logs" | while IFS= read -r line; do
            info "    $line"
        done

        return 1
    fi
}

# ==============================================================================
# Test 4: docker run hello-world inside container
# ==============================================================================
test_hello_world() {
    section "Test 4: docker run hello-world inside container"

    local hello_output hello_rc
    hello_output=$(run_with_timeout "$TEST_TIMEOUT" exec_in_container docker run --rm hello-world 2>&1) && hello_rc=0 || hello_rc=$?

    # Handle no timeout mechanism
    if [[ $hello_rc -eq 125 ]]; then
        hello_output=$(exec_in_container docker run --rm hello-world 2>&1) && hello_rc=0 || hello_rc=$?
    fi

    if [[ $hello_rc -eq 124 ]]; then
        fail "docker run hello-world timed out after ${TEST_TIMEOUT}s"
        return 1
    fi

    if [[ $hello_rc -eq 0 ]] && printf '%s' "$hello_output" | grep -qi "Hello from Docker"; then
        pass "docker run hello-world succeeded inside system container"
    else
        fail "docker run hello-world failed"
        info "  Exit code: $hello_rc"
        info "  Output: $(printf '%s' "$hello_output" | head -5)"
        return 1
    fi
}

# ==============================================================================
# Test 5: docker build inside container
# ==============================================================================
test_docker_build() {
    section "Test 5: docker build inside container"

    # Create a simple Dockerfile inside the container
    local dockerfile_content='FROM alpine:3.20
RUN echo "build-test-ok"
CMD ["echo", "containai-dind-build-test"]'

    # Create temp directory and Dockerfile
    if ! exec_in_container mkdir -p /tmp/dind-build-test; then
        fail "Failed to create build directory in container"
        return 1
    fi

    if ! printf '%s\n' "$dockerfile_content" | exec_in_container tee /tmp/dind-build-test/Dockerfile >/dev/null; then
        fail "Failed to create Dockerfile in container"
        return 1
    fi

    # Build the image
    info "Building test image inside container..."
    local build_output build_rc
    build_output=$(run_with_timeout "$TEST_TIMEOUT" exec_in_container docker build -t dind-build-test:latest /tmp/dind-build-test 2>&1) && build_rc=0 || build_rc=$?

    # Handle no timeout mechanism
    if [[ $build_rc -eq 125 ]]; then
        build_output=$(exec_in_container docker build -t dind-build-test:latest /tmp/dind-build-test 2>&1) && build_rc=0 || build_rc=$?
    fi

    if [[ $build_rc -eq 124 ]]; then
        fail "docker build timed out after ${TEST_TIMEOUT}s"
        return 1
    fi

    if [[ $build_rc -ne 0 ]]; then
        fail "docker build failed"
        info "  Exit code: $build_rc"
        info "  Output: $(printf '%s' "$build_output" | tail -10)"
        return 1
    fi

    # Run the built image to verify
    local run_output run_rc
    run_output=$(exec_in_container docker run --rm dind-build-test:latest 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -eq 0 ]] && [[ "$run_output" == *"containai-dind-build-test"* ]]; then
        pass "docker build and run succeeded inside system container"
    else
        fail "Built image failed to run correctly"
        info "  Output: $run_output"
        return 1
    fi

    # Cleanup test image
    exec_in_container docker rmi dind-build-test:latest >/dev/null 2>&1 || true
}

# ==============================================================================
# Test 6: Nested container networking (internet connectivity)
# ==============================================================================
test_nested_networking() {
    section "Test 6: Nested container networking"

    # Test internet connectivity from nested container
    # Use BusyBox-compatible wget flags: -T (timeout) not --timeout
    info "Testing internet connectivity from nested container..."

    local network_output network_rc
    # Note: Alpine uses BusyBox wget which requires -T for timeout (not --timeout)
    network_output=$(run_with_timeout "$TEST_TIMEOUT" exec_in_container docker run --rm alpine:3.20 wget -q -O /dev/null -T 10 https://github.com 2>&1) && network_rc=0 || network_rc=$?

    # Handle no timeout mechanism
    if [[ $network_rc -eq 125 ]]; then
        network_output=$(exec_in_container docker run --rm alpine:3.20 wget -q -O /dev/null -T 10 https://github.com 2>&1) && network_rc=0 || network_rc=$?
    fi

    if [[ $network_rc -eq 124 ]]; then
        # Timeout - this is a failure unless explicitly allowed
        if [[ "${CAI_ALLOW_NETWORK_FAILURE:-}" == "1" ]]; then
            warn "Nested container networking test timed out (allowed by CAI_ALLOW_NETWORK_FAILURE=1)"
            return 0
        fi
        fail "Nested container networking test timed out after ${TEST_TIMEOUT}s"
        info "  This may indicate network configuration issues"
        info "  Set CAI_ALLOW_NETWORK_FAILURE=1 to skip this check in restricted environments"
        return 1
    fi

    if [[ $network_rc -eq 0 ]]; then
        pass "Nested container has internet connectivity"
    else
        # Network failure - fail by default per acceptance criteria
        if [[ "${CAI_ALLOW_NETWORK_FAILURE:-}" == "1" ]]; then
            warn "Nested container could not reach internet (allowed by CAI_ALLOW_NETWORK_FAILURE=1)"
            info "  Error output: $network_output"
            return 0
        fi
        fail "Nested container networking failed"
        info "  Exit code: $network_rc"
        info "  Error output: $network_output"
        info "  Set CAI_ALLOW_NETWORK_FAILURE=1 to skip this check in restricted environments"
        return 1
    fi
}

# ==============================================================================
# Test 7: Inner Docker uses sysbox-runc by default (security verification)
# ==============================================================================
test_inner_docker_runtime() {
    section "Test 7: Inner Docker runtime configuration"

    # Verify inner Docker is configured with sysbox-runc as default
    local default_runtime
    default_runtime=$(exec_in_container docker info --format '{{.DefaultRuntime}}' 2>/dev/null) || default_runtime=""

    if [[ "$default_runtime" == "sysbox-runc" ]]; then
        pass "Inner Docker uses sysbox-runc as default runtime"
        info "  This enables secure nested containers"
    else
        warn "Inner Docker default runtime: $default_runtime (expected: sysbox-runc)"
        info "  Nested containers may have different isolation characteristics"
    fi

    # Verify sysbox-runc is available as a runtime option
    local runtimes
    runtimes=$(exec_in_container docker info --format '{{json .Runtimes}}' 2>/dev/null) || runtimes="{}"

    if printf '%s' "$runtimes" | grep -q "sysbox-runc"; then
        pass "sysbox-runc runtime is available in inner Docker"
    else
        warn "sysbox-runc not found in inner Docker runtimes"
        info "  Available runtimes: $runtimes"
    fi
}

# ==============================================================================
# Test 8: Error handling when dockerd not available
# ==============================================================================
test_dockerd_error_handling() {
    section "Test 8: Docker daemon error handling"

    # This test verifies that the docker CLI provides clear errors when
    # the daemon isn't available. We don't actually stop the daemon
    # (that would break our test container), but we verify the error
    # message format by connecting to a non-existent socket.

    local error_output error_rc
    error_output=$(exec_in_container docker -H unix:///nonexistent.sock info 2>&1) && error_rc=0 || error_rc=$?

    if [[ $error_rc -ne 0 ]]; then
        # Verify the error message is clear and actionable
        if printf '%s' "$error_output" | grep -qiE "cannot connect|connection refused|no such file|Is the docker daemon running"; then
            pass "Docker CLI provides clear error when daemon unavailable"
            info "  Error message: $(printf '%s' "$error_output" | head -1)"
        else
            warn "Docker CLI error message may be unclear"
            info "  Error: $error_output"
        fi
    else
        # This shouldn't happen - connecting to nonexistent socket should fail
        warn "Unexpected success connecting to nonexistent socket"
    fi
}

# ==============================================================================
# Test 9: Volume mounts in nested containers
# ==============================================================================
test_nested_volume_mounts() {
    section "Test 9: Volume mounts in nested containers"

    # Create a test file in the system container
    local test_content="containai-volume-test-$$"
    if ! exec_in_container bash -c "echo '$test_content' > /tmp/volume-test-file"; then
        fail "Failed to create test file in system container"
        return 1
    fi

    # Mount and read from nested container
    local volume_output volume_rc
    volume_output=$(exec_in_container docker run --rm -v /tmp/volume-test-file:/mounted-file:ro alpine:3.20 cat /mounted-file 2>&1) && volume_rc=0 || volume_rc=$?

    if [[ $volume_rc -eq 0 ]] && [[ "$volume_output" == *"$test_content"* ]]; then
        pass "Volume mounts work in nested containers"
    else
        fail "Volume mount in nested container failed"
        info "  Expected: $test_content"
        info "  Got: $volume_output"
        return 1
    fi

    # Cleanup
    exec_in_container rm -f /tmp/volume-test-file >/dev/null 2>&1 || true
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    printf '%s\n' "=============================================================================="
    printf '%s\n' "Docker-in-Docker (DinD) Integration Tests for ContainAI"
    printf '%s\n' "=============================================================================="

    # Skip Sysbox DinD verification when already inside a container
    # (these tests verify host-level Sysbox DinD setup, not nested ContainAI functionality)
    if _cai_is_container; then
        printf '%s\n' "[SKIP] Running inside a container - skipping Sysbox DinD verification"
        printf '%s\n' "[SKIP] These tests verify host-level Sysbox DinD; run on host to test installation"
        exit 0
    fi

    # Check prerequisites
    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' "[ERROR] docker is required" >&2
        exit 1
    fi

    # Check if context exists before running tests
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        printf '\n'
        printf '%s\n' "[WARN] Context '$CONTEXT_NAME' does not exist"
        printf '%s\n' "[WARN] Run 'cai setup' first to configure Sysbox"
        printf '%s\n' "[WARN] Running tests anyway to show expected failures..."
        printf '\n'
    fi

    info "Test image: $TEST_IMAGE"
    info "Test container: $TEST_CONTAINER_NAME"

    # Run tests in order (each depends on previous)
    test_system_container_start || { FAILED=1; }

    # Only run remaining tests if container started successfully
    if docker --context "$CONTEXT_NAME" inspect --type container "$TEST_CONTAINER_NAME" >/dev/null 2>&1; then
        test_systemd_pid1 || true
        test_dockerd_ready || { FAILED=1; }

        # Only test DinD features if dockerd is ready
        if exec_in_container docker info >/dev/null 2>&1; then
            test_hello_world || true
            test_docker_build || true
            test_nested_networking || true
            test_inner_docker_runtime || true
            test_dockerd_error_handling || true
            test_nested_volume_mounts || true
        else
            warn "Skipping DinD tests - inner dockerd not ready"
        fi
    else
        warn "Skipping all tests - system container not running"
    fi

    # Summary
    printf '\n'
    printf '%s\n' "=============================================================================="
    if [[ "$FAILED" -eq 0 ]]; then
        printf '%s\n' "All DinD tests passed!"
        printf '%s\n' ""
        printf '%s\n' "Docker-in-Docker is working correctly in Sysbox system containers."
        printf '%s\n' "Agents can build and run containers inside their isolated environment."
        exit 0
    else
        printf '%s\n' "Some DinD tests failed!"
        printf '%s\n' ""
        printf '%s\n' "Troubleshooting:"
        printf '%s\n' "  1. Ensure Sysbox is installed: cai setup"
        printf '%s\n' "  2. Check Sysbox services: systemctl status sysbox-mgr sysbox-fs"
        printf '%s\n' "  3. Verify context: docker --context $CONTEXT_NAME info"
        exit 1
    fi
}

main "$@"
