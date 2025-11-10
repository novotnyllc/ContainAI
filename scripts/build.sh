#!/bin/bash
# Build script for the coding agents containers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "🏗️  Building Coding Agents Containers"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running!"
    echo "   Please start Docker and try again"
    exit 1
fi

# Ask user which base image to use
echo "Select base image source:"
echo "1) Pull from GitHub Container Registry (recommended)"
echo "2) Build locally (takes ~15 minutes)"
read -p "Enter choice (1 or 2): " choice

case $choice in
    1)
        read -p "Enter GitHub username for base image: " gh_username
        BASE_IMAGE="ghcr.io/$gh_username/coding-agents-base:latest"
        echo ""
        echo "📥 Pulling base image: $BASE_IMAGE"
        docker pull "$BASE_IMAGE" || {
            echo "❌ Failed to pull base image"
            echo "   Make sure the image exists and you're authenticated:"
            echo "   docker login ghcr.io"
            exit 1
        }
        ;;
    2)
        echo ""
        echo "🔨 Building base image locally..."
        echo "   This will take approximately 15 minutes..."
        docker build -f Dockerfile.base -t coding-agents-base:local .
        BASE_IMAGE="coding-agents-base:local"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo "🔨 Building all-agents image..."
docker build --build-arg BASE_IMAGE="$BASE_IMAGE" -t coding-agents:local .

echo ""
echo "🔨 Building individual agent images..."
docker build -f Dockerfile.copilot --build-arg BASE_IMAGE=coding-agents:local -t coding-agents-copilot:local .
docker build -f Dockerfile.codex --build-arg BASE_IMAGE=coding-agents:local -t coding-agents-codex:local .
docker build -f Dockerfile.claude --build-arg BASE_IMAGE=coding-agents:local -t coding-agents-claude:local .

echo ""
echo "✅ Build complete!"
echo ""
echo "Images created:"
echo "  • coding-agents:local (all agents, interactive shell)"
echo "  • coding-agents-copilot:local (launches Copilot directly)"
echo "  • coding-agents-codex:local (launches Codex directly)"
echo "  • coding-agents-claude:local (launches Claude directly)"
echo ""
echo "🚀 Run a container with:"
echo "   ./scripts/run-agent.sh /path/to/your/repo"
echo ""
echo "   Or using docker-compose:"
echo "   cp .env.example .env"
echo "   # Edit .env with your repo path and WSL username"
echo "   docker-compose up -d                    # All agents"
echo "   docker-compose --profile copilot up -d  # Just Copilot"
echo "   docker-compose --profile codex up -d    # Just Codex"
echo "   docker-compose --profile claude up -d   # Just Claude"
