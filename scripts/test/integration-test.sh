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
DIND_STARTED=false
ARGS=("$@")

cleanup() {
    local exit_code=$?
    if [[ "$DIND_STARTED" == "true" ]]; then
        echo ""
        echo "Cleaning up isolated Docker daemon..."
        docker rm -f "$DIND_CONTAINER" >/dev/null 2>&1 || true
    fi
    exit $exit_code
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
  --help              Show this help message

ENVIRONMENT VARIABLES:
  TEST_ISOLATION_IMAGE            Override Docker-in-Docker image (default: docker:25.0-dind)
  TEST_ISOLATION_CONTAINER        Override container name
  TEST_ISOLATION_STARTUP_TIMEOUT  Daemon startup wait time in seconds (default: 180)
  TEST_PRESERVE_RESOURCES         Same as --preserve flag

EXAMPLES:
  # Quick validation (recommended for development)
  $(basename "$0") --mode launchers

  # Full build validation (run before PR)
  $(basename "$0") --mode full

  # Debug failed tests
  TEST_PRESERVE_RESOURCES=true $(basename "$0") --mode launchers
EOF
}

if [[ ${#ARGS[@]} -gt 0 && "${ARGS[0]}" =~ ^(--help|-h)$ ]]; then
    usage
    exit 0
fi

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
    if ! docker run -d \
        --privileged \
        --name "$DIND_CONTAINER" \
        -v "$PROJECT_ROOT":/workspace:ro \
        -e DOCKER_TLS_CERTDIR= \
        "$DIND_IMAGE" >/dev/null 2>&1; then
        echo "Error: Failed to start Docker-in-Docker container"
        echo "This may indicate missing --privileged support or image pull failure"
        exit 1
    fi
    DIND_STARTED=true
}

wait_for_daemon() {
    echo "  Waiting for Docker daemon to initialize (this can take 20-30 seconds)..."
    local retries=0
    local max_retries=${TEST_ISOLATION_STARTUP_TIMEOUT:-180}
    local last_progress=0
    while true; do
        if docker exec "$DIND_CONTAINER" docker info >/dev/null 2>&1; then
            echo "  ✓ Docker daemon ready after ${retries}s"
            break
        fi
        retries=$((retries + 1))
        
        # Progress indicator every 10 seconds
        if [[ $((retries % 10)) -eq 0 && $retries -ne $last_progress ]]; then
            echo "    ... still waiting (${retries}s elapsed)"
            last_progress=$retries
        fi
        
        if [[ $retries -ge $max_retries ]]; then
            echo "  ✗ Timed out waiting for Docker daemon"
            echo ""
            echo "--- Docker-in-Docker logs ---"
            docker logs "$DIND_CONTAINER" 2>&1 | tail -30
            echo ""
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
    for arg in "${ARGS[@]}"; do
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
        echo "Tip: Re-run with TEST_PRESERVE_RESOURCES=true to debug"
    fi
    echo "═══════════════════════════════════════════════════════════"
    
    return $test_exit_code
}

start_dind
wait_for_daemon
bootstrap_tools
run_integration_tests
