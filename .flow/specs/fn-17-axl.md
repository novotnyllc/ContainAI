# Config Sync v2

## Overview

Comprehensive overhaul of the import/sync system to support AI agent configurations, dev tools, selective syncing, import overrides, and intelligent symlink handling. Agent secrets (OAuth tokens) are synced by default (opt-out available).

## Background: Current Architecture

The import system has three main components:
1. **Host-side sync** (`src/lib/import.sh`): Uses `_IMPORT_SYNC_MAP` to define source→target mappings for rsync
2. **Container image symlinks** (`src/container/Dockerfile.agents`): Creates build-time symlinks from home directories to `/mnt/agent-data`
3. **Runtime init** (`src/container/containai-init.sh`): Ensures volume directory structure exists on first boot

**Key insight**: These components must stay synchronized. This epic introduces a shared manifest approach.

## Scope

**In scope:**
- Selective sync of AI agent folders (not entire dirs)
- XDG config discovery (~/.config/tmux, nvim, etc.)
- Agent secret syncing (OAuth tokens, API keys) - default ON, opt-out available
- Gitconfig filtering (strip credential.helper)
- Import overrides mechanism
- Absolute→relative symlink conversion (mountpoint-agnostic)
- User-specified additional files
- Container symlinks via manifest-driven approach
- Link check/fix command
- Timestamp-based auto-fix watcher

**Out of scope:**
- Cloud CLI credentials (AWS/GCP/Azure - use .env sync instead)
- Session history, caches, analytics dirs

## Terminology

To avoid confusion with existing concepts:
- **Agent secrets**: OAuth tokens, API keys, credentials stored in agent config files (e.g., `.claude/.credentials.json`, `.codex/auth.json`)
- **Host credentials**: Live access to host credential stores via bind mounts (existing `--credentials=host` flag, blocked from config)
- **Import overrides**: User-provided files that replace (not merge with) imported defaults

The existing `--credentials` flag for host credential mounting is unchanged. The new `--no-secrets` flag controls agent secret file import.

## What to Sync

### AI Agent Configs (Selective)

| Source | Sync | Skip |
|--------|------|------|
| **~/.claude/** | `settings.json`, `settings.local.json`, `commands/`, `skills/`, `agents/`, `plugins/`, `hooks/`, `CLAUDE.md`, `.credentials.json` | `projects/`, `statsig/`, `todos/` |
| **~/.config/opencode/** | `opencode.json`, `agents/`, `commands/`, `skills/`, `modes/`, `plugins/`, `instructions.md` | caches |
| **~/.aider.conf.yml** | sync | — |
| **~/.aider.model.settings.yml** | sync | — |
| **~/.continue/** | `config.yaml`, `config.json` | `sessions/`, `index/` |
| **~/.cursor/** | `mcp.json`, `rules`, `extensions/` | — |
| **~/.copilot/** | `config.json`, `mcp-config.json`, `skills/` | `logs/`, `command-history-state.json` |

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
| `~/.gitconfig` | yes | **Strip `credential.helper` lines** |
| `~/.gitignore_global` | yes | — |
| `~/.ssh/config` | yes | — |
| `~/.ssh/known_hosts` | yes | — |
| `~/.ssh/id_*` | with secrets flag | SSH keys are agent secrets |

### Editors

| Source | Sync |
|--------|------|
| `~/.vimrc`, `~/.vim/` | yes |
| `~/.config/nvim/` | yes |

### GitHub CLI (Clarification)

GitHub CLI (`~/.config/gh`) is explicitly **in scope** because it's required for agent git workflows. This is distinct from "cloud CLI credentials" (AWS/GCP/Azure) which remain out of scope.

## Import Overrides

Users can override any imported file by placing files in:
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

**Rules:**
- Override file wins over source file (complete replacement, no merge)
- Only regular files and directories allowed (no symlinks, no `..` traversal)
- Overrides cannot delete files (only replace)
- Override paths are validated against path traversal attacks
- Override directory is scanned after main import, applied via rsync with higher priority

## Symlink Handling

### Absolute → Relative Conversion

**Key insight:** Volume structure does NOT mirror $HOME (e.g., `~/.config/gh` → `/target/config/gh`). Symlink resolution must use the manifest with longest-prefix matching.

**Rules:**
- If source symlink points inside $HOME with absolute path AND target is in manifest → convert to relative
- If symlink target is outside $HOME → preserve original absolute, log warning
- If symlink target is not in manifest (not imported) → preserve original absolute, log warning
- Do NOT modify source files

**Algorithm:** Look up symlink target in manifest using longest-prefix match to find destination path, compute relative path from link location to target location using directory depth counting.

Example:
```
Source: ~/.config/nvim -> /home/user/dotfiles/nvim  (absolute)
Manifest lookup: dotfiles/nvim -> /target/dotfiles/nvim
Link at: /target/config/nvim (depth=1)
Result: /target/config/nvim -> ../dotfiles/nvim  (relative)
```

### Container Symlinks via Manifest

**Architecture note:** Container symlinks live in the container filesystem (created via Dockerfile), NOT in the data volume. They point INTO the data volume at `/mnt/agent-data/`.

**R flag for safe symlink creation:** When creating directory symlinks, if the destination already exists as a directory, `ln -sfn` creates a nested symlink inside it. The manifest `R` flag indicates "remove existing path first" (rm -rf before ln -sfn).

**Components:**
- `src/sync-manifest.toml` - Single source of truth for all entries
- `src/scripts/gen-*.sh` - Generators read manifest, produce build artifacts
- `src/container/generated/` - Generated files (gitignored)
- `/usr/local/lib/containai/link-spec.json` - Shipped in image for container-side check/fix
- `/usr/local/lib/containai/link-repair.sh` - Container-side repair script

**Commands:**
- `cai links check` - verify symlinks match link-spec.json
- `cai links fix` - recreate broken/missing symlinks (requires running/stopped container)

### Timestamp Watcher

**Timestamp files (in volume root):**
- `/.containai-imported-at` - Written by `cai import` on completion (to `/target/` during import)
- `/.containai-links-checked-at` - Written by link-repair.sh after ANY successful run

**Watcher behavior:**
- Polls every 60 seconds
- Compares: if imported > checked → run repair
- **Updates `/.containai-links-checked-at` after ANY successful repair run** (even if no changes needed)
- This prevents infinite loops when links are already correct

## Exclude Semantics

**Current problem**: Excludes are applied per-rsync-invocation where each has a different source root, causing inconsistent pattern matching.

**New approach**: Excludes are evaluated relative to the **destination path** and transported per-entry in MAP_DATA (not as a global env var).

**Pattern classification:**
- No-slash WITH glob metacharacters (`*.log`): Global globs, apply to all entries
- No-slash WITHOUT glob metacharacters (`claude`): Root prefixes, skip matching entries
- Path patterns (`claude/plugins/.system`): Bidirectional parent/child matching

See fn-17-axl.1 for detailed algorithm.

## Task Dependency Flow

```
fn-17-axl.1 (manifest + excludes)
    ├── fn-17-axl.2 (XDG discovery)
    ├── fn-17-axl.3 (selective sync) ─┐
    ├── fn-17-axl.4 (--no-secrets)    │
    ├── fn-17-axl.5 (gitconfig)       │
    ├── fn-17-axl.6 (overrides) ──────┼── fn-17-axl.9 (generators)
    ├── fn-17-axl.7 (symlinks) ───────┘       │
    └── fn-17-axl.8 (user files)              │
                                              ▼
                                     fn-17-axl.10 (links check/fix)
                                              │
                                              ▼
                                     fn-17-axl.11 (watcher)

fn-17-axl.12 (OAuth investigation) - independent
```

## Quick Commands

```bash
# Test import
cai import --dry-run

# Check links in container
cai links check

# Fix broken links
cai links fix

# Import without agent secrets
cai import --no-secrets

# List what would be synced
cai import --list
```

## Acceptance Criteria

- [ ] Selective sync of ~/.claude/ (excludes projects/, statsig/, todos/)
- [ ] Selective sync of ~/.config/opencode/ (excludes caches)
- [ ] plugins/ and extensions/ directories included
- [ ] XDG configs discovered (~/.config/tmux/, nvim/, etc.)
- [ ] Agent secrets synced by default
- [ ] --no-secrets flag skips credential/auth files
- [ ] .gitconfig synced with credential.helper stripped
- [ ] Import overrides work from ~/.config/containai/import-overrides/
- [ ] Override path validation (no symlinks, no traversal)
- [ ] Absolute symlinks converted to relative via manifest lookup (longest-prefix)
- [ ] Symlinks outside imported set preserved with warning
- [ ] User-specified files configurable via TOML
- [ ] Shared sync manifest drives import + image build + init
- [ ] Container symlinks match manifest (R flag for safe creation)
- [ ] `cai links check` reports link status against manifest
- [ ] `cai links fix` repairs broken links (running/stopped container)
- [ ] Timestamp watcher uses `/.containai-links-checked-at` (updated on ALL successful runs)
- [ ] Exclude patterns evaluated destination-relative with per-entry transport

## References

- Current import: `src/lib/import.sh` (`_IMPORT_SYNC_MAP`)
- Container symlinks: `src/container/Dockerfile.agents`
- Runtime init: `src/container/containai-init.sh`
- Config parsing: `src/lib/config.sh`
- XDG spec: https://wiki.archlinux.org/title/XDG_Base_Directory
- Claude Code settings: https://docs.anthropic.com/en/docs/claude-code

## Dependencies

- **fn-16-4c9.1**: Project reorg (should complete first for clean paths)
