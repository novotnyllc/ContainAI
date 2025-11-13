#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Starting Coding Agents Container..."

# Cleanup function to push changes before shutdown
cleanup_on_shutdown() {
    echo ""
    echo "📤 Container shutting down..."
    
    # Check if auto-commit/push is enabled (default: true)
    AUTO_COMMIT="${AUTO_COMMIT_ON_SHUTDOWN:-true}"
    AUTO_PUSH="${AUTO_PUSH_ON_SHUTDOWN:-true}"
    
    if [ "$AUTO_COMMIT" != "true" ] && [ "$AUTO_PUSH" != "true" ]; then
        echo "⏭️  Auto-commit and auto-push disabled, skipping..."
        return 0
    fi
    
    # Only process if in a git repository
    if [ -d /workspace/.git ]; then
        cd /workspace || {
            echo "⚠️  Warning: Could not change to workspace directory"
            return 0
        }
        
        # Check if there are any changes (staged or unstaged)
        if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            if [ "$AUTO_COMMIT" = "true" ]; then
                echo "💾 Uncommitted changes detected, creating automatic commit..."
                
                # Get repository and branch info
                REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
                BRANCH=$(git branch --show-current 2>/dev/null)
                TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
                
                # Stage all changes (tracked and untracked)
                git add -A 2>/dev/null || {
                    echo "⚠️  Warning: Failed to stage changes"
                    return 0
                }
                
                # Generate commit message based on changes
                COMMIT_MSG=$(generate_auto_commit_message)
                
                # Create commit
                if git commit -m "$COMMIT_MSG" 2>/dev/null; then
                    echo "✅ Auto-commit created"
                    echo "   Message: $COMMIT_MSG"
                    
                    # Push if auto-push is also enabled
                    if [ "$AUTO_PUSH" = "true" ] && [ -n "$BRANCH" ]; then
                        echo "📤 Pushing changes to local remote..."
                        if git push local "$BRANCH" 2>/dev/null; then
                            echo "✅ Changes pushed to local remote: $REPO_NAME ($BRANCH)"
                        else
                            echo "⚠️  Failed to push (local remote may not be configured)"
                            echo "💡 Run: git remote add local <url> to enable auto-push"
                        fi
                    fi
                else
                    echo "⚠️  Warning: Failed to create commit"
                fi
            else
                echo "⚠️  Uncommitted changes exist but auto-commit is disabled"
                echo "💡 Set AUTO_COMMIT_ON_SHUTDOWN=true to enable"
            fi
        else
            echo "✅ No uncommitted changes"
        fi
    fi
}

# Generate intelligent commit message based on git status
generate_auto_commit_message() {
    local agent_name="${AGENT_NAME:-unknown}"
    
    # Get git diff summary
    local diff_stat=$(git diff --cached --stat 2>/dev/null | tail -1)
    local files_changed=$(git diff --cached --name-only 2>/dev/null | head -10)
    
    # Try to generate commit message using the active AI agent
    local ai_message=""
    
    # Check if GitHub Copilot CLI is available and authenticated
    if command -v github-copilot-cli &> /dev/null && gh auth status &> /dev/null 2>&1; then
        echo "🤖 Asking GitHub Copilot to generate commit message..." >&2
        
        # Create prompt for the AI
        local prompt="Based on these git changes, write a concise commit message (50 chars max, conventional commits format):

Files changed:
$files_changed

Diff summary:
$diff_stat

Provide only the commit message, no explanation."
        
        # Use GitHub Copilot to generate message (with timeout)
        ai_message=$(timeout 10s github-copilot-cli suggest "$prompt" 2>/dev/null | head -1 | tr -d '\n' || echo "")
        
    # Fallback: Check if gh copilot is available as extension
    elif command -v gh &> /dev/null && gh auth status &> /dev/null 2>&1; then
        if gh copilot --help &> /dev/null 2>&1; then
            echo "🤖 Asking GitHub Copilot to generate commit message..." >&2
            
            local prompt="Write a concise git commit message for these changes (max 50 chars, conventional commits format):
$files_changed

Only output the commit message, nothing else."
            
            ai_message=$(timeout 10s gh copilot suggest -t shell "$prompt" 2>/dev/null | grep -v "^$" | head -1 | tr -d '\n' || echo "")
        fi
    fi
    
    # Clean up AI message if we got one
    if [ -n "$ai_message" ]; then
        # Remove common prefixes and clean up
        ai_message=$(echo "$ai_message" | sed -e 's/^git commit -m "//' -e 's/"$//' -e 's/^[Cc]ommit message: //' -e 's/^Message: //' | tr -d '\n')
        
        # Validate it's reasonable (not too long, not empty)
        if [ ${#ai_message} -gt 10 ] && [ ${#ai_message} -lt 100 ]; then
            echo "$ai_message"
            return 0
        fi
    fi
    
    # Fallback: Generate basic message if AI fails
    local added modified deleted
    added=$(git diff --cached --name-only --diff-filter=A 2>/dev/null | wc -l)
    modified=$(git diff --cached --name-only --diff-filter=M 2>/dev/null | wc -l)
    deleted=$(git diff --cached --name-only --diff-filter=D 2>/dev/null | wc -l)
    
    local msg_parts=()
    if [ "$added" -gt 0 ]; then msg_parts+=("$added added"); fi
    if [ "$modified" -gt 0 ]; then msg_parts+=("$modified modified"); fi
    if [ "$deleted" -gt 0 ]; then msg_parts+=("$deleted deleted"); fi
    
    local changes=$(IFS=", "; echo "${msg_parts[*]}")
    echo "chore: auto-commit ($changes)"
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

# Index project with Serena for faster semantic operations
if [ -d "/workspace/.git" ]; then
    echo "📊 Indexing workspace for Serena (faster code navigation)..."
    uvx --from "git+https://github.com/oraios/serena" serena project index --project /workspace 2>/dev/null || \
        echo "⚠️  Serena indexing skipped (may be slower on first use)"
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
echo "🔄 Auto-commit/push enabled on container shutdown"
echo "   - Uncommitted changes will be auto-committed with generated message"
echo "   - Changes will be pushed to 'local' remote (if configured)"
echo "   - Disable: AUTO_COMMIT_ON_SHUTDOWN=false or AUTO_PUSH_ON_SHUTDOWN=false"
echo ""

# Execute the command passed to the container
exec "$@"
