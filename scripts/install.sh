#!/usr/bin/env bash
# Install coding-agents launchers to PATH
# Adds host/launchers directory to ~/.bashrc or ~/.zshrc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHERS_PATH="$REPO_ROOT/host/launchers"

if [[ ! -d "$LAUNCHERS_PATH" ]]; then
    echo "ERROR: Launchers directory not found: $LAUNCHERS_PATH"
    exit 1
fi

echo "Installing launchers to PATH..."

echo "Running Coding Agents prerequisite and health checks..."
if ! "$REPO_ROOT/host/utils/verify-prerequisites.sh"; then
    echo "❌ Prerequisite verification failed. Resolve the issues above and re-run scripts/install.sh."
    exit 1
fi

if ! "$REPO_ROOT/host/utils/check-health.sh"; then
    echo "❌ Health check failed. Resolve the issues above and re-run scripts/install.sh."
    exit 1
fi

# Determine shell rc file
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == *"zsh"* ]]; then
    RC_FILE="$HOME/.zshrc"
else
    RC_FILE="$HOME/.bashrc"
fi

# Create rc file if it doesn't exist
touch "$RC_FILE"

# Check if already in PATH
if grep -q "$LAUNCHERS_PATH" "$RC_FILE" 2>/dev/null; then
    echo "✓ Launchers already in $RC_FILE"
else
    # Add to rc file
    {
        echo ""
        echo "# Coding Agents launchers"
        echo "export PATH=\"$LAUNCHERS_PATH:\$PATH\""
    } >> "$RC_FILE"
    
    echo "✓ Added to $RC_FILE"
    echo ""
    echo "NOTE: Restart your terminal or run: source $RC_FILE"
fi

# Update current session
export PATH="$LAUNCHERS_PATH:$PATH"

echo ""
echo "Installation complete! You can now run:"
echo "  run-copilot, run-codex, run-claude"
echo "  launch-agent, list-agents, remove-agent"
