# Config Sync Architecture

This document describes the config synchronization system between the host and container data volume.

## Overview

The import/sync system has three main components that must stay synchronized:
1. **Host-side sync** (`src/lib/import.sh`): Uses `_IMPORT_SYNC_MAP` to define source->target mappings for rsync
2. **Container image symlinks** (`src/container/Dockerfile.agents`): Creates build-time symlinks from home directories to `/mnt/agent-data`
3. **Runtime init** (`src/container/containai-init.sh`): Ensures volume directory structure exists on first boot

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
| `/source/.config/tmux` | `/target/config/tmux` | `d` | tmux config (directory) |
| `/source/.local/share/tmux` | `/target/local/share/tmux` | `d` | tmux data (directory) |
| `/source/.local/share/fonts` | `/target/local/share/fonts` | `d` | User fonts (directory) |
| `/source/.agents` | `/target/agents` | `d` | Common agents directory (directory) |
| `/source/.bash_aliases` | `/target/shell/bash_aliases` | `f` | Bash aliases (file) |
| `/source/.bashrc.d` | `/target/shell/bashrc.d` | `d` | Bash startup scripts (directory) |
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

### 3. containai-init.sh Directory Structure

Directories and files created on first boot:

**Directories:**
- `/mnt/agent-data/claude`
- `/mnt/agent-data/claude/plugins`
- `/mnt/agent-data/claude/skills`
- `/mnt/agent-data/config/gh`
- `/mnt/agent-data/config/opencode`
- `/mnt/agent-data/config/tmux`
- `/mnt/agent-data/local/share/tmux`
- `/mnt/agent-data/local/share/fonts`
- `/mnt/agent-data/shell`
- `/mnt/agent-data/shell/bashrc.d`
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

1. **`/mnt/agent-data/agents`** - Symlinked in Dockerfile but not created in init.sh

### Naming Inconsistencies

1. **bash_aliases** - Import uses `shell/bash_aliases`, symlink points to `~/.bash_aliases_imported` (intentional: keeps user's original `.bash_aliases` intact)

## Exclude Pattern Behavior

### Current Implementation

Excludes are currently applied globally via `EXCLUDE_DATA_B64` environment variable to each rsync invocation. This is problematic because each entry has a different source root.

For example, if the exclude pattern is `claude/plugins/.system`:
- For entry `/source/.claude/plugins:/target/claude/plugins`, rsync sees source as `/source/.claude/plugins/` so the pattern should be just `.system/`
- The global exclude would try to match `claude/plugins/.system` which doesn't match the rsync-relative path

### New Approach (v2 Design)

Excludes will be evaluated relative to the **destination path** and transported per-entry in MAP_DATA:

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
