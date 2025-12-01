#!/usr/bin/env bash
# Run the integration test suite inside an isolated Docker-in-Docker environment
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INTEGRATION_SCRIPT="$PROJECT_ROOT/scripts/test/integration-test-impl.sh"

# Source centralized base image utilities
# shellcheck source=host/utils/base-image.sh
source "$PROJECT_ROOT/host/utils/base-image.sh"

# When running in bash (including WSL), pwd already returns Unix-style paths
# that Docker can mount. No conversion needed.

# ============================================================================
# Unique Run Identification (for parallel CI jobs)
# ============================================================================

generate_run_id() {
    # Prefer CI-provided IDs for parallel job safety, fall back to timestamp-based ID
    if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
        echo "gh-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}"
    elif [[ -n "${CI_JOB_ID:-}" ]]; then
        echo "ci-${CI_JOB_ID}"
    elif [[ -n "${BUILD_ID:-}" ]]; then
        echo "jenkins-${BUILD_ID}"
    else
        # Local development - use PID and timestamp for uniqueness
        echo "local-$$-$(date +%s)"
    fi
}

RUN_ID="$(generate_run_id)"
RUN_TIMESTAMP="$(date +%s)"

DIND_IMAGE="${TEST_ISOLATION_IMAGE:-docker:25.0-dind}"
DIND_CONTAINER="${TEST_ISOLATION_CONTAINER:-containai-dind-${RUN_ID}}"
LABEL_RUN_ID="containai.test.run=${RUN_ID}"
LABEL_CREATED="containai.test.created=${RUN_TIMESTAMP}"
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
DIND_SECRETS_PATH="/run/containai/mcp-secrets.env"
DEFAULT_TRIVY_VERSION="${TEST_ISOLATION_TRIVY_VERSION:-0.50.2}"
CACHE_DIR="${DIND_CACHE_DIR:-${HOME}/.cache/containai/dind-docker}"

if [[ -n "${TEST_ISOLATION_DOCKER_RUN_FLAGS:-}" ]]; then
    # shellcheck disable=SC2206
    DIND_RUN_FLAGS=(${TEST_ISOLATION_DOCKER_RUN_FLAGS})
else
    DIND_RUN_FLAGS=(--privileged)
fi

fix_cache_permissions() {
    if [[ "${PERSIST_CACHE:-true}" != "true" ]]; then
        return
    fi

    if [[ -d "$CACHE_DIR" ]]; then
        echo "  Fixing cache directory permissions..."
        # Use docker to fix permissions since files inside are root-owned
        # We use alpine because it's small and likely available/cached
        if ! docker run --rm \
            -v "$CACHE_DIR":/cache \
            alpine:3.19 \
            chown -R "$(id -u):$(id -g)" /cache 2>&1; then
            echo "  ⚠️  Permission fix failed (may need manual: sudo chown -R \$(id -u):\$(id -g) $CACHE_DIR)"
        fi
    fi
}

cleanup() {
    local exit_code=$?

    # Disable further traps to prevent recursion
    trap - EXIT INT TERM HUP QUIT

    scrub_dind_host_secrets

    if [[ "${TEST_PRESERVE_RESOURCES:-false}" == "true" ]]; then
        if [[ "$DIND_STARTED" == "true" ]]; then
            echo ""
            echo "Preserving isolated Docker daemon ($DIND_CONTAINER) for debugging (TEST_PRESERVE_RESOURCES=true)"
        fi
        if [[ -n "$DIND_RUN_DIR" ]]; then
            echo "Shared /run directory preserved at: $DIND_RUN_DIR"
        fi
    else
        if [[ "$DIND_STARTED" == "true" ]]; then
            echo ""
            echo "Cleaning up isolated Docker daemon..."
            # Graceful stop to prevent cache corruption
            docker stop -t 10 "$DIND_CONTAINER" >/dev/null 2>&1 || true
            docker rm -fv "$DIND_CONTAINER" >/dev/null 2>&1 || true

            fix_cache_permissions
        fi

        # Clean up any other resources from this run (networks, etc.)
        cleanup_this_run

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
    if ! DIND_RUN_DIR=$(mktemp -d -t containai-dind-run-XXXXXX); then
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
Run the ContainAI integration test suite.

This script runs all integration tests inside an isolated Docker-in-Docker
environment to ensure reproducibility and prevent host daemon contamination.

Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --mode launchers    Test with existing/mock images (default, ~5-10 minutes)
    --mode full         Build all images from Dockerfiles (~15-25 minutes)
    --filter REGEX      Run only tests matching the regex
    --preserve          Keep test resources after completion for debugging
    --isolation dind    Run tests inside Docker-in-Docker (default)
    --isolation host    Run tests directly on host Docker daemon (optional, skips DinD risk)
    --with-host-secrets Enable host-secrets prompt tests (copies secrets into isolation when needed)
    --no-persist-cache  Do not persist Docker cache between runs (default: cache is persisted)
    --prune             Remove all cached data and stale containers, then exit
    --help              Show this help message

ENVIRONMENT VARIABLES:
    TEST_ISOLATION_IMAGE            Override Docker-in-Docker image (default: docker:25.0-dind)
    TEST_ISOLATION_CONTAINER        Override container name
    TEST_ISOLATION_CLIENT_IMAGE     Override helper CLI image used to probe DinD readiness
    TEST_ISOLATION_STARTUP_TIMEOUT  Daemon startup wait time in seconds (default: 300)
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

    if [[ -n "${CONTAINAI_MCP_SECRETS_FILE:-}" ]]; then
        candidates+=("${CONTAINAI_MCP_SECRETS_FILE}")
    fi
    if [[ -n "${MCP_SECRETS_FILE:-}" ]]; then
        candidates+=("${MCP_SECRETS_FILE}")
    fi
    candidates+=("${HOME}/.config/containai/mcp-secrets.env" "${HOME}/.mcp-secrets.env")

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
        --filter)
            if [[ $# -lt 2 ]]; then
                echo "Error: --filter requires an argument" >&2
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
        --persist-cache)
            PERSIST_CACHE=true
            shift
            ;;
        --no-persist-cache)
            PERSIST_CACHE=false
            shift
            ;;
        --prune)
            PRUNE_MODE=true
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
Set CONTAINAI_MCP_SECRETS_FILE, MCP_SECRETS_FILE, or populate ~/.config/containai/mcp-secrets.env
EOF
        exit 1
    fi
    export TEST_WITH_HOST_SECRETS="true"
    export TEST_HOST_SECRETS_FILE="$HOST_SECRETS_FILE"
fi

# Clean up resources from THIS run only (scoped cleanup)
cleanup_this_run() {
    echo "Cleaning up resources for run: ${RUN_ID}"

    # Stop and remove containers for THIS run only
    local containers
    containers=$(docker ps -aq --filter "label=${LABEL_RUN_ID}" 2>/dev/null || true)
    if [[ -n "$containers" ]]; then
        echo "$containers" | xargs docker rm -f 2>/dev/null || true
    fi

    # Remove networks for this run
    docker network ls -q --filter "label=${LABEL_RUN_ID}" 2>/dev/null \
        | xargs -r docker network rm 2>/dev/null || true
}

# Clean up stale resources from crashed/abandoned runs (timestamp-based)
cleanup_stale_resources() {
    local max_age_seconds="${1:-7200}"  # 2 hours default
    local now
    now=$(date +%s)

    echo "Checking for stale test resources (older than ${max_age_seconds}s)..."

    # Find containers with our label prefix that are too old
    local found_stale=false
    while read -r container_id; do
        [[ -z "$container_id" ]] && continue
        local created_ts
        created_ts=$(docker inspect --format '{{ index .Config.Labels "containai.test.created" }}' "$container_id" 2>/dev/null || echo "")

        if [[ -n "$created_ts" && $((now - created_ts)) -gt $max_age_seconds ]]; then
            echo "  Removing stale container: $container_id (age: $((now - created_ts))s)"
            docker rm -f "$container_id" 2>/dev/null || true
            found_stale=true
        fi
    done < <(docker ps -aq --filter "label=containai.test.run" 2>/dev/null || true)

    # Also clean up legacy containers (old naming scheme) that might be orphaned
    local legacy_containers
    legacy_containers=$(docker ps -aq --filter "name=containai-test-dind-" 2>/dev/null || true)
    if [[ -n "$legacy_containers" ]]; then
        echo "  Removing legacy DinD containers..."
        # shellcheck disable=SC2086
        docker rm -fv $legacy_containers >/dev/null 2>&1 || true
        found_stale=true
    fi

    if [[ "$found_stale" == "false" ]]; then
        echo "  No stale resources found"
    fi
}

if [[ "${PRUNE_MODE:-false}" == "true" ]]; then
    cleanup_stale_resources
    if [[ -d "$CACHE_DIR" ]]; then
        echo "Purging DinD cache directory: $CACHE_DIR"
        # Use docker to remove root-owned files in cache
        docker run --rm \
            -v "$(dirname "$CACHE_DIR")":/work \
            alpine:3.19 \
            rm -rf "/work/$(basename "$CACHE_DIR")"
        echo "✓ Cache purged"
    else
        echo "Cache directory does not exist (nothing to prune)"
    fi
    exit 0
fi

# Clean up any stale containers from previous aborted runs before starting
cleanup_stale_resources

# Catch all termination signals for robust cleanup
trap cleanup EXIT INT TERM HUP QUIT

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
    echo "  Run ID: $RUN_ID"
    echo "  Mounting: $PROJECT_ROOT -> /workspace (read-only)"

    initialize_dind_run_dir

    local -a docker_args=(
        "${DIND_RUN_FLAGS[@]}"
        "--name" "$DIND_CONTAINER"
        "--label" "$LABEL_RUN_ID"
        "--label" "$LABEL_CREATED"
        "-v" "$PROJECT_ROOT:/workspace:ro"
        "-v" "$DIND_RUN_DIR:/run"
        "-e" "DOCKER_TLS_CERTDIR="
    )

    if [[ "${PERSIST_CACHE:-true}" == "true" ]]; then
        mkdir -p "$CACHE_DIR"
        echo "  Mounting cache: $CACHE_DIR -> /var/lib/docker"
        docker_args+=("-v" "$CACHE_DIR:/var/lib/docker")
    fi

    if [[ ${#DIND_RUN_FLAGS[@]} -gt 0 ]]; then
        echo "  docker run flags: ${DIND_RUN_FLAGS[*]}"
    else
        echo "  docker run flags: <none>"
    fi
    
    local run_output
    if ! run_output=$(docker run -d \
        "${docker_args[@]}" \
        "$DIND_IMAGE" 2>&1); then
        echo "Error: Failed to start Docker-in-Docker container"
        echo "Docker error output:"
        echo "$run_output" | sed 's/^/  /'
        echo "This may indicate missing --privileged support or image pull failure"
        print_dind_logs
        exit 1
    fi
    DIND_STARTED=true
}

wait_for_daemon() {
    echo "  Waiting for Docker daemon to initialize (this can take 20-30 seconds)..."
    local retries=0
    local max_retries=${TEST_ISOLATION_STARTUP_TIMEOUT:-300}
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
    # Trust the workspace directory for git operations to avoid "dubious ownership" warnings
    docker exec "$DIND_CONTAINER" git config --global --add safe.directory /workspace
    echo "  ✓ Tooling installed"
}

inject_base_image() {
    # Build base image on host using centralized utility (handles caching & cleanup)
    # Then inject into DinD for test isolation
    (
        # shellcheck source=scripts/test/test-config.sh
        source "$SCRIPT_DIR/test-config.sh"

        echo "  Preparing base image..."

        # Build on host with content-hash caching (one version per channel)
        local host_image
        if ! host_image=$(build_base_image); then
            echo "  ⚠️  Failed to build base image on host, skipping injection"
            return 0
        fi

        # Check if DinD already has this exact image
        local host_id
        host_id=$(docker inspect --format='{{.Id}}' "$host_image" 2>/dev/null || echo "")

        local dind_id
        dind_id=$(docker exec "$DIND_CONTAINER" docker inspect --format='{{.Id}}' "$host_image" 2>/dev/null || echo "missing")

        if [[ -n "$host_id" && "$host_id" == "$dind_id" ]]; then
            echo "  ✓ Base image already present in isolation (checksum match)"
        else
            echo "  Injecting base image into isolation..."
            # Pipe save output directly to load input
            if ! docker save "$host_image" | docker exec -i "$DIND_CONTAINER" docker load >/dev/null; then
                echo "  ⚠️  Failed to inject base image"
                return 0
            fi
            echo "  ✓ Base image injected"
        fi

        # Tag for test suite use
        echo "  Tagging as $TEST_BASE_IMAGE..."
        if ! docker exec "$DIND_CONTAINER" docker tag "$host_image" "$TEST_BASE_IMAGE"; then
            echo "  ⚠️  Failed to tag injected image"
        fi

        # Clean up old base images inside DinD (same channel only)
        local channel="${CONTAINAI_LAUNCHER_CHANNEL:-dev}"
        docker exec "$DIND_CONTAINER" sh -c "
            docker images --format '{{.Repository}}:{{.Tag}}' \
                | grep '^containai-base:${channel}-' \
                | grep -v '$host_image' \
                | xargs -r docker rmi 2>/dev/null || true
        "

        # Prune dangling images in DinD
        docker exec "$DIND_CONTAINER" docker image prune -f >/dev/null 2>&1 || true

        if [[ "${PERSIST_CACHE:-true}" != "true" ]]; then
            echo "  (Tip: Cache persistence is disabled. Enable with --persist-cache for faster runs)"
        fi
    )
}

detect_host_trivy() {
    if [[ -n "${CONTAINAI_TRIVY_BIN:-}" ]]; then
        if command -v "${CONTAINAI_TRIVY_BIN}" >/dev/null 2>&1; then
            command -v "${CONTAINAI_TRIVY_BIN}"
            return
        fi
        echo "  ⚠️  CONTAINAI_TRIVY_BIN is set to '${CONTAINAI_TRIVY_BIN}' but it is not executable" >&2
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
            "-e" "CONTAINAI_MCP_SECRETS_FILE=$DIND_SECRETS_PATH"
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
        CONTAINAI_MCP_SECRETS_FILE="$HOST_SECRETS_FILE" \
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
    inject_base_image
    ensure_trivy_inside_isolation
    stage_host_secrets_inside_dind
    run_integration_tests
fi
