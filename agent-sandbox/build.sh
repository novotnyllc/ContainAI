#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Build agent-sandbox Docker image
# ==============================================================================
# Builds and tags the dotnet-sandbox image:
#   - agent-sandbox:latest
#   - agent-sandbox:YYYY-MM-DD
#
# Usage: ./build.sh [docker build options]
#   Example: ./build.sh --no-cache
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="agent-sandbox"
DATE_TAG="$(date +%Y-%m-%d)"

echo "Building $IMAGE_NAME..."
echo "  Tags: :latest, :$DATE_TAG"
echo ""

docker build \
    -t "${IMAGE_NAME}:latest" \
    -t "${IMAGE_NAME}:${DATE_TAG}" \
    "$@" \
    "$SCRIPT_DIR"

echo ""
echo "Build complete!"
echo "  docker images ${IMAGE_NAME}"
docker images "${IMAGE_NAME}" --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
