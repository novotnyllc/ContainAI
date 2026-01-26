#!/bin/sh
# Generated from sync-manifest.toml - DO NOT EDIT
# Regenerate with: src/scripts/gen-dockerfile-symlinks.sh
# This script is COPY'd into the container and RUN during build
set -e

mkdir -p \
    /home/agent/.claude \
    /mnt/agent-data/claude/plugins \
    /mnt/agent-data/claude/skills \
    /mnt/agent-data/claude/commands \
    /mnt/agent-data/claude/agents \
    /mnt/agent-data/claude/hooks \
    /home/agent/.config/gh \
    /home/agent/.ssh \
    /home/agent/.config/opencode \
    /mnt/agent-data/config/opencode/agents \
    /mnt/agent-data/config/opencode/commands \
    /mnt/agent-data/config/opencode/skills \
    /mnt/agent-data/config/opencode/modes \
    /mnt/agent-data/config/opencode/plugins \
    /home/agent/.local/share/opencode \
    /home/agent/.config \
    /mnt/agent-data/config/tmux \
    /home/agent/.local/share \
    /mnt/agent-data/local/share/tmux \
    /mnt/agent-data/local/share/fonts \
    /mnt/agent-data/agents \
    /home/agent/.oh-my-zsh \
    /mnt/agent-data/shell/oh-my-zsh-custom \
    /mnt/agent-data/editors/vim \
    /mnt/agent-data/config/nvim \
    /mnt/agent-data/config/oh-my-posh \
    /home/agent/.vscode-server \
    /mnt/agent-data/vscode-server/extensions \
    /home/agent/.vscode-server/data/User \
    /mnt/agent-data/vscode-server/data/User/mcp \
    /mnt/agent-data/vscode-server/data/User/prompts \
    /home/agent/.vscode-server-insiders \
    /mnt/agent-data/vscode-server-insiders/extensions \
    /home/agent/.vscode-server-insiders/data/User \
    /mnt/agent-data/vscode-server-insiders/data/User/mcp \
    /mnt/agent-data/vscode-server-insiders/data/User/prompts \
    /home/agent/.copilot \
    /mnt/agent-data/copilot/skills \
    /home/agent/.gemini \
    /home/agent/.codex \
    /mnt/agent-data/codex/skills \
    /home/agent/.continue \
    /home/agent/.cursor \
    /mnt/agent-data/cursor/rules \
    /mnt/agent-data/cursor/extensions \
    /home/agent/.vscode-server/data/Machine \
    /home/agent/.vscode-server-insiders/data/Machine

ln -sfn /mnt/agent-data/claude/claude.json /home/agent/.claude.json
ln -sfn /mnt/agent-data/claude/credentials.json /home/agent/.claude/.credentials.json
ln -sfn /mnt/agent-data/claude/settings.json /home/agent/.claude/settings.json
ln -sfn /mnt/agent-data/claude/settings.local.json /home/agent/.claude/settings.local.json
rm -rf /home/agent/.claude/plugins && ln -sfn /mnt/agent-data/claude/plugins /home/agent/.claude/plugins
rm -rf /home/agent/.claude/skills && ln -sfn /mnt/agent-data/claude/skills /home/agent/.claude/skills
rm -rf /home/agent/.claude/commands && ln -sfn /mnt/agent-data/claude/commands /home/agent/.claude/commands
rm -rf /home/agent/.claude/agents && ln -sfn /mnt/agent-data/claude/agents /home/agent/.claude/agents
rm -rf /home/agent/.claude/hooks && ln -sfn /mnt/agent-data/claude/hooks /home/agent/.claude/hooks
ln -sfn /mnt/agent-data/claude/CLAUDE.md /home/agent/.claude/CLAUDE.md
ln -sfn /mnt/agent-data/config/gh/hosts.yml /home/agent/.config/gh/hosts.yml
ln -sfn /mnt/agent-data/config/gh/config.yml /home/agent/.config/gh/config.yml
ln -sfn /mnt/agent-data/git/gitignore_global /home/agent/.gitignore_global
ln -sfn /mnt/agent-data/ssh/config /home/agent/.ssh/config
ln -sfn /mnt/agent-data/ssh/known_hosts /home/agent/.ssh/known_hosts
ln -sfn /mnt/agent-data/config/opencode/opencode.json /home/agent/.config/opencode/opencode.json
ln -sfn /mnt/agent-data/config/opencode/agents /home/agent/.config/opencode/agents
ln -sfn /mnt/agent-data/config/opencode/commands /home/agent/.config/opencode/commands
ln -sfn /mnt/agent-data/config/opencode/skills /home/agent/.config/opencode/skills
ln -sfn /mnt/agent-data/config/opencode/modes /home/agent/.config/opencode/modes
ln -sfn /mnt/agent-data/config/opencode/plugins /home/agent/.config/opencode/plugins
ln -sfn /mnt/agent-data/config/opencode/instructions.md /home/agent/.config/opencode/instructions.md
ln -sfn /mnt/agent-data/local/share/opencode/auth.json /home/agent/.local/share/opencode/auth.json
ln -sfn /mnt/agent-data/config/tmux /home/agent/.config/tmux
ln -sfn /mnt/agent-data/local/share/tmux /home/agent/.local/share/tmux
ln -sfn /mnt/agent-data/local/share/fonts /home/agent/.local/share/fonts
ln -sfn /mnt/agent-data/agents /home/agent/.agents
rm -rf /home/agent/.bash_aliases_imported && ln -sfn /mnt/agent-data/shell/bash_aliases /home/agent/.bash_aliases_imported
ln -sfn /mnt/agent-data/shell/zshrc /home/agent/.zshrc
ln -sfn /mnt/agent-data/shell/zprofile /home/agent/.zprofile
ln -sfn /mnt/agent-data/shell/inputrc /home/agent/.inputrc
rm -rf /home/agent/.oh-my-zsh/custom && ln -sfn /mnt/agent-data/shell/oh-my-zsh-custom /home/agent/.oh-my-zsh/custom
ln -sfn /mnt/agent-data/editors/vimrc /home/agent/.vimrc
rm -rf /home/agent/.vim && ln -sfn /mnt/agent-data/editors/vim /home/agent/.vim
rm -rf /home/agent/.config/nvim && ln -sfn /mnt/agent-data/config/nvim /home/agent/.config/nvim
ln -sfn /mnt/agent-data/config/starship.toml /home/agent/.config/starship.toml
rm -rf /home/agent/.config/oh-my-posh && ln -sfn /mnt/agent-data/config/oh-my-posh /home/agent/.config/oh-my-posh
ln -sfn /mnt/agent-data/vscode-server/extensions /home/agent/.vscode-server/extensions
ln -sfn /mnt/agent-data/vscode-server/data/User/mcp /home/agent/.vscode-server/data/User/mcp
ln -sfn /mnt/agent-data/vscode-server/data/User/prompts /home/agent/.vscode-server/data/User/prompts
ln -sfn /mnt/agent-data/vscode-server-insiders/extensions /home/agent/.vscode-server-insiders/extensions
ln -sfn /mnt/agent-data/vscode-server-insiders/data/User/mcp /home/agent/.vscode-server-insiders/data/User/mcp
ln -sfn /mnt/agent-data/vscode-server-insiders/data/User/prompts /home/agent/.vscode-server-insiders/data/User/prompts
ln -sfn /mnt/agent-data/copilot/config.json /home/agent/.copilot/config.json
ln -sfn /mnt/agent-data/copilot/mcp-config.json /home/agent/.copilot/mcp-config.json
rm -rf /home/agent/.copilot/skills && ln -sfn /mnt/agent-data/copilot/skills /home/agent/.copilot/skills
ln -sfn /mnt/agent-data/gemini/google_accounts.json /home/agent/.gemini/google_accounts.json
ln -sfn /mnt/agent-data/gemini/oauth_creds.json /home/agent/.gemini/oauth_creds.json
ln -sfn /mnt/agent-data/gemini/settings.json /home/agent/.gemini/settings.json
ln -sfn /mnt/agent-data/gemini/GEMINI.md /home/agent/.gemini/GEMINI.md
ln -sfn /mnt/agent-data/codex/config.toml /home/agent/.codex/config.toml
ln -sfn /mnt/agent-data/codex/auth.json /home/agent/.codex/auth.json
rm -rf /home/agent/.codex/skills && ln -sfn /mnt/agent-data/codex/skills /home/agent/.codex/skills
ln -sfn /mnt/agent-data/aider/aider.conf.yml /home/agent/.aider.conf.yml
ln -sfn /mnt/agent-data/aider/aider.model.settings.yml /home/agent/.aider.model.settings.yml
ln -sfn /mnt/agent-data/continue/config.yaml /home/agent/.continue/config.yaml
ln -sfn /mnt/agent-data/continue/config.json /home/agent/.continue/config.json
ln -sfn /mnt/agent-data/cursor/mcp.json /home/agent/.cursor/mcp.json
rm -rf /home/agent/.cursor/rules && ln -sfn /mnt/agent-data/cursor/rules /home/agent/.cursor/rules
rm -rf /home/agent/.cursor/extensions && ln -sfn /mnt/agent-data/cursor/extensions /home/agent/.cursor/extensions
ln -sfn /mnt/agent-data/vscode-server/data/Machine/settings.json /home/agent/.vscode-server/data/Machine/settings.json
ln -sfn /mnt/agent-data/vscode-server/data/User/mcp.json /home/agent/.vscode-server/data/User/mcp.json
ln -sfn /mnt/agent-data/vscode-server-insiders/data/Machine/settings.json /home/agent/.vscode-server-insiders/data/Machine/settings.json
ln -sfn /mnt/agent-data/vscode-server-insiders/data/User/mcp.json /home/agent/.vscode-server-insiders/data/User/mcp.json
