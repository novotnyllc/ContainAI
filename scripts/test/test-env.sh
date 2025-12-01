#!/usr/bin/env bash
# shellcheck source=scripts/test/test-config.sh
# Test environment setup and teardown utilities
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source centralized base image utilities
# shellcheck source=host/utils/base-image.sh disable=SC1091
source "$PROJECT_ROOT/host/utils/base-image.sh"

# Source test configuration
# shellcheck source=scripts/test/test-config.sh disable=SC1091
source "$SCRIPT_DIR/test-config.sh"

# Constants for timing and retries
REGISTRY_STARTUP_TIMEOUT=30
REGISTRY_POLL_INTERVAL=1
export CONTAINER_STARTUP_WAIT=2
export LONG_RUNNING_SLEEP=3600

FIXTURE_CONFIG_FILE="$TEST_MOCK_SECRETS_DIR/config.toml"
FIXTURE_GH_TOKEN_FILE="$TEST_MOCK_SECRETS_DIR/gh-token.txt"
TEST_PROXY_STARTED="false"
SECRET_SCANNER_BIN="${CONTAINAI_TRIVY_BIN:-}"
BUILD_CONTEXT_SCANNED="false"

ensure_secret_scanner() {
    if [[ -n "$SECRET_SCANNER_BIN" ]]; then
        if command -v "$SECRET_SCANNER_BIN" >/dev/null 2>&1; then
            SECRET_SCANNER_BIN="$(command -v "$SECRET_SCANNER_BIN")"
            return
        fi
        echo "❌ CONTAINAI_TRIVY_BIN is set to '$SECRET_SCANNER_BIN' but it is not executable"
        exit 1
    fi
    if command -v trivy >/dev/null 2>&1; then
        SECRET_SCANNER_BIN="$(command -v trivy)"
        return
    fi
    echo "❌ Trivy CLI is required for automatic image secret scanning" >&2
    echo "   Install it from https://aquasecurity.github.io/trivy or set CONTAINAI_TRIVY_BIN" >&2
    exit 1
}

# Scan build context for secrets BEFORE building any images.
# This is more efficient than scanning each image (no layer extraction needed)
# and catches secrets at the source before they're baked into images.
scan_build_context_for_secrets() {
    # Only scan once per test run
    if [[ "$BUILD_CONTEXT_SCANNED" == "true" ]]; then
        return 0
    fi
    
    ensure_secret_scanner
    echo "🔍 Scanning build context for secrets before image builds..."
    
    # Scan the directories that get COPYed into images
    local scan_dirs=(
        "$PROJECT_ROOT/docker"
        "$PROJECT_ROOT/agent-configs"
        "$PROJECT_ROOT/host"
        "$PROJECT_ROOT/scripts"
    )
    
    for dir in "${scan_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "  Scanning $dir..."
            if ! "$SECRET_SCANNER_BIN" fs \
                --scanners secret \
                --severity HIGH,CRITICAL \
                --exit-code 1 \
                --no-progress \
                "$dir"; then
                echo "❌ Secret scan failed in $dir" >&2
                exit 1
            fi
        fi
    done
    
    BUILD_CONTEXT_SCANNED="true"
    echo "✓ Build context secret scan passed"
}

# ============================================================================
# Fixture Helpers
# ============================================================================

populate_mock_workspace_assets() {
    if [ -f "$FIXTURE_CONFIG_FILE" ]; then
        cp "$FIXTURE_CONFIG_FILE" "$TEST_REPO_DIR/config.toml"
        echo "  Added mock config.toml to test repository"
    fi

    if [ -f "$FIXTURE_GH_TOKEN_FILE" ]; then
        mkdir -p "$TEST_REPO_DIR/.mock-secrets"
        cp "$FIXTURE_GH_TOKEN_FILE" "$TEST_REPO_DIR/.mock-secrets/gh-token.txt"
    fi
}

start_mock_proxy() {
    echo "Starting mock HTTP proxy..."

    docker network create \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        "$TEST_PROXY_NETWORK" 2>/dev/null || true

    docker run -d \
        --name "$TEST_PROXY_CONTAINER" \
        --network "$TEST_PROXY_NETWORK" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        alpine:3.19 sh -c "apk add --no-cache busybox-extras >/dev/null && while true; do nc -l -p 3128 >/dev/null; done" >/dev/null

    TEST_PROXY_STARTED="true"
    
    # Wait for listener to be ready with health check polling
    echo -n "  Waiting for proxy listener"
    for _ in {1..10}; do
        if docker exec "$TEST_PROXY_CONTAINER" nc -z localhost 3128 2>/dev/null; then
            echo " ✓"
            return 0
        fi
        echo -n "."
        sleep 1
    done
    echo " ✗ Proxy listener failed to start"
    return 1
}

stop_mock_proxy() {
    if [ "$TEST_PROXY_STARTED" != "true" ]; then
        return 0
    fi

    if [ "$TEST_PRESERVE_RESOURCES" = "true" ]; then
        echo "Preserving mock proxy resources"
        return 0
    fi

    echo "Stopping mock proxy..."
    docker rm -f "$TEST_PROXY_CONTAINER" 2>/dev/null || true
    docker network rm "$TEST_PROXY_NETWORK" 2>/dev/null || true
    TEST_PROXY_STARTED="false"
}

# ============================================================================
# Local Registry Management
# ============================================================================

start_local_registry() {
    echo "Starting local Docker registry..."
    
    # Check if registry already running
    if docker ps --filter "name=$TEST_REGISTRY_CONTAINER" --format "{{.Names}}" | grep -q "^${TEST_REGISTRY_CONTAINER}$"; then
        echo "  Registry already running"
        return 0
    fi
    
    # Start registry container
    if ! docker run -d \
        --name "$TEST_REGISTRY_CONTAINER" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        -p 5555:5000 \
        registry:2 >/dev/null 2>&1; then
        echo "  ✗ Failed to start registry container"
        return 1
    fi
    
    # Wait for registry to be ready
    echo -n "  Waiting for registry to be ready"
    local elapsed=0
    while [ $elapsed -lt $REGISTRY_STARTUP_TIMEOUT ]; do
        if curl -s http://localhost:5555/v2/ >/dev/null 2>&1; then
            echo " ✓"
            return 0
        fi
        echo -n "."
        sleep $REGISTRY_POLL_INTERVAL
        elapsed=$((elapsed + REGISTRY_POLL_INTERVAL))
    done
    
    echo " ✗ Failed to start registry"
    return 1
}

stop_local_registry() {
    if [ "$TEST_PRESERVE_RESOURCES" = "true" ]; then
        echo "Preserving local registry (use docker rm -f $TEST_REGISTRY_CONTAINER to remove)"
        return 0
    fi
    
    echo "Stopping local registry..."
    docker rm -f "$TEST_REGISTRY_CONTAINER" 2>/dev/null || true
}

# ============================================================================
# Image Building (Full Mode)
# ============================================================================

build_test_images() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Building test images in isolated environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    cd "$PROJECT_ROOT"
    
    # Scan build context for secrets BEFORE building any images
    # This catches secrets at the source and uses much less disk than image scanning
    scan_build_context_for_secrets

    # Build base image using centralized utility (handles caching & cleanup)
    echo ""
    echo "Building base image..."
    local base_tag
    if ! base_tag=$(build_base_image); then
        echo "❌ Failed to build base image"
        return 1
    fi

    # Tag for test registry and push
    echo "  Tagging as $TEST_BASE_IMAGE..."
    docker tag "$base_tag" "$TEST_BASE_IMAGE" || return 1
    echo "  Pushing to local registry..."
    docker push "$TEST_BASE_IMAGE" || return 1

    # Build agent images using the base image
    local agents=("copilot" "codex" "claude")
    for agent in "${agents[@]}"; do
        echo ""
        echo "Building $agent image..."

        # Get the test image variable name
        local agent_upper
        agent_upper=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')
        local image_var="TEST_${agent_upper}_IMAGE"
        local test_image="${!image_var}"

        docker build \
            -f "docker/agents/${agent}/Dockerfile" \
            -t "$test_image" \
            --build-arg BASE_IMAGE="$base_tag" \
            --build-arg BUILDKIT_INLINE_CACHE=1 \
            . || return 1

        echo "  Pushing to local registry..."
        docker push "$test_image" || return 1
    done

    echo ""
    echo "✓ All test images built successfully"
    return 0
}

# ============================================================================
# Lightweight Mock Images (Launchers Mode Fallback)
# ============================================================================

build_mock_agent_images() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Building full agent images (mock fallback disabled)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Falling back to repository Dockerfiles to preserve runtime parity"
    build_test_images
}

# ============================================================================
# Image Pulling (Launchers Mode)
# ============================================================================

pull_and_tag_test_images() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Pulling and tagging images for testing"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local agents=("copilot" "codex" "claude")
    for agent in "${agents[@]}"; do
        echo ""
        echo "Pulling $agent image..."
        
        local source_registry="${TEST_SOURCE_REGISTRY:-ghcr.io/yourusername}"
        local source_image="${source_registry}/containai-${agent}:latest"
        if docker pull "$source_image" >/dev/null 2>&1; then
            echo "  ✓ Pulled $source_image"
        else
            echo "  ⚠️  Warning: Could not pull $source_image from registry"
            source_image="containai-${agent}:latest"
            if docker image inspect "$source_image" >/dev/null 2>&1; then
                echo "  ✓ Using local image: $source_image"
            else
                echo "  ⚠️  No local image named $source_image"
                echo "  🔨 Building mock agent images locally..."
                build_mock_agent_images
                return $?
            fi
        fi
        
        local agent_upper
        agent_upper=$(printf '%s' "$agent" | tr '[:lower:]' '[:upper:]')
        local image_var="TEST_${agent_upper}_IMAGE"
        local test_image="${!image_var}"
        
        if ! docker tag "$source_image" "$test_image"; then
            echo "  ❌ Error: Could not tag image"
            return 1
        fi
        
        if [ "${TEST_USE_REGISTRY_PULLS:-true}" = "true" ]; then
            echo "  Pushing to local test registry..."
            if ! docker push "$test_image" >/dev/null 2>&1; then
                echo "  ❌ Error: Could not push to local registry"
                return 1
            fi
        fi
    done
    
    echo ""
    echo "✓ All images pulled and tagged for testing"
    return 0
}

# ============================================================================
# Test Network Setup
# ============================================================================

setup_test_network() {
    echo "Creating test network: $TEST_NETWORK"
    
    docker network create \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        "$TEST_NETWORK" 2>/dev/null || true
}

cleanup_test_network() {
    if [ "${TEST_PRESERVE_RESOURCES:-false}" = "true" ]; then
        echo "Preserving test network: $TEST_NETWORK"
        return 0
    fi
    
    echo "Removing test network: $TEST_NETWORK"
    docker network rm "$TEST_NETWORK" 2>/dev/null || {
        echo "⚠️  Warning: Could not remove test network"
        return 1
    }
}

# ============================================================================
# Test Repository Setup
# ============================================================================

setup_test_repository() {
    echo "Creating test repository: $TEST_REPO_DIR"
    
    rm -rf "$TEST_REPO_DIR"
    mkdir -p "$TEST_REPO_DIR"
    cd "$TEST_REPO_DIR"
    
    # Initialize git repo
    git init -q
    git config --local user.name "$TEST_GH_USER"
    git config --local user.email "$TEST_GH_EMAIL"
    git config --local remote.pushDefault local
    git config --local commit.gpgsign false
    
    # Create initial content
    cat > README.md << 'EOF'
# Test Repository

This is a test repository for the ContainAI test suite.
EOF
    
    mkdir -p src
    cat > src/main.py << 'EOF'
def hello():
    """Simple test function"""
    return "Hello, World!"

if __name__ == "__main__":
    print(hello())
EOF
    git add .
    git commit -q -m "Initial commit"
    if git rev-parse --verify --quiet main >/dev/null; then
        git checkout -q main
    else
        git checkout -q -b main
    fi

    populate_mock_workspace_assets
    
    echo "  Repository created with initial content"
}

cleanup_test_repository() {
    if [ "${TEST_PRESERVE_RESOURCES:-false}" = "true" ]; then
        echo "Preserving test repository: $TEST_REPO_DIR"
        return 0
    fi
    
    echo "Removing test repository: $TEST_REPO_DIR"
    rm -rf "$TEST_REPO_DIR" || {
        echo "⚠️  Warning: Could not remove test repository"
        return 1
    }
}

# ============================================================================
# Test Container Cleanup
# ============================================================================

cleanup_test_containers() {
    if [ "${TEST_PRESERVE_RESOURCES:-false}" = "true" ]; then
        echo "Preserving test containers (session: $$)"
        return 0
    fi
    
    echo "Removing test containers..."
    local attempt=0
    local max_attempts=5
    while true; do
        local containers
        containers=$(docker ps -aq --filter "label=$TEST_LABEL_SESSION" 2>/dev/null || true)
        if [ -z "$containers" ]; then
            if [ $attempt -eq 0 ]; then
                echo "  No test containers to remove"
            else
                echo "  ✓ Test containers removed"
            fi
            return 0
        fi
        echo "$containers" | xargs docker rm -f 2>/dev/null || true
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            local remaining
            remaining=$(docker ps -aq --filter "label=$TEST_LABEL_SESSION" 2>/dev/null || true)
            if [ -n "$remaining" ]; then
                echo "⚠️  Warning: Containers still present after cleanup attempts: $remaining"
                return 1
            fi
            echo "  ✓ Test containers removed"
            return 0
        fi
        echo "  Waiting for containers to terminate (attempt $attempt/$max_attempts)..."
        sleep 1
    done
}

# ============================================================================
# Test Image Cleanup
# ============================================================================

cleanup_test_images() {
    if [ "${TEST_PRESERVE_RESOURCES:-false}" = "true" ]; then
        echo "Preserving test images"
        return 0
    fi
    
    echo "Removing test images..."
    
    # Remove test images from local registry namespace
    # Exclude the base image if we are persisting cache, to avoid re-loading it next time
    local filter_arg="reference=${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/*"
    
    local images
    images=$(docker images --filter "$filter_arg" -q 2>/dev/null || true)
    
    if [ -z "${images}" ]; then
        echo "  No test images to remove"
        return 0
    fi

    # If persisting cache, we want to keep the base image so we don't have to reload it
    if [ "${PERSIST_CACHE:-true}" = "true" ]; then
        local base_id
        base_id=$(docker images -q "$TEST_BASE_IMAGE" 2>/dev/null || true)
        
        if [ -n "$base_id" ]; then
            echo "  Preserving base image ($TEST_BASE_IMAGE) for cache persistence"
            # Filter out the base image ID from the list of images to delete
            images=$(echo "$images" | grep -v "$base_id" || true)
        fi
    fi
    
    if [ -z "${images}" ]; then
        echo "  No other test images to remove"
        return 0
    fi
    
    echo "${images}" | xargs docker rmi -f 2>/dev/null || {
        echo "⚠️  Warning: Some images could not be removed"
        return 1
    }
}

# ============================================================================
# Complete Environment Setup
# ============================================================================

setup_test_environment() {
    local mode="${1:-launchers}"
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║           Setting Up Test Environment                     ║"
    echo "║           Mode: $(printf '%-44s' "$mode")║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Start local registry
    start_local_registry || return 1
    
    # Setup network
    setup_test_network
    
    # Setup test repository
    setup_test_repository
    
    # Build or pull images based on mode
    if [ "$mode" = "full" ]; then
        build_test_images || return 1
    else
        pull_and_tag_test_images || return 1
    fi
    
    echo ""
    echo "✓ Test environment ready"
    echo ""
    
    return 0
}

# ============================================================================
# Complete Environment Teardown
# ============================================================================

teardown_test_environment() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Cleaning up test environment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cleanup_test_containers
    cleanup_test_network
    cleanup_test_repository
    cleanup_test_images
    stop_local_registry
    stop_mock_proxy
    
    if [ "$TEST_PRESERVE_RESOURCES" = "true" ]; then
        echo ""
        echo "Resources preserved. To clean up manually:"
        echo "  docker ps -aq --filter 'label=$TEST_LABEL_SESSION' | xargs docker rm -f"
        echo "  docker network rm $TEST_NETWORK"
        echo "  rm -rf $TEST_REPO_DIR"
        echo "  docker rm -f $TEST_REGISTRY_CONTAINER"
    else
        echo ""
        echo "✓ Test environment cleaned up"
    fi
    
    echo ""
}

# Export functions
export -f start_local_registry
export -f stop_local_registry
export -f build_test_images
export -f build_mock_agent_images
export -f pull_and_tag_test_images
export -f setup_test_network
export -f cleanup_test_network
export -f setup_test_repository
export -f cleanup_test_repository
export -f cleanup_test_containers
export -f cleanup_test_images
export -f setup_test_environment
export -f teardown_test_environment
export -f populate_mock_workspace_assets
export -f start_mock_proxy
export -f stop_mock_proxy
