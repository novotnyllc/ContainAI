# fn-17-axl.2 XDG config discovery for dev tools

## Description

Add automatic discovery of XDG-compliant config directories for dev tools that aren't currently synced.

**Tools to add:**
- `~/.config/tmux/` (already partially supported via `~/.tmux.conf`)
- `~/.config/nvim/` (neovim config)
- `~/.config/starship.toml` (prompt customization)
- `~/.config/oh-my-posh/` (prompt themes)
- `~/.oh-my-zsh/custom/` (custom zsh plugins/themes only)
- `~/.vimrc`, `~/.vim/` (vim config)
- `~/.inputrc` (readline config)
- `~/.zshrc`, `~/.zprofile` (zsh config)

**Implementation:**
1. Add entries to sync manifest (designed in fn-17-axl.1)
2. Update `_IMPORT_SYNC_MAP` in `src/lib/import.sh`
3. Add corresponding symlinks to Dockerfile.agents
4. Update containai-init.sh to create required directories

**XDG precedence:**
- If both `~/.tmux.conf` and `~/.config/tmux/tmux.conf` exist, prefer XDG location
- Document this in docs/configuration.md

## Acceptance

- [ ] nvim config synced from `~/.config/nvim/`
- [ ] starship config synced from `~/.config/starship.toml`
- [ ] oh-my-posh themes synced from `~/.config/oh-my-posh/`
- [ ] oh-my-zsh custom dir synced from `~/.oh-my-zsh/custom/`
- [ ] vim config synced from `~/.vimrc` and `~/.vim/`
- [ ] inputrc synced from `~/.inputrc`
- [ ] zsh configs synced from `~/.zshrc`, `~/.zprofile`
- [ ] XDG tmux preferred over legacy location
- [ ] All entries in sync manifest
- [ ] `cai import --dry-run` shows new paths
- [ ] Container can use imported configs after `cai import`

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
