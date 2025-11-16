#!/usr/bin/env bash
# Run the integration test suite inside an isolated Docker-in-Docker environment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INTEGRATION_SCRIPT="$PROJECT_ROOT/scripts/test/integration-test-impl.sh"

# When running in bash (including WSL), pwd already returns Unix-style paths
# that Docker can mount. No conversion needed.

DIND_IMAGE="${TEST_ISOLATION_IMAGE:-docker:25.0-dind}"
DIND_CONTAINER="${TEST_ISOLATION_CONTAINER:-coding-agents-test-dind-$RANDOM}"
ISOLATION_MODE="${TEST_ISOLATION_MODE:-dind}"
DIND_STARTED=false
TEST_ARGS=()

if [[ -n "${TEST_ISOLATION_DOCKER_RUN_FLAGS:-}" ]]; then
    # shellcheck disable=SC2206
    DIND_RUN_FLAGS=(${TEST_ISOLATION_DOCKER_RUN_FLAGS})
else
    DIND_RUN_FLAGS=(--privileged)
fi

cleanup() {
    local exit_code=$?
    if [[ "$DIND_STARTED" == "true" ]]; then
        if [[ "${TEST_PRESERVE_RESOURCES:-false}" == "true" ]]; then
            echo ""
            echo "Preserving isolated Docker daemon ($DIND_CONTAINER) for debugging (TEST_PRESERVE_RESOURCES=true)"
        else
            echo ""
            echo "Cleaning up isolated Docker daemon..."
            docker rm -f "$DIND_CONTAINER" >/dev/null 2>&1 || true
        fi
    fi
    exit $exit_code
}

print_dind_logs() {
    if [[ "$DIND_STARTED" != "true" ]]; then
        return
    fi
    echo ""
    echo "--- Docker-in-Docker logs (last 80 lines) ---"
    if ! docker logs --tail 80 "$DIND_CONTAINER" 2>&1; then
        echo "Unable to retrieve logs from $DIND_CONTAINER"
    fi
    echo "--- End logs ---"
}

usage() {
    cat <<EOF
Run the Coding Agents integration test suite.

This script runs all integration tests inside an isolated Docker-in-Docker
environment to ensure reproducibility and prevent host daemon contamination.

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --mode launchers    Test with existing/mock images (default, ~5-10 minutes)
    --mode full         Build all images from Dockerfiles (~15-25 minutes)
    --preserve          Keep test resources after completion for debugging
    --isolation dind    Run tests inside Docker-in-Docker (default)
    --isolation host    Run tests directly on host Docker daemon (optional, skips DinD risk)
    --help              Show this help message

ENVIRONMENT VARIABLES:
    TEST_ISOLATION_IMAGE            Override Docker-in-Docker image (default: docker:25.0-dind)
    TEST_ISOLATION_CONTAINER        Override container name
    TEST_ISOLATION_STARTUP_TIMEOUT  Daemon startup wait time in seconds (default: 180)
    TEST_PRESERVE_RESOURCES         Same as --preserve flag
    TEST_ISOLATION_MODE             Default isolation mode (dind | host)
    TEST_ISOLATION_DOCKER_RUN_FLAGS Extra docker run flags when using DinD

EXAMPLES:
  # Quick validation (recommended for development)
  $(basename "$0") --mode launchers

  # Full build validation (run before PR)
  $(basename "$0") --mode full

  # Debug failed tests
  TEST_PRESERVE_RESOURCES=true $(basename "$0") --mode launchers

    # Force host mode when the default is DinD
    TEST_ISOLATION_MODE=host $(basename "$0") --mode launchers
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --mode)
            if [[ $# -lt 2 ]]; then
                echo "Error: --mode requires an argument" >&2
                exit 1
            fi
            TEST_ARGS+=("$1" "$2")
            shift 2
            ;;
        --preserve)
            TEST_ARGS+=("$1")
            shift
            ;;
        --isolation)
            if [[ $# -lt 2 ]]; then
                echo "Error: --isolation requires an argument" >&2
                exit 1
            fi
            ISOLATION_MODE="$2"
            shift 2
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

case "$ISOLATION_MODE" in
    host|dind) ;;
    *)
        echo "Error: Invalid isolation mode '$ISOLATION_MODE' (expected 'host' or 'dind')" >&2
        exit 1
        ;;
esac

trap cleanup EXIT INT TERM

# Validate Docker is available
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker command not found"
    echo "Please ensure Docker is installed and running"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker daemon is not running"
    echo "Please start Docker and try again"
    exit 1
fi

start_dind() {
    echo "Starting isolated Docker daemon ($DIND_IMAGE)..."
    echo "  Mounting: $PROJECT_ROOT -> /workspace (read-only)"
    if [[ ${#DIND_RUN_FLAGS[@]} -gt 0 ]]; then
        echo "  docker run flags: ${DIND_RUN_FLAGS[*]}"
    else
        echo "  docker run flags: <none>"
    fi
    if ! docker run -d \
        ${DIND_RUN_FLAGS[@]} \
        --name "$DIND_CONTAINER" \
        -v "$PROJECT_ROOT":/workspace:ro \
        -e DOCKER_TLS_CERTDIR= \
        "$DIND_IMAGE" >/dev/null 2>&1; then
        echo "Error: Failed to start Docker-in-Docker container"
        echo "This may indicate missing --privileged support or image pull failure"
        print_dind_logs
        exit 1
    fi
    DIND_STARTED=true
}

wait_for_daemon() {
    echo "  Waiting for Docker daemon to initialize (this can take 20-30 seconds)..."
    local retries=0
    local max_retries=${TEST_ISOLATION_STARTUP_TIMEOUT:-180}
    local last_progress=0
    local last_error=""
    local docker_exec_output=""
    while true; do
        local state
        state=$(docker inspect -f '{{.State.Status}}' "$DIND_CONTAINER" 2>/dev/null || echo "missing")
        if [[ "$state" != "running" ]]; then
            echo "  ✗ Docker-in-Docker container stopped unexpectedly (state: $state)"
            print_dind_logs
            echo "  Hint: set TEST_PRESERVE_RESOURCES=true to inspect the container manually"
            exit 1
        fi

        if docker_exec_output=$(docker exec "$DIND_CONTAINER" docker info 2>&1); then
            echo "  ✓ Docker daemon ready after ${retries}s"
            break
        fi
        last_error=$docker_exec_output
        retries=$((retries + 1))
        
        # Progress indicator every 10 seconds
        if [[ $((retries % 10)) -eq 0 && $retries -ne $last_progress ]]; then
            echo "    ... still waiting (${retries}s elapsed)"
            last_progress=$retries
        fi
        
        if [[ $retries -ge $max_retries ]]; then
            echo "  ✗ Timed out waiting for Docker daemon"
            if [[ -n "$last_error" ]]; then
                echo "  Last docker info error:"
                echo "$last_error"
            fi
            print_dind_logs
            echo "Tip: Set TEST_ISOLATION_STARTUP_TIMEOUT to increase wait time"
            exit 1
        fi
        sleep 1
    done
}

bootstrap_tools() {
    echo "  Installing base tooling inside isolation..."
    if ! docker exec "$DIND_CONTAINER" sh -c "apk add --no-cache bash git curl jq python3 py3-pip coreutils >/dev/null 2>&1"; then
        echo "  ✗ Failed to install required tools"
        echo "  This usually indicates a network connectivity issue"
        exit 1
    fi
    echo "  ✓ Tooling installed"
}

run_integration_tests() {
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Running integration suite inside isolation"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    local command="cd /workspace && ./scripts/test/integration-test-impl.sh"
    for arg in "${TEST_ARGS[@]}"; do
        command+=" $(printf '%q' "$arg")"
    done
    
    local test_exit_code=0
    docker exec -e TEST_PRESERVE_RESOURCES="${TEST_PRESERVE_RESOURCES:-false}" "$DIND_CONTAINER" bash -lc "$command" || test_exit_code=$?
    
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    if [[ $test_exit_code -eq 0 ]]; then
        echo "Integration tests completed successfully"
    else
        echo "Integration tests failed with exit code: $test_exit_code"
        print_dind_logs
        echo "Tip: Re-run with TEST_PRESERVE_RESOURCES=true to debug"
    fi
    echo "═══════════════════════════════════════════════════════════"
    
    return $test_exit_code
}

run_on_host() {
    echo "Running integration suite directly on host Docker daemon"
    echo ""
    bash "$INTEGRATION_SCRIPT" "${TEST_ARGS[@]}"
}

if [[ "$ISOLATION_MODE" = "host" ]]; then
    run_on_host
else
    start_dind
    wait_for_daemon
    bootstrap_tools
    run_integration_tests
fi
