# Config Sync Architecture

This document describes the config synchronization system between the host and container data volume.

## Overview

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {
  'primaryColor': '#1a1a2e',
  'primaryTextColor': '#ffffff',
  'primaryBorderColor': '#16213e',
  'secondaryColor': '#0f3460',
  'tertiaryColor': '#1a1a2e',
  'lineColor': '#a0a0a0',
  'textColor': '#ffffff',
  'background': '#0d1117'
}}}%%
accTitle: Config Sync Data Flow
accDescr: Shows how host configs flow via rsync to Docker volume, then appear in container via symlinks from home directories to /mnt/agent-data paths.
flowchart LR
    subgraph Host["Host System"]
        HostConfigs["~/.claude<br/>~/.config/gh<br/>~/.gitconfig"]
    end

    subgraph Sync["cai import (rsync)"]
        SyncMap["_IMPORT_SYNC_MAP"]
    end

    subgraph Volume["Docker Volume"]
        VolData["/mnt/agent-data<br/>/claude<br/>/config/gh<br/>/config/git"]
    end

    subgraph Container["Container Home"]
        Symlinks["~/.claude → /mnt/agent-data/claude<br/>~/.config/gh → /mnt/agent-data/config/gh"]
    end

    HostConfigs -->|"rsync"| SyncMap
    SyncMap -->|"to volume"| VolData
    VolData -->|"symlinks"| Symlinks

    style Host fill:#1a1a2e,stroke:#16213e,color:#fff
    style Sync fill:#0f3460,stroke:#16213e,color:#fff
    style Volume fill:#16213e,stroke:#0f3460,color:#fff
    style Container fill:#0f3460,stroke:#16213e,color:#fff
```

The import/sync system has three main components that must stay synchronized:
1. **Host-side sync** (`src/lib/import.sh`): Uses `_IMPORT_SYNC_MAP` to define source->target mappings for rsync
2. **Container image symlinks** (`src/container/Dockerfile.agents`): Creates build-time symlinks from home directories to `/mnt/agent-data`
3. **Runtime init** (`src/container/containai-init.sh`): Ensures volume directory structure exists on first boot

```mermaid
%%{init: {'theme': 'base', 'themeVariables': {
  'primaryColor': '#1a1a2e',
  'primaryTextColor': '#ffffff',
  'primaryBorderColor': '#16213e',
  'secondaryColor': '#0f3460',
  'tertiaryColor': '#1a1a2e',
  'lineColor': '#a0a0a0',
  'textColor': '#ffffff',
  'background': '#0d1117'
}}}%%
accTitle: Three-Component Sync System
accDescr: The sync system requires alignment between import.sh (host sync), Dockerfile.agents (build-time symlinks), and containai-init.sh (runtime directory creation).
flowchart TB
    subgraph Source["Single Source of Truth"]
        Manifest["sync-manifest.toml"]
    end

    subgraph Components["Generated Components"]
        Import["import.sh<br/>_IMPORT_SYNC_MAP"]
        Dockerfile["Dockerfile.agents<br/>Symlink creation"]
        Init["containai-init.sh<br/>Directory structure"]
    end

    subgraph Artifacts["Container Artifacts"]
        SymlinksScript["generated/symlinks.sh"]
        InitDirs["generated/init-dirs.sh"]
        LinkSpec["generated/link-spec.json"]
    end

    Manifest -->|"gen-dockerfile-symlinks.sh"| SymlinksScript
    Manifest -->|"gen-init-dirs.sh"| InitDirs
    Manifest -->|"gen-container-link-spec.sh"| LinkSpec
    Manifest -->|"manual sync"| Import

    SymlinksScript --> Dockerfile
    InitDirs --> Init

    style Source fill:#e94560,stroke:#16213e,color:#fff
    style Components fill:#0f3460,stroke:#16213e,color:#fff
    style Artifacts fill:#16213e,stroke:#0f3460,color:#fff
```

## Component Analysis

### 1. Import Sync Map (import.sh)

The `_IMPORT_SYNC_MAP` array defines what gets synced from host `$HOME` to the data volume.

| Source | Target | Flags | Description |
|--------|--------|-------|-------------|
| `/source/.claude.json` | `/target/claude/claude.json` | `fjs` | Claude root config (file, JSON init, secret) |
| `/source/.claude/.credentials.json` | `/target/claude/credentials.json` | `fs` | Claude credentials (file, secret) |
| `/source/.claude/settings.json` | `/target/claude/settings.json` | `fj` | Claude settings (file, JSON init) |
| `/source/.claude/settings.local.json` | `/target/claude/settings.local.json` | `f` | Claude local settings (file) |
| `/source/.claude/plugins` | `/target/claude/plugins` | `d` | Claude plugins (directory) |
| `/source/.claude/skills` | `/target/claude/skills` | `d` | Claude skills (directory) |
| `/source/.config/gh` | `/target/config/gh` | `ds` | GitHub CLI config (directory, secret) |
| `/source/.config/opencode` | `/target/config/opencode` | `d` | OpenCode config (directory) |
| `/source/.tmux.conf` | `/target/config/tmux/tmux.conf` | `f` | tmux legacy config (fallback) |
| `/source/.config/tmux` | `/target/config/tmux` | `d` | tmux XDG config (preferred) |
| `/source/.local/share/tmux` | `/target/local/share/tmux` | `d` | tmux data (directory) |
| `/source/.local/share/fonts` | `/target/local/share/fonts` | `d` | User fonts (directory) |
| `/source/.agents` | `/target/agents` | `d` | Common agents directory (directory) |
| `/source/.bash_aliases` | `/target/shell/bash_aliases` | `f` | Bash aliases (file) |
| `/source/.bashrc.d` | `/target/shell/bashrc.d` | `d` | Bash startup scripts (directory) |
| `/source/.zshrc` | `/target/shell/zshrc` | `f` | Zsh config (file) |
| `/source/.zprofile` | `/target/shell/zprofile` | `f` | Zsh profile (file) |
| `/source/.inputrc` | `/target/shell/inputrc` | `f` | Readline config (file) |
| `/source/.oh-my-zsh/custom` | `/target/shell/oh-my-zsh-custom` | `d` | Oh-My-Zsh custom plugins/themes (directory) |
| `/source/.vimrc` | `/target/editors/vimrc` | `f` | Vim config (file) |
| `/source/.vim` | `/target/editors/vim` | `d` | Vim directory (directory) |
| `/source/.config/nvim` | `/target/config/nvim` | `d` | Neovim config (directory) |
| `/source/.config/starship.toml` | `/target/config/starship.toml` | `f` | Starship prompt config (file) |
| `/source/.config/oh-my-posh` | `/target/config/oh-my-posh` | `d` | Oh-My-Posh themes (directory) |
| `/source/.vscode-server/extensions` | `/target/vscode-server/extensions` | `d` | VS Code extensions (directory) |
| `/source/.vscode-server/data/Machine` | `/target/vscode-server/data/Machine` | `d` | VS Code machine settings (directory) |
| `/source/.vscode-server/data/User/mcp` | `/target/vscode-server/data/User/mcp` | `d` | VS Code MCP config (directory) |
| `/source/.vscode-server/data/User/prompts` | `/target/vscode-server/data/User/prompts` | `d` | VS Code prompts (directory) |
| `/source/.vscode-server-insiders/extensions` | `/target/vscode-server-insiders/extensions` | `d` | VS Code Insiders extensions (directory) |
| `/source/.vscode-server-insiders/data/Machine` | `/target/vscode-server-insiders/data/Machine` | `d` | VS Code Insiders machine settings (directory) |
| `/source/.vscode-server-insiders/data/User/mcp` | `/target/vscode-server-insiders/data/User/mcp` | `d` | VS Code Insiders MCP config (directory) |
| `/source/.vscode-server-insiders/data/User/prompts` | `/target/vscode-server-insiders/data/User/prompts` | `d` | VS Code Insiders prompts (directory) |
| `/source/.copilot/config.json` | `/target/copilot/config.json` | `f` | Copilot config (file) |
| `/source/.copilot/mcp-config.json` | `/target/copilot/mcp-config.json` | `f` | Copilot MCP config (file) |
| `/source/.copilot/skills` | `/target/copilot/skills` | `d` | Copilot skills (directory) |
| `/source/.gemini/google_accounts.json` | `/target/gemini/google_accounts.json` | `fs` | Gemini accounts (file, secret) |
| `/source/.gemini/oauth_creds.json` | `/target/gemini/oauth_creds.json` | `fs` | Gemini OAuth (file, secret) |
| `/source/.gemini/settings.json` | `/target/gemini/settings.json` | `fj` | Gemini settings (file, JSON init) |
| `/source/.gemini/GEMINI.md` | `/target/gemini/GEMINI.md` | `f` | Gemini instructions (file) |
| `/source/.codex/config.toml` | `/target/codex/config.toml` | `f` | Codex config (file) |
| `/source/.codex/auth.json` | `/target/codex/auth.json` | `fs` | Codex auth (file, secret) |
| `/source/.codex/skills` | `/target/codex/skills` | `dx` | Codex skills (directory, exclude .system/) |
| `/source/.local/share/opencode/auth.json` | `/target/local/share/opencode/auth.json` | `fs` | OpenCode auth (file, secret) |

**Flags:**
- `d` = directory
- `f` = file
- `j` = initialize JSON with `{}` if empty
- `m` = mirror mode (`--delete` to remove files not in source)
- `s` = secret (600 for files, 700 for dirs)
- `x` = exclude `.system/` subdirectory

### 2. Dockerfile.agents Symlinks

Symlinks created in the container image pointing to `/mnt/agent-data`:

| Container Path | Volume Target | Notes |
|----------------|---------------|-------|
| `~/.claude/.credentials.json` | `/mnt/agent-data/claude/credentials.json` | |
| `~/.claude.json` | `/mnt/agent-data/claude/claude.json` | Root-level file |
| `~/.claude/settings.json` | `/mnt/agent-data/claude/settings.json` | |
| `~/.claude/plugins` | `/mnt/agent-data/claude/plugins` | Directory symlink |
| `~/.claude/skills` | `/mnt/agent-data/claude/skills` | Directory symlink |
| `~/.copilot/config.json` | `/mnt/agent-data/copilot/config.json` | |
| `~/.copilot/mcp-config.json` | `/mnt/agent-data/copilot/mcp-config.json` | |
| `~/.copilot/skills` | `/mnt/agent-data/copilot/skills` | Uses rm -rf first |
| `~/.gemini/google_accounts.json` | `/mnt/agent-data/gemini/google_accounts.json` | |
| `~/.gemini/oauth_creds.json` | `/mnt/agent-data/gemini/oauth_creds.json` | |
| `~/.gemini/settings.json` | `/mnt/agent-data/gemini/settings.json` | |
| `~/.gemini/GEMINI.md` | `/mnt/agent-data/gemini/GEMINI.md` | |
| `~/.codex/auth.json` | `/mnt/agent-data/codex/auth.json` | |
| `~/.codex/config.toml` | `/mnt/agent-data/codex/config.toml` | |
| `~/.codex/skills` | `/mnt/agent-data/codex/skills` | Uses rm -rf first |
| `~/.local/share/opencode/auth.json` | `/mnt/agent-data/local/share/opencode/auth.json` | |
| `~/.vscode-server/data/Machine/settings.json` | `/mnt/agent-data/vscode-server/data/Machine/settings.json` | |
| `~/.vscode-server/extensions` | `/mnt/agent-data/vscode-server/extensions` | Directory symlink |
| `~/.vscode-server/data/User/mcp.json` | `/mnt/agent-data/vscode-server/data/User/mcp.json` | |
| `~/.vscode-server/data/User/prompts` | `/mnt/agent-data/vscode-server/data/User/prompts` | Directory symlink |
| `~/.vscode-server/data/User/mcp` | `/mnt/agent-data/vscode-server/data/User/mcp` | Directory symlink |
| `~/.vscode-server-insiders/data/Machine/settings.json` | `/mnt/agent-data/vscode-server-insiders/data/Machine/settings.json` | |
| `~/.vscode-server-insiders/extensions` | `/mnt/agent-data/vscode-server-insiders/extensions` | Directory symlink |
| `~/.vscode-server-insiders/data/User/mcp.json` | `/mnt/agent-data/vscode-server-insiders/data/User/mcp.json` | |
| `~/.vscode-server-insiders/data/User/prompts` | `/mnt/agent-data/vscode-server-insiders/data/User/prompts` | Directory symlink |
| `~/.vscode-server-insiders/data/User/mcp` | `/mnt/agent-data/vscode-server-insiders/data/User/mcp` | Directory symlink |
| `~/.config/gh` | `/mnt/agent-data/config/gh` | Directory symlink |
| `~/.config/opencode` | `/mnt/agent-data/config/opencode` | Directory symlink |
| `~/.config/tmux` | `/mnt/agent-data/config/tmux` | Directory symlink |
| `~/.local/share/tmux` | `/mnt/agent-data/local/share/tmux` | Directory symlink |
| `~/.local/share/fonts` | `/mnt/agent-data/local/share/fonts` | Directory symlink |
| `~/.agents` | `/mnt/agent-data/agents` | Directory symlink |
| `~/.bash_aliases_imported` | `/mnt/agent-data/shell/bash_aliases` | Note: different name |
| `~/.zshrc` | `/mnt/agent-data/shell/zshrc` | Zsh config |
| `~/.zprofile` | `/mnt/agent-data/shell/zprofile` | Zsh profile |
| `~/.inputrc` | `/mnt/agent-data/shell/inputrc` | Readline config |
| `~/.oh-my-zsh/custom` | `/mnt/agent-data/shell/oh-my-zsh-custom` | Uses rm -rf first |
| `~/.vimrc` | `/mnt/agent-data/editors/vimrc` | Vim config |
| `~/.vim` | `/mnt/agent-data/editors/vim` | Uses rm -rf first |
| `~/.config/nvim` | `/mnt/agent-data/config/nvim` | Uses rm -rf first |
| `~/.config/starship.toml` | `/mnt/agent-data/config/starship.toml` | Starship prompt |
| `~/.config/oh-my-posh` | `/mnt/agent-data/config/oh-my-posh` | Oh-My-Posh themes |

### 3. containai-init.sh Directory Structure

Directories and files created on first boot:

**Directories:**
- `/mnt/agent-data/claude`
- `/mnt/agent-data/claude/plugins`
- `/mnt/agent-data/claude/skills`
- `/mnt/agent-data/config/gh`
- `/mnt/agent-data/config/opencode`
- `/mnt/agent-data/config/tmux`
- `/mnt/agent-data/config/nvim`
- `/mnt/agent-data/config/oh-my-posh`
- `/mnt/agent-data/local/share/tmux`
- `/mnt/agent-data/local/share/fonts`
- `/mnt/agent-data/shell`
- `/mnt/agent-data/shell/bashrc.d`
- `/mnt/agent-data/shell/oh-my-zsh-custom`
- `/mnt/agent-data/editors`
- `/mnt/agent-data/editors/vim`
- `/mnt/agent-data/vscode-server/extensions`
- `/mnt/agent-data/vscode-server/data/Machine`
- `/mnt/agent-data/vscode-server/data/User/mcp`
- `/mnt/agent-data/vscode-server/data/User/prompts`
- `/mnt/agent-data/vscode-server-insiders/extensions`
- `/mnt/agent-data/vscode-server-insiders/data/Machine`
- `/mnt/agent-data/vscode-server-insiders/data/User/mcp`
- `/mnt/agent-data/vscode-server-insiders/data/User/prompts`
- `/mnt/agent-data/copilot/skills`
- `/mnt/agent-data/gemini`
- `/mnt/agent-data/codex/skills`
- `/mnt/agent-data/local/share/opencode`

**Files (with JSON init):**
- `/mnt/agent-data/claude/claude.json` (JSON)
- `/mnt/agent-data/claude/credentials.json` (JSON)
- `/mnt/agent-data/claude/settings.json` (JSON)
- `/mnt/agent-data/vscode-server/data/Machine/settings.json` (JSON)
- `/mnt/agent-data/vscode-server/data/User/mcp.json` (JSON)
- `/mnt/agent-data/vscode-server-insiders/data/Machine/settings.json` (JSON)
- `/mnt/agent-data/vscode-server-insiders/data/User/mcp.json` (JSON)
- `/mnt/agent-data/gemini/settings.json` (JSON)

**Files (plain):**
- `/mnt/agent-data/claude/settings.local.json`
- `/mnt/agent-data/shell/bash_aliases`
- `/mnt/agent-data/shell/zshrc`
- `/mnt/agent-data/shell/zprofile`
- `/mnt/agent-data/shell/inputrc`
- `/mnt/agent-data/config/starship.toml`
- `/mnt/agent-data/editors/vimrc`
- `/mnt/agent-data/copilot/config.json`
- `/mnt/agent-data/copilot/mcp-config.json`
- `/mnt/agent-data/gemini/google_accounts.json`
- `/mnt/agent-data/gemini/oauth_creds.json`
- `/mnt/agent-data/gemini/GEMINI.md`
- `/mnt/agent-data/codex/config.toml`
- `/mnt/agent-data/codex/auth.json`
- `/mnt/agent-data/local/share/opencode/auth.json`

**Secret permissions (chmod 600/700):**
- `/mnt/agent-data/claude/claude.json` (600)
- `/mnt/agent-data/claude/credentials.json` (600)
- `/mnt/agent-data/gemini/google_accounts.json` (600)
- `/mnt/agent-data/gemini/oauth_creds.json` (600)
- `/mnt/agent-data/codex/auth.json` (600)
- `/mnt/agent-data/local/share/opencode/auth.json` (600)
- `/mnt/agent-data/config/gh` (700)

## Identified Mismatches

### Missing from Import (synced but not imported from host)

1. **VS Code mcp.json files** - Dockerfile creates symlinks for `/mnt/agent-data/vscode-server/data/User/mcp.json` but import.sh only syncs the `mcp/` directory, not the `mcp.json` file

### Missing from Dockerfile (imported but no symlink)

1. **`~/.claude/settings.local.json`** - Imported to volume but no symlink in Dockerfile
2. **`~/.bashrc.d`** - Imported to `shell/bashrc.d` but linked differently (sourced via .bashrc hook, not symlinked directly)

### Missing from containai-init.sh (symlinked but not created)

None - all symlinked paths are now created in containai-init.sh.

### Naming Inconsistencies

1. **bash_aliases** - Import uses `shell/bash_aliases`, symlink points to `~/.bash_aliases_imported` (intentional: keeps user's original `.bash_aliases` intact)

## XDG Config Preference

For tools that support both legacy and XDG config locations, ContainAI prefers the XDG location:

| Tool | Legacy Location | XDG Location | Behavior |
|------|-----------------|--------------|----------|
| tmux | `~/.tmux.conf` | `~/.config/tmux/` | Both synced; XDG preferred |

**tmux precedence:** The legacy `~/.tmux.conf` is synced first to `/target/config/tmux/tmux.conf`, then the XDG `~/.config/tmux/` directory is synced over it. This ensures:
- If only legacy exists: it becomes available at the XDG location in the container
- If only XDG exists: it is used directly
- If both exist: XDG wins (overwrites the legacy file)

## Exclude Pattern Behavior

### Implementation

Excludes are evaluated relative to the **destination path** and transported per-entry in MAP_DATA:

```
source:target:flags:excludes_b64
```

**Pattern Classification:**
1. **No-slash WITH glob metacharacters** (`*.log`, `*.tmp`): Global globs applied to all entries
2. **No-slash WITHOUT glob metacharacters** (`claude`, `config`): Root prefixes that skip matching entries
3. **Path patterns** (`claude/plugins/.system`): Bidirectional parent/child matching

## References

- Import implementation: `src/lib/import.sh`
- Container symlinks: `src/container/Dockerfile.agents`
- Runtime init: `src/container/containai-init.sh`
- Sync manifest: `src/sync-manifest.toml` (single source of truth)
