#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Build agent-sandbox Docker image
# ==============================================================================
# Usage: ./build.sh [options] [docker build options]
#   --dotnet-channel CHANNEL  .NET SDK channel (default: 10.0)
#   --help                    Show this help
#
# Examples:
#   ./build.sh                          # Build with defaults
#   ./build.sh --dotnet-channel lts     # Use latest LTS
#   ./build.sh --no-cache               # Pass option to docker build
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="agent-sandbox"
DATE_TAG="$(date +%Y-%m-%d)"

# Defaults
DOTNET_CHANNEL="10.0"

# Parse options
DOCKER_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dotnet-channel)
            if [[ -z "${2-}" ]]; then
                echo "ERROR: --dotnet-channel requires a value" >&2
                echo "Usage: ./build.sh [options] [docker build options]" >&2
                exit 1
            fi
            DOTNET_CHANNEL="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '4,16p' "$0" | sed 's/^# //' | sed 's/^#//'
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

# Capture baseline
BASELINE_SIZE=$(docker images "${IMAGE_NAME}:latest" --format '{{.Size}}' 2>/dev/null | head -1)
if [[ -z "$BASELINE_SIZE" ]]; then
    echo "=== Baseline: (no existing image) ==="
    HAVE_BASELINE=0
else
    echo "=== Baseline: $BASELINE_SIZE ==="
    HAVE_BASELINE=1
fi

# Generate OCI label values
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VCS_REF="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

echo "Building $IMAGE_NAME..."
echo "  Tags: :latest, :$DATE_TAG"
echo "  .NET channel: $DOTNET_CHANNEL"
echo ""

docker build \
    -t "${IMAGE_NAME}:latest" \
    -t "${IMAGE_NAME}:${DATE_TAG}" \
    --build-arg DOTNET_CHANNEL="$DOTNET_CHANNEL" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg VCS_REF="$VCS_REF" \
    ${DOCKER_ARGS[@]+"${DOCKER_ARGS[@]}"} \
    "$SCRIPT_DIR"

# Capture result
RESULT_SIZE=$(docker images "${IMAGE_NAME}:latest" --format '{{.Size}}' | head -1)
if [[ -z "$RESULT_SIZE" ]]; then
    echo "ERROR: Build did not produce ${IMAGE_NAME}:latest"
    exit 1
fi

echo ""
echo "Build complete!"
echo "=== Result: $RESULT_SIZE ==="
docker images "${IMAGE_NAME}" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"

