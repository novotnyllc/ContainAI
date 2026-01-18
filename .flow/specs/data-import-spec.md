# Sync-Agent-Plugins Refactoring Specification

## Overview

Refactor `sync-agent-plugins.sh` to use a declarative rsync-based approach for syncing portable configuration files from host to Docker volume.

**Important constraints:**
- **Linux only** - macOS has different config locations; block with error on macOS (future work)
- **Sync is optional** - entrypoint.sh MUST also ensure all target files/dirs exist since sync may not be run

---

## Architecture

### Single Configuration Map

All sync items defined in one array. For each entry:
1. Target is ALWAYS created first (empty file/dir)
2. Then source is copied if it exists (overwrites empty target)

The `:j` flag initializes JSON files with `{}` when created empty.

```bash
# Format: "source:target:flags"
# Flags: d=directory, f=file, j=initialize with {} if empty

SYNC_MAP=(
  # ─── Claude Code ───
  # Note: target files are NOT dot-prefixed for visibility in volume
  "/source/.claude.json:/target/claude/claude.json:fj"
  "/source/.claude/.credentials.json:/target/claude/credentials.json:f"
  "/source/.claude/settings.json:/target/claude/settings.json:fj"
  "/source/.claude/settings.local.json:/target/claude/settings.local.json:f"
  "/source/.claude/plugins:/target/claude/plugins:d"
  "/source/.claude/skills:/target/claude/skills:d"

  # ─── GitHub CLI ───
  # Note: ~/.config/gh/ already covered by config symlink
  "/source/.config/gh:/target/config/gh:d"

  # ─── OpenCode ───
  # Config: ~/.config/opencode/ already covered by config symlink
  "/source/.config/opencode:/target/config/opencode:d"
  "/source/.local/share/opencode:/target/local/share/opencode:d"

  # ─── tmux ───
  # Supports both legacy (~/.tmux.conf) and XDG (~/.config/tmux/)
  "/source/.tmux.conf:/target/tmux/.tmux.conf:f"
  "/source/.tmux:/target/tmux/.tmux:d"
  "/source/.config/tmux:/target/config/tmux:d"

  # ─── Shell ───
  "/source/.bash_aliases:/target/shell/.bash_aliases:f"
  "/source/.bashrc.d:/target/shell/.bashrc.d:d"

  # ─── VS Code Server ───
  "/source/.vscode-server/extensions:/target/vscode-server/extensions:d"
  "/source/.vscode-server/data/Machine:/target/vscode-server/data/Machine:d"
  "/source/.vscode-server/data/User/mcp:/target/vscode-server/data/User/mcp:d"
  "/source/.vscode-server/data/User/prompts:/target/vscode-server/data/User/prompts:d"
  "/source/.vscode-server/data/Machine/settings.json:/target/vscode-server/data/Machine/settings.json:f"
  "/source/.vscode-server/data/User/mcp.json:/target/vscode-server/data/User/mcp.json:f"

  # ─── VS Code Insiders ───
  "/source/.vscode-server-insiders/extensions:/target/vscode-server-insiders/extensions:d"
  "/source/.vscode-server-insiders/data/Machine:/target/vscode-server-insiders/data/Machine:d"
  "/source/.vscode-server-insiders/data/User/mcp:/target/vscode-server-insiders/data/User/mcp:d"
  "/source/.vscode-server-insiders/data/User/prompts:/target/vscode-server-insiders/data/User/prompts:d"
  "/source/.vscode-server-insiders/data/Machine/settings.json:/target/vscode-server-insiders/data/Machine/settings.json:f"
  "/source/.vscode-server-insiders/data/User/mcp.json:/target/vscode-server-insiders/data/User/mcp.json:f"

  # ─── Copilot ───
  "/source/.copilot:/target/copilot:d"
  "/source/.copilot/config.json:/target/copilot/config.json:f"

  # ─── Gemini ───
  "/source/.gemini:/target/gemini:d"
  "/source/.gemini/settings.json:/target/gemini/settings.json:fj"
  "/source/.gemini/google_accounts.json:/target/gemini/google_accounts.json:f"
  "/source/.gemini/oauth_creds.json:/target/gemini/oauth_creds.json:f"

  # ─── Codex ───
  "/source/.codex:/target/codex:d"
  "/source/.codex/skills:/target/codex/skills:d"
  "/source/.codex/auth.json:/target/codex/auth.json:f"
  "/source/.codex/config.toml:/target/codex/config.toml:f"

)
```

### Rsync-Based Sync Function

```bash
sync_configs() {
  docker run --rm \
    --mount type=bind,src="$HOME",dst=/source,readonly \
    --mount type=volume,src="$DATA_VOLUME",dst=/target \
    eeacms/rsync sh -ec '
      ensure() {
        path="$1"; flags="$2"
        case "$flags" in
          *d*) mkdir -p "$path" ;;
          *f*) mkdir -p "$(dirname "$path")"; touch "$path" ;;
        esac
        # Initialize JSON with {} if empty and flagged
        case "$flags" in
          *j*) [ -s "$path" ] || echo "{}" > "$path" ;;
        esac
      }

      copy() {
        src="$1"; dst="$2"; flags="$3"
        # Always ensure target exists first
        ensure "$dst" "$flags"
        # Then copy from source if it exists (overwrites empty target)
        [ -e "$src" ] && rsync -a "$src" "$(dirname "$dst")/"
      }

      '"$(for entry in "${SYNC_MAP[@]}"; do
        src="${entry%%:*}"
        rest="${entry#*:}"
        dst="${rest%%:*}"
        flags="${rest#*:}"
        printf 'copy %q %q %q\n' "$src" "$dst" "$flags"
      done)"'

      chown -R 1000:1000 /target
    '
}
```

---

## File Inventory

### Claude Code
| Host | Volume | Notes |
|------|--------|-------|
| `~/.claude.json` | `/mnt/agent-data/claude/claude.json` | JSON init, no dot prefix in volume |
| `~/.claude/.credentials.json` | `/mnt/agent-data/claude/credentials.json` | no dot prefix in volume |
| `~/.claude/settings.json` | `/mnt/agent-data/claude/settings.json` | JSON init |
| `~/.claude/settings.local.json` | `/mnt/agent-data/claude/settings.local.json` | optional |
| `~/.claude/plugins/` | `/mnt/agent-data/claude/plugins/` | cache/, marketplaces/ |
| `~/.claude/skills/` | `/mnt/agent-data/claude/skills/` | |

**Post-sync transforms (keep existing):**
- `installed_plugins.json`: Path rewrite + scope change
- `known_marketplaces.json`: Path rewrite

### GitHub CLI
| Host | Volume | Notes |
|------|--------|-------|
| `~/.config/gh/` | `/mnt/agent-data/config/gh/` | config.yml, hosts.yml |

### OpenCode
| Host | Volume | Notes |
|------|--------|-------|
| `~/.config/opencode/` | `/mnt/agent-data/config/opencode/` | opencode.json, agent/, command/, plugin/ |
| `~/.local/share/opencode/` | `/mnt/agent-data/local/share/opencode/` | auth.json |

### tmux
| Host | Volume | Notes |
|------|--------|-------|
| `~/.tmux.conf` | `/mnt/agent-data/tmux/.tmux.conf` | legacy location |
| `~/.tmux/` | `/mnt/agent-data/tmux/.tmux/` | TPM plugins |
| `~/.config/tmux/` | `/mnt/agent-data/config/tmux/` | XDG location |

### Shell
| Host | Volume | Notes |
|------|--------|-------|
| `~/.bash_aliases` | `/mnt/agent-data/shell/.bash_aliases` | |
| `~/.bashrc.d/` | `/mnt/agent-data/shell/.bashrc.d/` | |

---

## Dockerfile Changes

Add symlinks for new tools (after line 224):

```dockerfile
    # tmux (legacy location)
    && mkdir -p /mnt/agent-data/tmux \
    && ln -s /mnt/agent-data/tmux/.tmux.conf ${HOME}/.tmux.conf \
    && ln -s /mnt/agent-data/tmux/.tmux ${HOME}/.tmux \
    \
    # Shell configs
    && mkdir -p /mnt/agent-data/shell \
    && ln -s /mnt/agent-data/shell/.bash_aliases ${HOME}/.bash_aliases_imported \
    && ln -s /mnt/agent-data/shell/.bashrc.d ${HOME}/.bashrc.d \
    \
    # OpenCode data (XDG_DATA_HOME)
    && mkdir -p /mnt/agent-data/local/share \
    && ln -s /mnt/agent-data/local/share ${HOME}/.local/share
```

Note: `~/.config/gh`, `~/.config/opencode`, `~/.config/tmux` are already covered by the existing `~/.config` → `/mnt/agent-data/config` symlink.

---

## Files to Modify

| File | Changes |
|------|---------|
| [agent-sandbox/sync-agent-plugins.sh](agent-sandbox/sync-agent-plugins.sh) | Replace with SYNC_MAP + rsync pattern; add Linux-only guard |
| [agent-sandbox/Dockerfile](agent-sandbox/Dockerfile) | Add symlinks for tmux, shell, ~/.local/share |
| [agent-sandbox/entrypoint.sh](agent-sandbox/entrypoint.sh) | MUST ensure ALL target files/dirs exist (sync is optional) |

---

## Verification

```bash
# Dry run
sync-agent-plugins.sh --dry-run

# Inspect volume
docker run --rm -v sandbox-agent-data:/data alpine ls -laR /data

# Test in container
gh auth status
opencode --version
tmux  # should load config
```
