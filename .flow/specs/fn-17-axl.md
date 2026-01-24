# Config Sync v2

## Overview

Comprehensive overhaul of the import/sync system to support AI agent configurations, dev tools, selective syncing, import overrides, and intelligent symlink handling. Agent credentials are synced by default (opt-out available).

## Scope

**In scope:**
- Selective sync of AI agent folders (not entire dirs)
- XDG config discovery (~/.config/tmux, nvim, etc.)
- Agent credential syncing (Claude, etc.) - default ON, opt-out available
- Gitconfig filtering (strip credential.helper)
- Import overrides mechanism
- Absolute→relative symlink conversion
- User-specified additional files
- Container symlinks to data volume
- Link check/fix command
- Timestamp-based auto-fix watcher

**Out of scope:**
- Cloud CLI credentials (use .env sync instead)
- Session history, caches, analytics dirs

## What to Sync

### AI Agent Configs (Selective)

| Source | Sync | Skip |
|--------|------|------|
| **~/.claude/** | `settings.json`, `commands/`, `skills/`, `agents/`, `plugins/`, `hooks/`, `CLAUDE.md`, `.credentials.json` | `projects/`, `statsig/` |
| **~/.config/opencode/** | `opencode.json`, `agents/`, `commands/`, `skills/`, `modes/`, `plugins/`, `instructions.md` | caches |
| **~/.aider.conf.yml** | sync | — |
| **~/.aider.model.settings.yml** | sync | — |
| **~/.continue/** | `config.yaml`, `config.json` | `sessions/`, `index/` |
| **~/.cursor/** | `mcp.json`, `rules`, `extensions/` | — |
| **~/.copilot/** | `config.json`, `mcp-config.json` | — |

### Shell & Terminal

| Source | Sync |
|--------|------|
| `~/.bashrc`, `~/.bash_profile`, `~/.bash_aliases` | yes |
| `~/.zshrc`, `~/.zprofile` | yes |
| `~/.inputrc` | yes |
| `~/.tmux.conf` OR `~/.config/tmux/` | yes (XDG preferred) |
| `~/.config/starship.toml` | yes |
| `~/.config/oh-my-posh/` | yes |
| `~/.oh-my-zsh/custom/` | yes (custom only) |

### Git & SSH

| Source | Sync | Notes |
|--------|------|-------|
| `~/.gitconfig` | yes | **Strip `credential.helper` line** |
| `~/.gitignore_global` | yes | — |
| `~/.ssh/config` | yes | — |
| `~/.ssh/known_hosts` | yes | — |
| `~/.ssh/id_*` | with creds flag | Agent credentials only |

### Editors

| Source | Sync |
|--------|------|
| `~/.vimrc`, `~/.vim/` | yes |
| `~/.config/nvim/` | yes |

## Import Overrides

Users can override any imported file by placing it in:
```
~/.config/containai/import-overrides/
```

Structure maps to home directory:
```
~/.config/containai/import-overrides/
├── .gitconfig              # Overrides ~/.gitconfig
├── .claude/
│   └── settings.json       # Overrides ~/.claude/settings.json
└── .config/
    └── starship.toml       # Overrides ~/.config/starship.toml
```

**Priority:** Override file wins over source file.

## Symlink Handling

### Absolute → Relative Conversion
- If source file is an absolute symlink pointing inside $HOME
- Convert to relative symlink in destination
- Do NOT modify source files

Example:
```
Source: ~/.config/nvim -> /home/user/dotfiles/nvim  (absolute)
Import: ~/.config/nvim -> ../../dotfiles/nvim       (relative)
```

### Container Symlinks
- Create symlinks in container pointing to data volume paths
- `cai links check` - verify all links are valid
- `cai links fix` - recreate broken links

### Timestamp Watcher
- Import writes timestamp to data volume root
- Lightweight watcher in container checks timestamp
- If import newer than last fix → auto-run link fix

## Quick commands

```bash
# Test import
cai import --dry-run

# Check links in container
cai links check

# Fix broken links
cai links fix

# Import without credentials
cai import --no-credentials
```

## Acceptance

- [ ] Selective sync of ~/.claude/ (excludes projects/, statsig/)
- [ ] Selective sync of ~/.config/opencode/ (excludes caches)
- [ ] plugins/ and extensions/ directories included
- [ ] XDG configs discovered (~/.config/tmux/, nvim/, etc.)
- [ ] Agent credentials synced by default
- [ ] --no-credentials flag skips credential files
- [ ] .gitconfig synced with credential.helper stripped
- [ ] Import overrides work from ~/.config/containai/import-overrides/
- [ ] Absolute symlinks converted to relative (if inside $HOME)
- [ ] User-specified files configurable
- [ ] Container symlinks point to data volume
- [ ] `cai links check` reports link status
- [ ] `cai links fix` repairs broken links
- [ ] Timestamp watcher triggers auto-fix

## References

- Current import: `src/lib/sync.sh`
- Config parsing: `src/lib/config.sh`
- XDG spec: https://wiki.archlinux.org/title/XDG_Base_Directory
- Claude Code settings: https://docs.anthropic.com/en/docs/claude-code

## Dependencies

- **fn-16-4c9.1**: Project reorg (should complete first for clean paths)
