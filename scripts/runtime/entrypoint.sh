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
                        # Validate branch name (alphanumeric, dash, underscore, slash only)
                        if [[ "$BRANCH" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
                            echo "📤 Pushing changes to local remote..."
                            if git push local "$BRANCH" 2>/dev/null; then
                                echo "✅ Changes pushed to local remote: $REPO_NAME ($BRANCH)"
                            else
                                echo "⚠️  Failed to push (local remote may not be configured)"
                                echo "💡 Run: git remote add local <url> to enable auto-push"
                            fi
                        else
                            echo "⚠️  Invalid branch name, skipping push"
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
        
        # Sanitize: remove control characters, limit length
        ai_message=$(echo "$ai_message" | tr -d '\r\n\t' | head -c 100)
        
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

# Display current repository information (concise)
if [ -d .git ]; then
    branch=$(git branch --show-current 2>/dev/null || echo 'detached')
    echo "📁 $(git remote get-url origin 2>/dev/null || echo 'Local repository') [${branch}]"
else
    echo "⚠️  Not a git repository - run 'git init' if needed"
fi

# Configure git to use generic credential helper that delegates to host's auth
# Works with GitHub, GitLab, Bitbucket, Azure DevOps, self-hosted, etc.
# The credential helper tries: gh CLI (for github.com) -> git-credential-store
git config --global credential.helper ""
git config --global credential.helper '!/usr/local/bin/git-credential-host-helper.sh'

# Configure git autocrlf for Windows compatibility
git config --global core.autocrlf true

# Configure commit signing if host has it configured
# This allows verified commits while keeping signing keys secure on host
if [ -f /home/agentuser/.gitconfig ]; then
    # Check if host has GPG signing configured
    if host_gpg_key=$(git config --file /home/agentuser/.gitconfig user.signingkey 2>/dev/null); then
        if [ -n "$host_gpg_key" ]; then
            # Copy GPG signing configuration from host
            git config --global user.signingkey "$host_gpg_key"
            
            # Check if host has commit signing enabled
            if git config --file /home/agentuser/.gitconfig commit.gpgsign 2>/dev/null | grep -q "true"; then
                git config --global commit.gpgsign true
                
                # Use GPG proxy instead of copying host's gpg.program path
                # This keeps private keys secure on host
                if [ -S "${GPG_PROXY_SOCKET:-/tmp/gpg-proxy.sock}" ]; then
                    git config --global gpg.program /usr/local/bin/gpg-host-proxy.sh
                    echo "🔏 Commit signing: GPG via proxy (key: ${host_gpg_key:0:8}...)"
                elif [ -S "${HOME}/.gnupg/S.gpg-agent" ]; then
                    # Fallback: Use direct GPG agent socket if available
                    git config --global gpg.program gpg
                    echo "🔏 Commit signing: GPG via agent (key: ${host_gpg_key:0:8}...)"
                else
                    echo "⚠️  GPG signing configured but proxy/agent unavailable"
                fi
            fi
        fi
    fi
    
    # Check if host has SSH signing configured (newer git feature)
    if host_ssh_key=$(git config --file /home/agentuser/.gitconfig user.signingkey 2>/dev/null); then
        if git config --file /home/agentuser/.gitconfig gpg.format 2>/dev/null | grep -q "ssh"; then
            # Copy SSH signing configuration from host
            git config --global gpg.format ssh
            git config --global user.signingkey "$host_ssh_key"
            
            if git config --file /home/agentuser/.gitconfig commit.gpgsign 2>/dev/null | grep -q "true"; then
                git config --global commit.gpgsign true
                echo "🔏 Commit signing: SSH via agent"
            fi
            
            # SSH signing uses SSH agent socket - already forwarded if available
            # The signing key can be different from authentication key
        fi
    fi
fi

# Setup MCP configuration if config.toml exists
if [ -f "/workspace/config.toml" ]; then
    /usr/local/bin/setup-mcp-configs.sh 2>&1 | grep -E "^(ERROR|WARN)" || true
fi

# Setup VS Code tasks for container
if [ -f "/workspace/scripts/runtime/setup-vscode-tasks.sh" ]; then
    /workspace/scripts/runtime/setup-vscode-tasks.sh 2>/dev/null || true
fi

# Index project with Serena for faster semantic operations (silent unless error)
if [ -d "/workspace/.git" ]; then
    uvx --from "git+https://github.com/oraios/serena" serena project index --project /workspace >/dev/null 2>&1 || \
        echo "⚠️  Serena indexing failed"
fi

# Load MCP secrets from host mount if available
if [ -f "/home/agentuser/.mcp-secrets.env" ]; then
    set -a
    source /home/agentuser/.mcp-secrets.env
    set +a
fi

# Update Serena MCP server to latest version (silent)
uvx --refresh --from "git+https://github.com/oraios/serena@main" serena --version >/dev/null 2>&1 || true

# Check authentication and configuration (concise summary)
echo ""

# Collect authentication status quietly
auth_status=""
git_user=$(git config user.name 2>/dev/null || echo "")
[ -n "$git_user" ] && auth_status="${auth_status}git:${git_user} "

if [ -S "${CREDENTIAL_SOCKET:-/tmp/git-credential-proxy.sock}" ]; then
    auth_status="${auth_status}creds:proxy(secure) "
elif command -v gh &> /dev/null && gh auth status &> /dev/null 2>&1; then
    auth_status="${auth_status}creds:gh "
elif [ -f ~/.git-credentials ]; then
    auth_status="${auth_status}creds:file "
fi

if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
    key_count=$(ssh-add -l 2>/dev/null | grep -v "no identities" | wc -l)
    if [ "$key_count" -gt 0 ]; then
        auth_status="${auth_status}ssh:${key_count}keys "
    fi
elif [ -d ~/.ssh ] && [ -n "$(ls -A ~/.ssh/id_* 2>/dev/null)" ]; then
    auth_status="${auth_status}ssh:keys-only "
fi

# Single-line authentication summary
if [ -n "$auth_status" ]; then
    echo "✅ Auth: ${auth_status}"
else
    echo "⚠️  No authentication configured - see docs/vscode-integration.md"
fi

echo "✨ Container ready | MCP: /workspace/config.toml | Auto-commit on shutdown"
echo ""

# Execute the command passed to the container
exec "$@"
