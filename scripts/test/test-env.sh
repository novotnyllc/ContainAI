#!/usr/bin/env bash
# Test environment setup and teardown utilities

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test configuration
source "$SCRIPT_DIR/test-config.sh"

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
    docker run -d \
        --name "$TEST_REGISTRY_CONTAINER" \
        --label "$TEST_LABEL_TEST" \
        --label "$TEST_LABEL_SESSION" \
        -p 5555:5000 \
        registry:2 >/dev/null
    
    # Wait for registry to be ready
    echo -n "  Waiting for registry to be ready"
    for i in {1..30}; do
        if curl -s http://localhost:5555/v2/ >/dev/null 2>&1; then
            echo " ✓"
            return 0
        fi
        echo -n "."
        sleep 1
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
        -f docker/base.Dockerfile \
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
            -f "docker/${agent}.Dockerfile" \
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
# Image Pulling (Launchers Mode)
# ============================================================================

pull_and_tag_test_images() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Pulling and tagging images for testing"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Pull from registry and tag for local testing
    local agents=("copilot" "codex" "claude")
    for agent in "${agents[@]}"; do
        echo ""
        echo "Pulling $agent image..."
        
        # Pull from actual registry
        local source_image="ghcr.io/yourusername/coding-agents-${agent}:latest"
        docker pull "$source_image" 2>/dev/null || {
            echo "  Warning: Could not pull $source_image, using local if available"
            source_image="coding-agents-${agent}:latest"
        }
        
        # Tag for testing
        local image_var="TEST_${agent^^}_IMAGE"
        local test_image="${!image_var}"
        
        docker tag "$source_image" "$test_image" || {
            echo "  Error: Could not tag image"
            return 1
        }
        
        # Push to local test registry
        echo "  Pushing to local test registry..."
        docker push "$test_image" || return 1
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
    if [ "$TEST_PRESERVE_RESOURCES" = "true" ]; then
        echo "Preserving test network: $TEST_NETWORK"
        return 0
    fi
    
    echo "Removing test network: $TEST_NETWORK"
    docker network rm "$TEST_NETWORK" 2>/dev/null || true
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
    git config user.name "$TEST_GH_USER"
    git config user.email "$TEST_GH_EMAIL"
    git config remote.pushDefault local
    
    # Create initial content
    cat > README.md << 'EOF'
# Test Repository

This is a test repository for the coding agents test suite.
EOF
    
    cat > src/main.py << 'EOF'
def hello():
    """Simple test function"""
    return "Hello, World!"

if __name__ == "__main__":
    print(hello())
EOF
    
    mkdir -p src
    git add .
    git commit -q -m "Initial commit"
    git checkout -q -b main
    
    echo "  Repository created with initial content"
}

cleanup_test_repository() {
    if [ "$TEST_PRESERVE_RESOURCES" = "true" ]; then
        echo "Preserving test repository: $TEST_REPO_DIR"
        return 0
    fi
    
    echo "Removing test repository: $TEST_REPO_DIR"
    rm -rf "$TEST_REPO_DIR"
}

# ============================================================================
# Test Container Cleanup
# ============================================================================

cleanup_test_containers() {
    if [ "$TEST_PRESERVE_RESOURCES" = "true" ]; then
        echo "Preserving test containers (session: $$)"
        return 0
    fi
    
    echo "Removing test containers..."
    
    # Remove by session label
    local containers=$(docker ps -aq --filter "label=$TEST_LABEL_SESSION")
    if [ -n "$containers" ]; then
        echo "$containers" | xargs docker rm -f 2>/dev/null || true
    fi
}

# ============================================================================
# Test Image Cleanup
# ============================================================================

cleanup_test_images() {
    if [ "$TEST_PRESERVE_RESOURCES" = "true" ]; then
        echo "Preserving test images"
        return 0
    fi
    
    echo "Removing test images..."
    
    # Remove test images from local registry namespace
    docker images --filter "reference=${TEST_REGISTRY}/${TEST_IMAGE_PREFIX}/*" -q | \
        xargs -r docker rmi -f 2>/dev/null || true
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
export -f pull_and_tag_test_images
export -f setup_test_network
export -f cleanup_test_network
export -f setup_test_repository
export -f cleanup_test_repository
export -f cleanup_test_containers
export -f cleanup_test_images
export -f setup_test_environment
export -f teardown_test_environment
