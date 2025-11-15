#!/usr/bin/env bash
# Test environment setup and teardown utilities
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test configuration
source "$SCRIPT_DIR/test-config.sh"

# Constants for timing and retries
REGISTRY_STARTUP_TIMEOUT=30
REGISTRY_POLL_INTERVAL=1
CONTAINER_STARTUP_WAIT=2
LONG_RUNNING_SLEEP=3600

FIXTURE_CONFIG_FILE="$TEST_MOCK_SECRETS_DIR/config.toml"
FIXTURE_GH_TOKEN_FILE="$TEST_MOCK_SECRETS_DIR/gh-token.txt"
TEST_PROXY_STARTED="false"

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
    for i in {1..10}; do
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
        registry:2 2>&1 >/dev/null; then
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
    
    # Build base image
    echo ""
    echo "Building base image..."
    docker build \
        -f docker/base/Dockerfile \
        -t "$TEST_BASE_IMAGE" \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        . || return 1
    
    # Push to local registry
    echo "  Pushing to local registry..."
    docker push "$TEST_BASE_IMAGE" || return 1
    
    # Build agent images (they will pull from local registry)
    local agents=("copilot" "codex" "claude")
    for agent in "${agents[@]}"; do
        echo ""
        echo "Building $agent image..."
        
        # Get the test image variable name
        local image_var="TEST_${agent^^}_IMAGE"
        local test_image="${!image_var}"
        
        docker build \
            -f "docker/agents/${agent}/Dockerfile" \
            -t "$test_image" \
            --build-arg BASE_IMAGE="$TEST_BASE_IMAGE" \
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
    echo "Building lightweight mock agent images"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local build_dir
    build_dir=$(mktemp -d)

    cp "$PROJECT_ROOT/scripts/runtime/setup-mcp-configs.sh" "$build_dir/setup-mcp-configs.sh"
    cp "$PROJECT_ROOT/scripts/utils/convert-toml-to-mcp.py" "$build_dir/convert-toml-to-mcp.py"

    cat > "$build_dir/Dockerfile" <<'EOF'
FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash git ca-certificates curl jq && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash agentuser

COPY setup-mcp-configs.sh /usr/local/bin/setup-mcp-configs.sh
COPY convert-toml-to-mcp.py /usr/local/bin/convert-toml-to-mcp.py
RUN chmod +x /usr/local/bin/setup-mcp-configs.sh

USER agentuser
WORKDIR /workspace
CMD ["sleep", "infinity"]
EOF

    # Build base mock image once
    echo ""
    echo "Building mock image..."
    local base_mock_image="${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/base-mock:test"
    docker build -t "$base_mock_image" "$build_dir" || {
        rm -rf "$build_dir"
        return 1
    }
    
    # Tag and push for each agent
    local agents=("copilot" "codex" "claude")
    for agent in "${agents[@]}"; do
        local image_var="TEST_${agent^^}_IMAGE"
        local test_image="${!image_var}"
        echo "  Tagging for $agent..."
        docker tag "$base_mock_image" "$test_image" || {
            rm -rf "$build_dir"
            return 1
        }
        if [ "${TEST_USE_REGISTRY_PULLS:-true}" = "true" ]; then
            docker push "$test_image" >/dev/null 2>&1 || {
                rm -rf "$build_dir"
                return 1
            }
        fi
    done

    rm -rf "$build_dir"
    echo ""
    echo "✓ Mock agent images built"
    return 0
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
        local source_image="${source_registry}/coding-agents-${agent}:latest"
        if docker pull "$source_image" >/dev/null 2>&1; then
            echo "  ✓ Pulled $source_image"
        else
            echo "  ⚠️  Warning: Could not pull $source_image from registry"
            source_image="coding-agents-${agent}:latest"
            if docker image inspect "$source_image" >/dev/null 2>&1; then
                echo "  ✓ Using local image: $source_image"
            else
                echo "  ⚠️  No local image named $source_image"
                echo "  🔨 Building mock agent images locally..."
                build_mock_agent_images
                return $?
            fi
        fi
        
        local image_var="TEST_${agent^^}_IMAGE"
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

This is a test repository for the coding agents test suite.
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
    
    # Remove by session label
    local containers
    containers=$(docker ps -aq --filter "label=$TEST_LABEL_SESSION" 2>/dev/null || true)
    if [ -z "${containers}" ]; then
        echo "  No test containers to remove"
        return 0
    fi
    
    echo "${containers}" | xargs docker rm -f 2>/dev/null || {
        echo "⚠️  Warning: Some containers could not be removed"
        return 1
    }
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
    local images
    images=$(docker images --filter "reference=${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/*" -q 2>/dev/null || true)
    if [ -z "${images}" ]; then
        echo "  No test images to remove"
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
