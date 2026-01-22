#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Build ContainAI Docker images (layered build)
# ==============================================================================
# Usage: ./build.sh [options] [docker build options]
#   --dotnet-channel CHANNEL  .NET SDK channel (default: 10.0)
#   --layer LAYER             Build only specific layer (base|sdks|full|all)
#   --help                    Show this help
#
# Build order: base -> sdks -> full -> containai (alias)
#
# Examples:
#   ./build.sh                          # Build all layers
#   ./build.sh --layer base             # Build only base layer
#   ./build.sh --dotnet-channel lts     # Use latest LTS for .NET
#   ./build.sh --no-cache               # Pass option to docker build
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATE_TAG="$(date +%Y-%m-%d)"

# Defaults
DOTNET_CHANNEL="10.0"
BUILD_LAYER="all"

# Parse options
DOCKER_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dotnet-channel)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --dotnet-channel requires a value" >&2
                exit 1
            fi
            DOTNET_CHANNEL="$2"
            shift 2
            ;;
        --layer)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --layer requires a value (base|sdks|full|all)" >&2
                exit 1
            fi
            BUILD_LAYER="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '4,19p' "$0" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            DOCKER_ARGS+=("$1")
            shift
            ;;
    esac
done

# Enable BuildKit
export DOCKER_BUILDKIT=1

# Generate OCI label values
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

# Build function for a single layer
build_layer() {
    local name="$1"
    local dockerfile="$2"
    local extra_args=("${@:3}")

    echo ""
    echo "=== Building containai/${name} ==="
    echo ""

    docker build \
        -t "containai/${name}:latest" \
        -t "containai/${name}:${DATE_TAG}" \
        --build-arg BUILD_DATE="$BUILD_DATE" \
        --build-arg VCS_REF="$VCS_REF" \
        ${extra_args[@]+"${extra_args[@]}"} \
        ${DOCKER_ARGS[@]+"${DOCKER_ARGS[@]}"} \
        -f "${SCRIPT_DIR}/${dockerfile}" \
        "$SCRIPT_DIR"

    echo "  Tagged: containai/${name}:latest, containai/${name}:${DATE_TAG}"
}

# Build layers based on selection
case "$BUILD_LAYER" in
    base)
        build_layer "base" "Dockerfile.base"
        ;;
    sdks)
        build_layer "sdks" "Dockerfile.sdks" --build-arg DOTNET_CHANNEL="$DOTNET_CHANNEL"
        ;;
    full)
        build_layer "full" "Dockerfile.full"
        ;;
    all)
        echo "Building all ContainAI layers..."
        echo "  .NET channel: $DOTNET_CHANNEL"

        # Build in dependency order
        build_layer "base" "Dockerfile.base"
        build_layer "sdks" "Dockerfile.sdks" --build-arg DOTNET_CHANNEL="$DOTNET_CHANNEL"
        build_layer "full" "Dockerfile.full"

        # Build final alias image
        echo ""
        echo "=== Building containai (final image) ==="
        echo ""
        docker build \
            -t "containai:latest" \
            -t "containai:${DATE_TAG}" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            --build-arg VCS_REF="$VCS_REF" \
            ${DOCKER_ARGS[@]+"${DOCKER_ARGS[@]}"} \
            -f "${SCRIPT_DIR}/Dockerfile" \
            "$SCRIPT_DIR"
        echo "  Tagged: containai:latest, containai:${DATE_TAG}"
        ;;
    *)
        echo "ERROR: Unknown layer '$BUILD_LAYER'. Use: base, sdks, full, or all" >&2
        exit 1
        ;;
esac

echo ""
echo "Build complete!"
echo ""
docker images "containai*" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" | head -20
