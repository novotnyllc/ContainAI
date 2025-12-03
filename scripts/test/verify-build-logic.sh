#!/bin/bash
set -euo pipefail

# Mock variables needed by test_audit_logging
PROJECT_ROOT="$(pwd)"
TEST_CONTAINER_PREFIX="test-audit"
TEST_COPILOT_IMAGE="alpine:latest" # Use alpine for speed, we just need to run cat
TEST_LABEL_TEST="test"
TEST_LABEL_SESSION="session"

# Source the function (we'll just copy the relevant part or source the file if we can mock the rest)
# Since sourcing executes code, I'll just copy the function logic I want to test here to verify the build steps.

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }
test_section() { echo "--- $1 ---"; }

test_audit_logging() {
    test_section "Testing audit logging (Host <-> Shim)"

    local config="${BUILD_CONFIGURATION:-Release}"
    
    echo "Building artifacts for configuration: $config"
    
    # Build Host
    pushd "$PROJECT_ROOT" >/dev/null
    if ! dotnet publish src/ContainAI.Host/ContainAI.Host.csproj -c "$config" >/dev/null; then
        fail "Failed to build ContainAI.Host"
        popd >/dev/null
        return
    fi
    popd >/dev/null

    # Build Shim
    pushd "$PROJECT_ROOT/src/audit-shim" >/dev/null
    local cargo_flag=""
    if [[ "$config" == "Release" ]]; then
        cargo_flag="--release"
    fi
    
    if ! cargo build $cargo_flag >/dev/null; then
        fail "Failed to build audit-shim"
        popd >/dev/null
        return
    fi
    popd >/dev/null

    # Determine paths
    local config_lower
    config_lower=$(echo "$config" | tr '[:upper:]' '[:lower:]')
    
    local host_bin="$PROJECT_ROOT/artifacts/publish/ContainAI.Host/$config_lower/containai"
    
    # Cargo output
    local target_dir="$PROJECT_ROOT/src/target"
    local shim_lib="$target_dir/$config_lower/libaudit_shim.so"

    if [ ! -f "$host_bin" ]; then
        fail "Host binary not found at $host_bin"
        return
    fi

    if [ ! -f "$shim_lib" ]; then
        fail "Shim library not found at $shim_lib"
        return
    fi

    echo "Build verification successful."
    echo "Host: $host_bin"
    echo "Shim: $shim_lib"
}

test_audit_logging
