# syntax=docker/dockerfile:1
# Custom Claude Code sandbox with Latest version

FROM docker/sandbox-templates:claude-code

# Switch to root to perform installation
USER root

# Upgrade Claude Code to Latest
RUN <<EOF
#!/bin/bash
set -e

echo "=== Installing latest Claude Code version ==="

# Configure npm to use user-level global installation
# This installs to ~/.npm-global instead of /usr/local/lib/node_modules
su - agent -c "mkdir -p ~/.npm-global"
su - agent -c "npm config set prefix '~/.npm-global'"
su - agent -c "echo 'export PATH=~/.npm-global/bin:\$PATH' >> ~/.bashrc"

# Install latest Claude Code using npm (goes to user directory)
su - agent -c "npm install -g @anthropic-ai/claude-code@latest"

echo "=== New Claude Code version ==="
su - agent -c "source ~/.bashrc && claude --version"

# Workaround the sandbox not doing this automatically
su - agent -c "ln -s /mnt/claude-data/.credentials.json /home/agent/.claude/.credentials.json"
EOF

# Switch back to agent user
USER agent
WORKDIR /home/agent/workspace