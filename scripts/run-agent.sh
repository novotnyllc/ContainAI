#!/bin/bash
# Helper script to run the coding agent container with a specific repository

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if repository path is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-repository> [container-name]"
    echo ""
    echo "Example: $0 ~/local-dev/my-project my-project"
    echo "Example: $0 /path/to/my-project"
    exit 1
fi

REPO_PATH="$(realpath "$1")"
REPO_NAME="${2:-$(basename "$REPO_PATH")}"

# Check if path exists
if [ ! -d "$REPO_PATH" ]; then
    echo "❌ Error: Repository path does not exist: $REPO_PATH"
    exit 1
fi

# Check if it's a git repository
if [ ! -d "$REPO_PATH/.git" ]; then
    echo "⚠️  Warning: $REPO_PATH is not a git repository"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "🚀 Starting coding agent container..."
echo "📁 Repository: $REPO_PATH"
echo "🏷️  Container: coding-agent-$REPO_NAME"
echo ""

# Run the container
docker run -it --rm \
    --name "coding-agent-$REPO_NAME" \
    --hostname "coding-agent" \
    -v "$REPO_PATH:/workspace" \
    -v "$HOME/.ssh:/home/agentuser/.ssh:ro" \
    -w /workspace \
    --network bridge \
    --security-opt no-new-privileges:true \
    --cpus="4" \
    --memory="8g" \
    coding-agents:local \
    /bin/bash

echo ""
echo "👋 Container stopped."
