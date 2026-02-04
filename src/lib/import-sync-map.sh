# Generated from src/manifests/ - DO NOT EDIT
# Regenerate with: src/scripts/gen-import-map.sh src/manifests/
#
# This array maps host paths to volume paths for import.
# Format: /source/<host_path>:/target/<volume_path>:<flags>
#
# Flags:
#   f = file, d = directory
#   j = json-init (create {} if empty)
#   s = secret (skipped with --no-secrets)
#   o = optional (skip if source does not exist)
#   g = git-filter (strip credential.helper and signing config)
#   x = exclude .system/ subdirectory
#   p = exclude *.priv.* files

_IMPORT_SYNC_MAP=(
    "/source/.local/share/fonts:/target/local/share/fonts:d"
    "/source/.agents:/target/agents:d"
    "/source/.config/containai/manifests:/target/containai/manifests:do"
    "/source/.bash_aliases:/target/shell/bash_aliases:f"
    "/source/.bashrc.d:/target/shell/bashrc.d:dp"
    "/source/.zshrc:/target/shell/zshrc:f"
    "/source/.zprofile:/target/shell/zprofile:f"
    "/source/.zshenv:/target/shell/zshenv:f"
    "/source/.inputrc:/target/shell/inputrc:f"
    "/source/.oh-my-zsh/custom:/target/shell/oh-my-zsh-custom:d"
    "/source/.gitignore_global:/target/git/gitignore_global:f"
    "/source/.config/gh/hosts.yml:/target/config/gh/hosts.yml:fs"
    "/source/.config/gh/config.yml:/target/config/gh/config.yml:f"
    "/source/.vimrc:/target/editors/vimrc:f"
    "/source/.vim:/target/editors/vim:d"
    "/source/.config/nvim:/target/config/nvim:d"
    "/source/.vscode-server/extensions:/target/vscode-server/extensions:d"
    "/source/.vscode-server/data/Machine:/target/vscode-server/data/Machine:d"
    "/source/.vscode-server/data/User/mcp:/target/vscode-server/data/User/mcp:d"
    "/source/.vscode-server/data/User/prompts:/target/vscode-server/data/User/prompts:d"
    "/source/.vscode-server-insiders/extensions:/target/vscode-server-insiders/extensions:d"
    "/source/.vscode-server-insiders/data/Machine:/target/vscode-server-insiders/data/Machine:d"
    "/source/.vscode-server-insiders/data/User/mcp:/target/vscode-server-insiders/data/User/mcp:d"
    "/source/.vscode-server-insiders/data/User/prompts:/target/vscode-server-insiders/data/User/prompts:d"
    "/source/.tmux.conf:/target/config/tmux/tmux.conf:f"
    "/source/.config/tmux:/target/config/tmux:d"
    "/source/.local/share/tmux:/target/local/share/tmux:d"
    "/source/.config/starship.toml:/target/config/starship.toml:f"
    "/source/.config/oh-my-posh:/target/config/oh-my-posh:d"
    "/source/.claude.json:/target/claude/claude.json:fjs"
    "/source/.claude/.credentials.json:/target/claude/credentials.json:fs"
    "/source/.claude/settings.json:/target/claude/settings.json:fj"
    "/source/.claude/settings.local.json:/target/claude/settings.local.json:f"
    "/source/.claude/plugins:/target/claude/plugins:d"
    "/source/.claude/skills:/target/claude/skills:d"
    "/source/.claude/commands:/target/claude/commands:d"
    "/source/.claude/agents:/target/claude/agents:d"
    "/source/.claude/hooks:/target/claude/hooks:d"
    "/source/.claude/CLAUDE.md:/target/claude/CLAUDE.md:f"
    "/source/.codex/config.toml:/target/codex/config.toml:f"
    "/source/.codex/auth.json:/target/codex/auth.json:fs"
    "/source/.codex/skills:/target/codex/skills:dx"
    "/source/.gemini/google_accounts.json:/target/gemini/google_accounts.json:fso"
    "/source/.gemini/oauth_creds.json:/target/gemini/oauth_creds.json:fso"
    "/source/.gemini/settings.json:/target/gemini/settings.json:fjo"
    "/source/.gemini/GEMINI.md:/target/gemini/GEMINI.md:fo"
    "/source/.copilot/config.json:/target/copilot/config.json:fo"
    "/source/.copilot/mcp-config.json:/target/copilot/mcp-config.json:fo"
    "/source/.copilot/skills:/target/copilot/skills:do"
    "/source/.config/opencode/opencode.json:/target/config/opencode/opencode.json:fjs"
    "/source/.config/opencode/agents:/target/config/opencode/agents:d"
    "/source/.config/opencode/commands:/target/config/opencode/commands:d"
    "/source/.config/opencode/skills:/target/config/opencode/skills:d"
    "/source/.config/opencode/modes:/target/config/opencode/modes:d"
    "/source/.config/opencode/plugins:/target/config/opencode/plugins:d"
    "/source/.config/opencode/instructions.md:/target/config/opencode/instructions.md:f"
    "/source/.local/share/opencode/auth.json:/target/local/share/opencode/auth.json:fs"
    "/source/.kimi/config.toml:/target/kimi/config.toml:fso"
    "/source/.kimi/mcp.json:/target/kimi/mcp.json:fjso"
    "/source/.pi/agent/settings.json:/target/pi/settings.json:fjo"
    "/source/.pi/agent/models.json:/target/pi/models.json:fjso"
    "/source/.pi/agent/keybindings.json:/target/pi/keybindings.json:fjo"
    "/source/.pi/agent/skills:/target/pi/skills:dxo"
    "/source/.pi/agent/extensions:/target/pi/extensions:do"
    "/source/.aider.conf.yml:/target/aider/aider.conf.yml:fso"
    "/source/.aider.model.settings.yml:/target/aider/aider.model.settings.yml:fso"
    "/source/.continue/config.yaml:/target/continue/config.yaml:fso"
    "/source/.continue/config.json:/target/continue/config.json:fjso"
    "/source/.cursor/mcp.json:/target/cursor/mcp.json:fjso"
    "/source/.cursor/rules:/target/cursor/rules:do"
    "/source/.cursor/extensions:/target/cursor/extensions:do"
)
