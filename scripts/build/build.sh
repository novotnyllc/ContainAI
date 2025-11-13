#!/usr/bin/env bash
# Build script for the coding agents containers

set -euo pipefail

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
        read -p "Enter GitHub username or org for base image [novotnyllc]: " gh_username
        gh_username=${gh_username:-novotnyllc}
        BASE_IMAGE="ghcr.io/$gh_username/coding-agents-base:latest"
        echo ""
        echo "📥 Pulling base image: $BASE_IMAGE"
        if ! docker pull "$BASE_IMAGE"; then
            echo "❌ Failed to pull base image"
            echo "   Make sure the image exists and you're authenticated:"
            echo "   docker login ghcr.io -u $gh_username"
            echo ""
            echo "   Or build locally instead (option 2)"
            exit 1
        fi
        ;;
    2)
        echo ""
        echo "🔨 Building base image locally..."
        echo "   This will take approximately 15 minutes..."
        if ! docker build -f docker/base/Dockerfile -t coding-agents-base:local .; then
            echo "❌ Failed to build base image"
            exit 1
        fi
        BASE_IMAGE="coding-agents-base:local"
        ;;
    *)
        echo "❌ Invalid choice: $choice"
        echo "   Please enter 1 or 2"
        exit 1
        ;;
esac

echo ""
echo "🔨 Building all-agents image..."
if ! docker build -f docker/agents/all/Dockerfile --build-arg BASE_IMAGE="$BASE_IMAGE" -t coding-agents:local .; then
    echo "❌ Failed to build all-agents image"
    exit 1
fi

echo ""
echo "🔨 Building individual agent images..."
for agent in copilot codex claude; do
    if ! docker build -f "docker/agents/${agent}/Dockerfile" --build-arg BASE_IMAGE=coding-agents:local -t "coding-agents-${agent}:local" .; then
        echo "❌ Failed to build ${agent} image"
        exit 1
    fi
done

echo ""
echo "🔨 Building network proxy image..."
if ! docker build -f docker/proxy/Dockerfile -t coding-agents-proxy:local .; then
    echo "❌ Failed to build proxy image"
    exit 1
fi

echo ""
echo "✅ Build complete!"
echo ""
echo "Images created:"
echo "  • coding-agents:local (all agents, interactive shell)"
echo "  • coding-agents-copilot:local (launches Copilot directly)"
echo "  • coding-agents-codex:local (launches Codex directly)"
echo "  • coding-agents-claude:local (launches Claude directly)"
echo "  • coding-agents-proxy:local (Squid network proxy sidecar)"
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
