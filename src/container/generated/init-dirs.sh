#!/usr/bin/env bash
# Generated from sync-manifest.toml - DO NOT EDIT
# Regenerate with: src/scripts/gen-init-dirs.sh
#
# This script is sourced by containai-init.sh to create volume structure.
# It uses helper functions defined in the parent script:
#   ensure_dir <path>          - create directory with validation
#   ensure_file <path> [json]  - create file (json=true for {} init)
#   safe_chmod <mode> <path>   - chmod with symlink/path validation

# Regular directories
ensure_dir "${DATA_DIR}/claude/plugins"
ensure_dir "${DATA_DIR}/claude/skills"
ensure_dir "${DATA_DIR}/claude/commands"
ensure_dir "${DATA_DIR}/claude/agents"
ensure_dir "${DATA_DIR}/claude/hooks"
ensure_dir "${DATA_DIR}/config/opencode/agents"
ensure_dir "${DATA_DIR}/config/opencode/commands"
ensure_dir "${DATA_DIR}/config/opencode/skills"
ensure_dir "${DATA_DIR}/config/opencode/modes"
ensure_dir "${DATA_DIR}/config/opencode/plugins"
ensure_dir "${DATA_DIR}/config/tmux"
ensure_dir "${DATA_DIR}/local/share/tmux"
ensure_dir "${DATA_DIR}/local/share/fonts"
ensure_dir "${DATA_DIR}/agents"
ensure_dir "${DATA_DIR}/shell/bashrc.d"
ensure_dir "${DATA_DIR}/shell/oh-my-zsh-custom"
ensure_dir "${DATA_DIR}/editors/vim"
ensure_dir "${DATA_DIR}/config/nvim"
ensure_dir "${DATA_DIR}/config/oh-my-posh"
ensure_dir "${DATA_DIR}/vscode-server/extensions"
ensure_dir "${DATA_DIR}/vscode-server/data/Machine"
ensure_dir "${DATA_DIR}/vscode-server/data/User/mcp"
ensure_dir "${DATA_DIR}/vscode-server/data/User/prompts"
ensure_dir "${DATA_DIR}/vscode-server-insiders/extensions"
ensure_dir "${DATA_DIR}/vscode-server-insiders/data/Machine"
ensure_dir "${DATA_DIR}/vscode-server-insiders/data/User/mcp"
ensure_dir "${DATA_DIR}/vscode-server-insiders/data/User/prompts"
ensure_dir "${DATA_DIR}/copilot/skills"
ensure_dir "${DATA_DIR}/codex/skills"
ensure_dir "${DATA_DIR}/cursor/rules"
ensure_dir "${DATA_DIR}/cursor/extensions"

# Regular files
ensure_file "${DATA_DIR}/claude/settings.json" true
ensure_file "${DATA_DIR}/claude/settings.local.json"
ensure_file "${DATA_DIR}/claude/CLAUDE.md"
ensure_file "${DATA_DIR}/config/gh/config.yml"
ensure_file "${DATA_DIR}/git/gitignore_global"
ensure_file "${DATA_DIR}/ssh/config"
ensure_file "${DATA_DIR}/ssh/known_hosts"
ensure_file "${DATA_DIR}/config/opencode/instructions.md"
ensure_file "${DATA_DIR}/shell/bash_aliases"
ensure_file "${DATA_DIR}/shell/zshrc"
ensure_file "${DATA_DIR}/shell/zprofile"
ensure_file "${DATA_DIR}/shell/inputrc"
ensure_file "${DATA_DIR}/editors/vimrc"
ensure_file "${DATA_DIR}/config/starship.toml"
ensure_file "${DATA_DIR}/copilot/config.json"
ensure_file "${DATA_DIR}/copilot/mcp-config.json"
ensure_file "${DATA_DIR}/gemini/settings.json" true
ensure_file "${DATA_DIR}/gemini/GEMINI.md"
ensure_file "${DATA_DIR}/codex/config.toml"
ensure_file "${DATA_DIR}/vscode-server/data/Machine/settings.json" true
ensure_file "${DATA_DIR}/vscode-server/data/User/mcp.json" true
ensure_file "${DATA_DIR}/vscode-server-insiders/data/Machine/settings.json" true
ensure_file "${DATA_DIR}/vscode-server-insiders/data/User/mcp.json" true

# Secret files (600 permissions)
ensure_file "${DATA_DIR}/claude/claude.json" true
safe_chmod 600 "${DATA_DIR}/claude/claude.json"
ensure_file "${DATA_DIR}/claude/credentials.json"
safe_chmod 600 "${DATA_DIR}/claude/credentials.json"
ensure_file "${DATA_DIR}/config/gh/hosts.yml"
safe_chmod 600 "${DATA_DIR}/config/gh/hosts.yml"
ensure_file "${DATA_DIR}/config/opencode/opencode.json" true
safe_chmod 600 "${DATA_DIR}/config/opencode/opencode.json"
ensure_file "${DATA_DIR}/local/share/opencode/auth.json"
safe_chmod 600 "${DATA_DIR}/local/share/opencode/auth.json"
ensure_file "${DATA_DIR}/gemini/google_accounts.json"
safe_chmod 600 "${DATA_DIR}/gemini/google_accounts.json"
ensure_file "${DATA_DIR}/gemini/oauth_creds.json"
safe_chmod 600 "${DATA_DIR}/gemini/oauth_creds.json"
ensure_file "${DATA_DIR}/codex/auth.json"
safe_chmod 600 "${DATA_DIR}/codex/auth.json"
ensure_file "${DATA_DIR}/aider/aider.conf.yml"
safe_chmod 600 "${DATA_DIR}/aider/aider.conf.yml"
ensure_file "${DATA_DIR}/aider/aider.model.settings.yml"
safe_chmod 600 "${DATA_DIR}/aider/aider.model.settings.yml"
ensure_file "${DATA_DIR}/continue/config.yaml"
safe_chmod 600 "${DATA_DIR}/continue/config.yaml"
ensure_file "${DATA_DIR}/continue/config.json" true
safe_chmod 600 "${DATA_DIR}/continue/config.json"
ensure_file "${DATA_DIR}/cursor/mcp.json" true
safe_chmod 600 "${DATA_DIR}/cursor/mcp.json"

# Secret directories (700 permissions)
