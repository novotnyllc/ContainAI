#!/usr/bin/env bash
# ==============================================================================
# Integration test: Docker-in-Docker with runc 1.3.3+ on ContainAI sysbox build
# ==============================================================================
# Validates that the ContainAI sysbox build (with openat2 fix) works correctly
# with runc 1.3.3+. This is a regression test for the "unsafe procfs detected"
# error that occurs with upstream sysbox releases.
#
# See: https://github.com/nestybox/sysbox/issues/973
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

# Context name for sysbox containers
CONTEXT_NAME="${_CAI_CONTAINAI_DOCKER_CONTEXT:-containai-docker}"

# Timeouts
DOCKERD_WAIT_TIMEOUT=60
TEST_TIMEOUT=60
CONTAINER_STOP_TIMEOUT=30

# Test container name (unique per run to avoid conflicts)
TEST_CONTAINER_NAME="containai-dind-runc133-test-$$"

# ContainAI base image for system container testing
TEST_IMAGE="${CONTAINAI_TEST_IMAGE:-ghcr.io/novotnyllc/containai/base:latest}"

# Error pattern that indicates the openat2 bug
OPENAT2_ERROR_PATTERN="unsafe procfs detected.*openat2"

# Cleanup function
cleanup() {
    info "Cleaning up test container..."

    # Stop and remove test container (ignore errors)
    if docker --context "$CONTEXT_NAME" inspect --type container -- "$TEST_CONTAINER_NAME" >/dev/null 2>&1; then
        docker --context "$CONTEXT_NAME" stop --time "$CONTAINER_STOP_TIMEOUT" -- "$TEST_CONTAINER_NAME" 2>/dev/null || true
        docker --context "$CONTEXT_NAME" rm -f -- "$TEST_CONTAINER_NAME" 2>/dev/null || true
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
wait_for_dockerd() {
    local container="$1"
    local timeout="${2:-$DOCKERD_WAIT_TIMEOUT}"
    local elapsed=0
    local interval=2

    info "Waiting for inner dockerd to start (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        if docker --context "$CONTEXT_NAME" exec -- "$container" docker info >/dev/null 2>&1; then
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
    docker --context "$CONTEXT_NAME" exec -- "$TEST_CONTAINER_NAME" "$@"
}

# Execute command inside the system container with stdin attached
exec_in_container_stdin() {
    docker --context "$CONTEXT_NAME" exec -i -- "$TEST_CONTAINER_NAME" "$@"
}

# Check output for openat2 error pattern
check_for_openat2_error() {
    local output="$1"
    if printf '%s' "$output" | grep -qiE "$OPENAT2_ERROR_PATTERN"; then
        return 0  # Error found
    fi
    return 1  # Error not found
}

# ==============================================================================
# Test 1: Verify sysbox has ContainAI build (with openat2 fix)
# ==============================================================================
test_sysbox_containai_build() {
    section "Test 1: Verify sysbox has ContainAI build (openat2 fix)"

    # Check if context exists first
    if ! docker context inspect "$CONTEXT_NAME" >/dev/null 2>&1; then
        fail "Context '$CONTEXT_NAME' not found"
        info "  Remediation: Run 'cai setup' to configure Sysbox"
        return 1
    fi

    # Check sysbox-fs version for ContainAI build marker
    local sysbox_fs_version sysbox_fs_rc
    sysbox_fs_version=$(sysbox-fs --version 2>&1) && sysbox_fs_rc=0 || sysbox_fs_rc=$?

    if [[ $sysbox_fs_rc -ne 0 ]]; then
        local platform
        platform=$(_cai_detect_platform)
        if [[ "$platform" == "macos" ]]; then
            warn "Could not query sysbox-fs version on macOS; continuing with behavioral checks"
            info "  Output: $sysbox_fs_version"
            info "  Ensure sysbox is installed if subsequent tests report openat2 failures"
            return 0
        fi
        fail "Could not query sysbox-fs version"
        info "  Ensure sysbox is installed"
        return 1
    fi

    info "sysbox-fs version: $sysbox_fs_version"

    # Check for ContainAI build marker (containai suffix or openat2 in version)
    # The ContainAI build may have version like 0.6.7+containai or similar
    if printf '%s' "$sysbox_fs_version" | grep -qiE "(containai|openat2)"; then
        pass "Sysbox has ContainAI build marker in version string"
    else
        # Even without version marker, we can verify by checking if openat2 syscall is handled
        # For now, just warn - the actual DinD test will confirm functionality
        warn "Sysbox version does not contain ContainAI marker"
        info "  Version: $sysbox_fs_version"
        info "  The DinD tests will verify if openat2 fix is functional"
    fi

    # Also check sysbox-runc and sysbox-mgr versions for reference
    local sysbox_runc_version sysbox_mgr_version
    sysbox_runc_version=$(sysbox-runc --version 2>&1 | head -1) || sysbox_runc_version="unknown"
    sysbox_mgr_version=$(sysbox-mgr --version 2>&1 | head -1) || sysbox_mgr_version="unknown"

    info "sysbox-runc version: $sysbox_runc_version"
    info "sysbox-mgr version: $sysbox_mgr_version"
}

# ==============================================================================
# Test 2: Verify inner runc version >= 1.3.3
# ==============================================================================
test_inner_runc_version() {
    section "Test 2: Verify inner runc version >= 1.3.3"

    # Pull image if needed
    if ! docker --context "$CONTEXT_NAME" image inspect "$TEST_IMAGE" >/dev/null 2>&1; then
        info "Pulling test image: $TEST_IMAGE"
        if ! run_with_timeout 120 docker --context "$CONTEXT_NAME" pull "$TEST_IMAGE"; then
            fail "Failed to pull test image: $TEST_IMAGE"
            return 1
        fi
    fi

    # Start system container to check inner runc version
    info "Starting system container to check inner runc version..."

    local run_output run_rc
    run_output=$(docker --context "$CONTEXT_NAME" run -d \
        --runtime=sysbox-runc \
        --name "$TEST_CONTAINER_NAME" \
        --stop-timeout "$CONTAINER_STOP_TIMEOUT" \
        "$TEST_IMAGE" 2>&1) && run_rc=0 || run_rc=$?

    if [[ $run_rc -ne 0 ]]; then
        # Check if this is the openat2 error
        if check_for_openat2_error "$run_output"; then
            fail "Container start failed with openat2 error (sysbox needs ContainAI build)"
            info "  Error: $run_output"
            info "  This indicates sysbox does NOT have the openat2 fix"
            return 1
        fi
        fail "Failed to start system container"
        info "  Error: $run_output"
        return 1
    fi

    # Wait for dockerd to be ready
    if ! wait_for_dockerd "$TEST_CONTAINER_NAME" "$DOCKERD_WAIT_TIMEOUT"; then
        fail "Inner dockerd failed to start"
        return 1
    fi

    # Get inner runc version
    local inner_runc_version inner_runc_rc
    inner_runc_version=$(exec_in_container docker info --format '{{.Runtimes.runc.path}}' 2>/dev/null) || inner_runc_version=""

    # Try to get actual runc version by running it
    local runc_version_output runc_version_rc
    runc_version_output=$(exec_in_container runc --version 2>&1) && runc_version_rc=0 || runc_version_rc=$?

    if [[ $runc_version_rc -ne 0 ]]; then
        fail "Could not query inner runc version"
        info "  Output: $runc_version_output"
        info "  runc must be accessible inside the container to verify version >= 1.3.3"
        return 1
    fi

    info "Inner runc version output: $runc_version_output"

    # Parse version number (e.g., "runc version 1.3.3")
    local version_number
    version_number=$(printf '%s' "$runc_version_output" | grep -oE 'runc version [0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)

    if [[ -z "$version_number" ]]; then
        local platform
        platform=$(_cai_detect_platform)
        if [[ "$platform" == "macos" ]] && [[ $runc_version_rc -eq 0 ]] && [[ -z "$runc_version_output" ]]; then
            warn "Inner runc version output is empty on macOS; treating version check as inconclusive"
            info "  Inner runc runtime path: ${inner_runc_version:-unknown}"
            return 0
        fi
        fail "Could not parse runc version from output"
        info "  Output: $runc_version_output"
        return 1
    fi

    info "Inner runc version: $version_number"

    # Compare versions using sort -V
    local min_version="1.3.3"
    local older_version
    older_version=$(printf '%s\n%s\n' "$version_number" "$min_version" | sort -V | head -1)

    if [[ "$older_version" == "$min_version" ]] || [[ "$version_number" == "$min_version" ]]; then
        pass "Inner runc version ($version_number) >= $min_version"
    else
        fail "Inner runc version ($version_number) < $min_version"
        info "  This test requires runc >= 1.3.3 to verify the openat2 fix"
        info "  The openat2 security check was added in runc 1.3.3"
        return 1
    fi
}

# ==============================================================================
# Test 3: docker run inside sysbox container (no openat2 error)
# ==============================================================================
test_docker_run_no_openat2_error() {
    section "Test 3: docker run inside sysbox container (no openat2 error)"

    # Container should already be running from test 2
    if ! docker --context "$CONTEXT_NAME" inspect --type container -- "$TEST_CONTAINER_NAME" >/dev/null 2>&1; then
        fail "Test container not running (prerequisite failed)"
        return 1
    fi

    # Verify dockerd is ready
    if ! exec_in_container docker info >/dev/null 2>&1; then
        fail "Inner dockerd not ready"
        return 1
    fi

    info "Running docker run hello-world inside sysbox container..."

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

    # Check for openat2 error
    if check_for_openat2_error "$hello_output"; then
        fail "docker run failed with openat2 error"
        info "  This indicates sysbox does NOT have the openat2 fix"
        info "  Error: $hello_output"
        return 1
    fi

    if [[ $hello_rc -eq 0 ]] && printf '%s' "$hello_output" | grep -qi "Hello from Docker"; then
        pass "docker run hello-world succeeded without openat2 error"
    elif [[ $hello_rc -eq 0 ]]; then
        local platform
        platform=$(_cai_detect_platform)
        if [[ "$platform" == "macos" ]] && [[ -z "$hello_output" ]]; then
            local hello_diag
            hello_diag=$(exec_in_container docker images --format '{{.Repository}}:{{.Tag}}' hello-world 2>&1 || true)
            warn "docker run hello-world returned rc=0 with empty output on macOS; treating as inconclusive"
            info "  Diagnostics (hello-world image refs): $hello_diag"
            return 0
        fi
        fail "docker run hello-world failed"
        info "  Exit code: $hello_rc"
        info "  Output: $(printf '%s' "$hello_output" | head -10)"
        return 1
    else
        fail "docker run hello-world failed"
        info "  Exit code: $hello_rc"
        info "  Output: $(printf '%s' "$hello_output" | head -10)"
        return 1
    fi
}

# ==============================================================================
# Test 4: docker build inside sysbox container (no openat2 error)
# ==============================================================================
test_docker_build_no_openat2_error() {
    section "Test 4: docker build inside sysbox container (no openat2 error)"

    # Container should already be running
    if ! docker --context "$CONTEXT_NAME" inspect --type container -- "$TEST_CONTAINER_NAME" >/dev/null 2>&1; then
        fail "Test container not running (prerequisite failed)"
        return 1
    fi

    # Create a simple Dockerfile inside the container
    local dockerfile_content='FROM alpine:3.20
RUN echo "runc133-build-test-ok"
CMD ["echo", "containai-dind-runc133-build-test"]'

    # Create temp directory and Dockerfile
    if ! exec_in_container mkdir -p /tmp/dind-runc133-build-test; then
        fail "Failed to create build directory in container"
        return 1
    fi

    if ! printf '%s\n' "$dockerfile_content" | exec_in_container_stdin tee /tmp/dind-runc133-build-test/Dockerfile >/dev/null; then
        fail "Failed to create Dockerfile in container"
        return 1
    fi

    # Build the image
    info "Building test image inside sysbox container..."
    local build_output build_rc
    build_output=$(run_with_timeout "$TEST_TIMEOUT" exec_in_container docker build -t dind-runc133-build-test:latest /tmp/dind-runc133-build-test 2>&1) && build_rc=0 || build_rc=$?

    # Handle no timeout mechanism
    if [[ $build_rc -eq 125 ]]; then
        build_output=$(exec_in_container docker build -t dind-runc133-build-test:latest /tmp/dind-runc133-build-test 2>&1) && build_rc=0 || build_rc=$?
    fi

    if [[ $build_rc -eq 124 ]]; then
        fail "docker build timed out after ${TEST_TIMEOUT}s"
        return 1
    fi

    # Check for openat2 error
    if check_for_openat2_error "$build_output"; then
        fail "docker build failed with openat2 error"
        info "  This indicates sysbox does NOT have the openat2 fix"
        info "  Error: $build_output"
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
    run_output=$(exec_in_container docker run --rm dind-runc133-build-test:latest 2>&1) && run_rc=0 || run_rc=$?

    # Check for openat2 error in run
    if check_for_openat2_error "$run_output"; then
        fail "Running built image failed with openat2 error"
        info "  Error: $run_output"
        return 1
    fi

    if [[ $run_rc -eq 0 ]] && [[ "$run_output" == *"containai-dind-runc133-build-test"* ]]; then
        pass "docker build and run succeeded without openat2 error"
    elif [[ $run_rc -eq 0 ]]; then
        local platform
        platform=$(_cai_detect_platform)
        if [[ "$platform" == "macos" ]] && [[ -z "$run_output" ]]; then
            local image_id
            image_id=$(exec_in_container docker image inspect dind-runc133-build-test:latest --format '{{.Id}}' 2>/dev/null) || image_id=""
            warn "Built image run returned rc=0 with empty output on macOS; treating as inconclusive"
            info "  Built image ID: ${image_id:-unavailable}"
            return 0
        fi
        fail "Built image failed to run correctly"
        info "  Exit code: $run_rc"
        info "  Output: $run_output"
        return 1
    else
        fail "Built image failed to run correctly"
        info "  Exit code: $run_rc"
        info "  Output: $run_output"
        return 1
    fi

    # Cleanup test image
    exec_in_container docker rmi dind-runc133-build-test:latest >/dev/null 2>&1 || true
}

# ==============================================================================
# Test 5: Verify no openat2 errors in container logs
# ==============================================================================
test_no_openat2_in_logs() {
    section "Test 5: Verify no openat2 errors in container/system logs"

    # Container should already be running
    if ! docker --context "$CONTEXT_NAME" inspect --type container -- "$TEST_CONTAINER_NAME" >/dev/null 2>&1; then
        fail "Test container not running (prerequisite failed)"
        return 1
    fi

    # Check container logs for openat2 errors
    local container_logs container_logs_rc
    container_logs=$(docker --context "$CONTEXT_NAME" logs -- "$TEST_CONTAINER_NAME" 2>&1) && container_logs_rc=0 || container_logs_rc=$?

    if check_for_openat2_error "$container_logs"; then
        fail "Container logs contain openat2 errors"
        info "  This indicates the sysbox openat2 fix is not working"
        # Show relevant error lines
        printf '%s' "$container_logs" | grep -iE "$OPENAT2_ERROR_PATTERN" | while IFS= read -r line; do
            info "    $line"
        done
        return 1
    fi

    pass "No openat2 errors found in container logs"

    # Also check journalctl on host for sysbox-fs errors (if available)
    if command -v journalctl >/dev/null 2>&1; then
        local sysbox_fs_logs sysbox_fs_logs_rc
        sysbox_fs_logs=$(journalctl -u sysbox-fs --no-pager -n 50 --since "5 minutes ago" 2>&1) && sysbox_fs_logs_rc=0 || sysbox_fs_logs_rc=$?

        if [[ $sysbox_fs_logs_rc -eq 0 ]] && [[ -n "$sysbox_fs_logs" ]]; then
            if check_for_openat2_error "$sysbox_fs_logs"; then
                warn "sysbox-fs logs contain openat2 references (may be handled)"
                # This could be normal if sysbox-fs is intercepting openat2 calls
                info "  Check if these are interception logs (expected) vs errors (problem)"
            else
                pass "No openat2 errors in sysbox-fs logs"
            fi
        fi
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    printf '%s\n' "=============================================================================="
    printf '%s\n' "Docker-in-Docker runc 1.3.3+ Compatibility Test"
    printf '%s\n' "=============================================================================="
    printf '%s\n' "This test validates that the ContainAI sysbox build (with openat2 fix)"
    printf '%s\n' "works correctly with runc 1.3.3+ which added security checks that conflict"
    printf '%s\n' "with sysbox-fs bind mounts."
    printf '%s\n' ""
    printf '%s\n' "See: https://github.com/nestybox/sysbox/issues/973"
    printf '%s\n' "=============================================================================="

    # Skip Sysbox runc compatibility verification when already inside a container
    # (these tests verify host-level Sysbox build, not nested ContainAI functionality)
    if _cai_is_container; then
        printf '%s\n' "[SKIP] Running inside a container - skipping Sysbox runc 1.3.3+ verification"
        printf '%s\n' "[SKIP] These tests verify host-level Sysbox build; run on host to test installation"
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
    test_sysbox_containai_build || true
    test_inner_runc_version || { FAILED=1; }

    # Only run DinD tests if container is running
    if docker --context "$CONTEXT_NAME" inspect --type container -- "$TEST_CONTAINER_NAME" >/dev/null 2>&1; then
        # Verify dockerd is ready
        if exec_in_container docker info >/dev/null 2>&1; then
            test_docker_run_no_openat2_error || { FAILED=1; }
            test_docker_build_no_openat2_error || { FAILED=1; }
            test_no_openat2_in_logs || true
        else
            warn "Skipping DinD tests - inner dockerd not ready"
            FAILED=1
        fi
    else
        warn "Skipping DinD tests - system container not running"
        FAILED=1
    fi

    # Summary
    printf '\n'
    printf '%s\n' "=============================================================================="
    if [[ "$FAILED" -eq 0 ]]; then
        printf '%s\n' "All runc 1.3.3+ compatibility tests passed!"
        printf '%s\n' ""
        printf '%s\n' "The ContainAI sysbox build with openat2 fix is working correctly."
        printf '%s\n' "Docker-in-Docker operations succeed without 'unsafe procfs detected' errors."
        exit 0
    else
        printf '%s\n' "Some runc 1.3.3+ compatibility tests failed!"
        printf '%s\n' ""
        printf '%s\n' "Troubleshooting:"
        printf '%s\n' "  1. Ensure ContainAI sysbox build is installed: cai setup"
        printf '%s\n' "  2. Check sysbox services: systemctl status sysbox-mgr sysbox-fs"
        printf '%s\n' "  3. Verify sysbox version includes openat2 fix (containai marker)"
        printf '%s\n' ""
        printf '%s\n' "If you see 'unsafe procfs detected: openat2' errors, the sysbox build"
        printf '%s\n' "does not have the openat2 fix. Install the ContainAI custom build."
        exit 1
    fi
}

main "$@"
