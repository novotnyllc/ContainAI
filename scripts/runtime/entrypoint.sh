#!/bin/bash
set -e

echo "🚀 Starting Coding Agents Container..."

# Cleanup function to push changes before shutdown
cleanup_on_shutdown() {
    echo ""
    echo "📤 Container shutting down..."
    
    # Check if auto-push is enabled (default: true)
    AUTO_PUSH="${AUTO_PUSH_ON_SHUTDOWN:-true}"
    
    if [ "$AUTO_PUSH" != "true" ]; then
        echo "⏭️  Auto-push disabled, skipping..."
        return
    fi
    
    # Only push if in a git repository with uncommitted changes
    if [ -d /workspace/.git ]; then
        cd /workspace
        
        # Check if there are any changes to commit
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            echo "💾 Uncommitted changes detected, pushing to local remote..."
            
            REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
            BRANCH=$(git branch --show-current 2>/dev/null)
            
            if [ -n "$BRANCH" ]; then
                # Push to local remote (host machine)
                if git push local "$BRANCH" 2>/dev/null; then
                    echo "✅ Changes pushed to local remote: $REPO_NAME ($BRANCH)"
                else
                    echo "⚠️  Failed to push changes (local remote may not be configured)"
                fi
            else
                echo "⚠️  Not on a branch, skipping push"
            fi
        else
            echo "✅ No uncommitted changes, nothing to push"
        fi
    fi
}

# Register cleanup on shutdown signals
trap cleanup_on_shutdown SIGTERM SIGINT EXIT

# Ensure we're in the workspace directory
cd /workspace || exit 1

# Display current repository information
if [ -d .git ]; then
    echo "📁 Repository: $(git remote get-url origin 2>/dev/null || echo 'Local repository')"
    echo "🌿 Branch: $(git branch --show-current 2>/dev/null || echo 'Unknown')"
    echo "📝 Last commit: $(git log -1 --oneline 2>/dev/null || echo 'No commits')"
else
    echo "⚠️  Warning: Not a git repository. Initialize with 'git init' if needed."
fi

# Announce network policy for transparency
case "${NETWORK_POLICY:-allow-all}" in
    restricted)
        echo "🌐 Network policy: restricted (container launched without outbound network)"
        ;;
    squid)
        echo "🌐 Network policy: squid (traffic routed through proxy sidecar)"
        ;;
    *)
        echo "🌐 Network policy: allow-all (standard Docker bridge network)"
        ;;
esac

# Configure git to use HTTPS with gh credential helper (OAuth from host)
git config --global credential.helper ""
git config --global credential.helper '!gh auth git-credential'

# Setup MCP configuration if config.toml exists
if [ -f "/workspace/config.toml" ]; then
    echo "⚙️  Setting up MCP configurations from workspace config.toml..."
    /usr/local/bin/setup-mcp-configs.sh
else
    echo "ℹ️  No config.toml found in workspace - MCP servers not configured"
fi

# Load MCP secrets from host mount if available
if [ -f "/home/agentuser/.mcp-secrets.env" ]; then
    echo "🔐 Loading MCP secrets from host..."
    set -a
    source /home/agentuser/.mcp-secrets.env
    set +a
else
    echo "ℹ️  No MCP secrets file found (optional)"
fi

# Update Serena MCP server to latest version
echo "🔄 Updating Serena MCP server..."
uvx --refresh --from "git+https://github.com/oraios/serena@main" serena --version >/dev/null 2>&1 || \
    echo "⚠️  Serena update skipped (offline or unavailable)"

# Check authentication status (all from host mounts via OAuth)
echo ""
if command -v gh &> /dev/null; then
    if gh auth status &> /dev/null 2>&1; then
        echo "✅ GitHub CLI authenticated via OAuth (from host)"
    else
        echo "⚠️  GitHub CLI: Run 'gh auth login' in WSL2 host, then restart container"
    fi
fi

# Check git config (from host mount)
if git config user.name &> /dev/null 2>&1; then
    echo "✅ Git configured (from host)"
else
    echo "⚠️  Git: Configure in WSL2 host with 'git config --global user.name/email'"
fi

echo ""
echo "✨ Container ready - Prompt-free operation enabled!"
echo ""
echo "Available coding agents (OAuth authenticated):"
echo "  • GitHub Copilot: Use 'github-copilot-cli' or alias '??'"
echo "  • Codex: Use 'codex' command"
echo "  • Claude: Use 'claude' command"
echo ""
echo "Repository: /workspace (automatically trusted)"
echo "MCP config: /workspace/config.toml"
echo "Policy: approval_policy = \"always\" (no prompts)"
echo ""
echo "💡 All authentication uses OAuth from WSL2 host"
echo "   - GitHub/Copilot: via gh CLI (~/.config/gh/hosts.yml)"
echo "   - Codex/Claude: via native OAuth configs"
echo "   - Update on host, restart container to refresh"
echo ""

# Execute the command passed to the container
exec "$@"
