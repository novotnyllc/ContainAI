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
DIND_CLIENT_IMAGE_DEFAULT="${DIND_IMAGE/-dind/-cli}"
if [[ "$DIND_CLIENT_IMAGE_DEFAULT" == "$DIND_IMAGE" ]]; then
    DIND_CLIENT_IMAGE_DEFAULT="docker:cli"
fi
DIND_CLIENT_IMAGE="${TEST_ISOLATION_CLIENT_IMAGE:-$DIND_CLIENT_IMAGE_DEFAULT}"
DIND_RUN_DIR=""
ISOLATION_MODE="${TEST_ISOLATION_MODE:-dind}"
DIND_STARTED=false
TEST_ARGS=()
WITH_HOST_SECRETS=false
HOST_SECRETS_FILE=""
DIND_SECRETS_PATH="/run/coding-agents/mcp-secrets.env"
DEFAULT_TRIVY_VERSION="${TEST_ISOLATION_TRIVY_VERSION:-0.50.2}"

if [[ -n "${TEST_ISOLATION_DOCKER_RUN_FLAGS:-}" ]]; then
    # shellcheck disable=SC2206
    DIND_RUN_FLAGS=(${TEST_ISOLATION_DOCKER_RUN_FLAGS})
else
    DIND_RUN_FLAGS=(--privileged)
fi

cleanup() {
    local exit_code=$?
    scrub_dind_host_secrets
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

    if [[ "${TEST_PRESERVE_RESOURCES:-false}" == "true" ]]; then
        if [[ -n "$DIND_RUN_DIR" ]]; then
            echo "Shared /run directory preserved at: $DIND_RUN_DIR"
        fi
    else
        purge_dind_run_dir "$DIND_RUN_DIR"
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

scrub_dind_host_secrets() {
    if [[ "$WITH_HOST_SECRETS" != "true" || "$ISOLATION_MODE" != "dind" || "$DIND_STARTED" != "true" ]]; then
        return
    fi
    docker exec "$DIND_CONTAINER" sh -c "rm -f '$DIND_SECRETS_PATH'" >/dev/null 2>&1 || true
}

stage_host_secrets_inside_dind() {
    if [[ "$WITH_HOST_SECRETS" != "true" || "$ISOLATION_MODE" != "dind" ]]; then
        return
    fi

    echo "  Copying host secrets into isolation..."
    local dest_dir
    dest_dir=$(dirname "$DIND_SECRETS_PATH")
    if ! docker exec "$DIND_CONTAINER" sh -c "mkdir -p '$dest_dir' && chmod 700 '$dest_dir'" >/dev/null 2>&1; then
        echo "  ✗ Failed to prepare secrets directory inside isolation"
        exit 1
    fi

    if ! docker cp "$HOST_SECRETS_FILE" "$DIND_CONTAINER:$DIND_SECRETS_PATH" >/dev/null 2>&1; then
        echo "  ✗ Failed to copy host secrets into isolation"
        exit 1
    fi

    if ! docker exec "$DIND_CONTAINER" sh -c "chmod 600 '$DIND_SECRETS_PATH'" >/dev/null 2>&1; then
        echo "  ⚠️  Unable to tighten permissions on secrets file inside isolation" >&2
    fi
    echo "  ✓ Host secrets staged inside isolation"
}

initialize_dind_run_dir() {
    if [[ -n "$DIND_RUN_DIR" && -d "$DIND_RUN_DIR" ]]; then
        return
    fi
    if ! DIND_RUN_DIR=$(mktemp -d -t coding-agents-dind-run-XXXXXX); then
        echo "Error: Unable to create shared /run directory for DinD"
        exit 1
    fi
    chmod 1777 "$DIND_RUN_DIR"
}

purge_dind_run_dir() {
    local dir="$1"
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        return
    fi
    if ! docker run --rm -v "$dir":/run alpine:3.19 sh -c 'rm -rf /run/*' >/dev/null 2>&1; then
        echo "Warning: Unable to scrub shared /run directory automatically ($dir)"
    fi
    rm -rf "$dir" >/dev/null 2>&1 || true
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
    --with-host-secrets Enable host-secrets prompt tests (copies secrets into isolation when needed)
    --help              Show this help message

ENVIRONMENT VARIABLES:
    TEST_ISOLATION_IMAGE            Override Docker-in-Docker image (default: docker:25.0-dind)
    TEST_ISOLATION_CONTAINER        Override container name
    TEST_ISOLATION_CLIENT_IMAGE     Override helper CLI image used to probe DinD readiness
    TEST_ISOLATION_STARTUP_TIMEOUT  Daemon startup wait time in seconds (default: 180)
    TEST_PRESERVE_RESOURCES         Same as --preserve flag
    TEST_ISOLATION_MODE             Default isolation mode (dind | host)
    TEST_ISOLATION_DOCKER_RUN_FLAGS Extra docker run flags when using DinD
    TEST_ISOLATION_TRIVY_VERSION    Override Trivy version fetched inside DinD (default: 0.50.2)

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

resolve_host_secrets_file() {
    local -a candidates=()
    local -A seen=()

    if [[ -n "${CODING_AGENTS_MCP_SECRETS_FILE:-}" ]]; then
        candidates+=("${CODING_AGENTS_MCP_SECRETS_FILE}")
    fi
    if [[ -n "${MCP_SECRETS_FILE:-}" ]]; then
        candidates+=("${MCP_SECRETS_FILE}")
    fi
    candidates+=("${HOME}/.config/coding-agents/mcp-secrets.env" "${HOME}/.mcp-secrets.env")

    local candidate resolved
    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" ]] || continue
        resolved=$(realpath "$candidate" 2>/dev/null || echo "$candidate")
        if [[ -n "${seen[$resolved]:-}" ]]; then
            continue
        fi
        seen[$resolved]=1
        if [[ -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
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
        --with-host-secrets)
            WITH_HOST_SECRETS=true
            TEST_ARGS+=("$1")
            shift
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

if [[ "$WITH_HOST_SECRETS" == "true" ]]; then
    if ! HOST_SECRETS_FILE=$(resolve_host_secrets_file); then
        cat >&2 <<EOF
Error: Unable to locate host secrets file.
Set CODING_AGENTS_MCP_SECRETS_FILE, MCP_SECRETS_FILE, or populate ~/.config/coding-agents/mcp-secrets.env
EOF
        exit 1
    fi
    export TEST_WITH_HOST_SECRETS="true"
    export TEST_HOST_SECRETS_FILE="$HOST_SECRETS_FILE"
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
    if [[ ${#DIND_RUN_FLAGS[@]} -gt 0 ]]; then
        echo "  docker run flags: ${DIND_RUN_FLAGS[*]}"
    else
        echo "  docker run flags: <none>"
    fi
    initialize_dind_run_dir
    if ! docker run -d \
        "${DIND_RUN_FLAGS[@]}" \
        --name "$DIND_CONTAINER" \
        -v "$PROJECT_ROOT":/workspace:ro \
        -v "$DIND_RUN_DIR":/run \
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
    local docker_probe_output=""
    while true; do
        local state
        state=$(docker inspect -f '{{.State.Status}}' "$DIND_CONTAINER" 2>/dev/null || echo "missing")
        if [[ "$state" != "running" ]]; then
            echo "  ✗ Docker-in-Docker container stopped unexpectedly (state: $state)"
            print_dind_logs
            echo "  Hint: set TEST_PRESERVE_RESOURCES=true to inspect the container manually"
            exit 1
        fi

        if docker_probe_output=$(docker run --rm \
            -v "$DIND_RUN_DIR":/run \
            "$DIND_CLIENT_IMAGE" \
            -H unix:///run/docker.sock info 2>&1); then
            echo "  ✓ Docker daemon ready after ${retries}s"
            break
        fi
        last_error=$docker_probe_output
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

detect_host_trivy() {
    if [[ -n "${CODING_AGENTS_TRIVY_BIN:-}" ]]; then
        if command -v "${CODING_AGENTS_TRIVY_BIN}" >/dev/null 2>&1; then
            command -v "${CODING_AGENTS_TRIVY_BIN}"
            return
        fi
        echo "  ⚠️  CODING_AGENTS_TRIVY_BIN is set to '${CODING_AGENTS_TRIVY_BIN}' but it is not executable" >&2
    fi
    if command -v trivy >/dev/null 2>&1; then
        command -v trivy
        return
    fi
    return 1
}

ensure_trivy_inside_isolation() {
    echo "  Ensuring Trivy CLI is available inside isolation..."
    if docker exec "$DIND_CONTAINER" sh -c "command -v trivy >/dev/null 2>&1"; then
        echo "  ✓ Trivy already present"
        return
    fi

    local host_trivy
    if host_trivy=$(detect_host_trivy); then
        echo "  Copying host Trivy binary ($host_trivy)"
        if ! docker cp "$host_trivy" "$DIND_CONTAINER:/usr/local/bin/trivy" >/dev/null 2>&1; then
            echo "  ✗ Failed to copy host Trivy binary into isolation"
            exit 1
        fi
        docker exec "$DIND_CONTAINER" chmod +x /usr/local/bin/trivy >/dev/null 2>&1 || true
        echo "  ✓ Trivy copied from host"
        return
    fi

    echo "  Host Trivy binary not found, downloading v${DEFAULT_TRIVY_VERSION}..."
    local install_script
    read -r -d '' install_script <<'EOF'
set -euo pipefail
if command -v trivy >/dev/null 2>&1; then
    exit 0
fi
apk add --no-cache curl tar >/dev/null 2>&1
arch="$(uname -m)"
case "$arch" in
    x86_64|amd64) pkg_arch="64bit" ;;
    arm64|aarch64) pkg_arch="ARM64" ;;
    armv7l|armv7) pkg_arch="ARM" ;;
    *) echo "Unsupported architecture for automatic Trivy install: $arch" >&2; exit 1 ;;
esac
tmpdir="$(mktemp -d)"
curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${pkg_arch}.tar.gz" | tar -xz -C "$tmpdir" trivy
install -m 0755 "$tmpdir/trivy" /usr/local/bin/trivy
rm -rf "$tmpdir"
EOF
    if ! docker exec -e TRIVY_VERSION="$DEFAULT_TRIVY_VERSION" "$DIND_CONTAINER" sh -c "$install_script"; then
        echo "  ✗ Failed to install Trivy inside isolation"
        exit 1
    fi
    echo "  ✓ Trivy ${DEFAULT_TRIVY_VERSION} installed via download"
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
    
    local -a exec_env=("-e" "TEST_PRESERVE_RESOURCES=${TEST_PRESERVE_RESOURCES:-false}")
    if [[ "$WITH_HOST_SECRETS" == "true" ]]; then
        exec_env+=(
            "-e" "TEST_WITH_HOST_SECRETS=true"
            "-e" "TEST_HOST_SECRETS_FILE=$DIND_SECRETS_PATH"
            "-e" "CODING_AGENTS_MCP_SECRETS_FILE=$DIND_SECRETS_PATH"
        )
    fi

    local test_exit_code=0
    docker exec "${exec_env[@]}" "$DIND_CONTAINER" bash -lc "$command" || test_exit_code=$?
    
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
    if [[ "$WITH_HOST_SECRETS" == "true" ]]; then
        CODING_AGENTS_MCP_SECRETS_FILE="$HOST_SECRETS_FILE" \
        TEST_WITH_HOST_SECRETS="true" \
        TEST_HOST_SECRETS_FILE="$HOST_SECRETS_FILE" \
        bash "$INTEGRATION_SCRIPT" "${TEST_ARGS[@]}"
    else
        bash "$INTEGRATION_SCRIPT" "${TEST_ARGS[@]}"
    fi
}

if [[ "$ISOLATION_MODE" = "host" ]]; then
    run_on_host
else
    start_dind
    wait_for_daemon
    bootstrap_tools
    ensure_trivy_inside_isolation
    stage_host_secrets_inside_dind
    run_integration_tests
fi
