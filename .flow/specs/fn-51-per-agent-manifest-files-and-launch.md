# fn-51: Per-Agent Manifest Files and Launch Aliases

**Status:** draft
**Priority:** medium
**Blocked by:** none

## Problem Statement

Currently:
1. `sync-manifest.toml` is a monolithic file with all agent/tool entries mixed together
2. Agent aliases (e.g., `alias claude="claude --dangerously-skip-permissions"`) are hardcoded in Dockerfile.agents
3. No extension point for user-defined agents/tools

This creates maintenance burden and prevents users from adding their own agents without modifying core files.

## Solution Overview

Split the monolithic manifest into per-agent files and generate launch wrappers that handle:
1. Default launch parameters (yolo/autonomous mode flags)
2. User-extensible agent definitions

## Architecture

### Directory Structure

```
src/manifests/                    # Built-in agent manifests
├── claude.toml                   # Claude Code entries + launch config
├── codex.toml                    # Codex entries + launch config
├── gemini.toml                   # Gemini CLI entries + launch config
├── copilot.toml                  # Copilot entries + launch config
├── opencode.toml                 # OpenCode entries + launch config
├── kimi.toml                     # Kimi CLI entries + launch config
├── pi.toml                       # Pi entries + launch config
├── aider.toml                    # Aider entries + launch config
├── continue.toml                 # Continue entries + launch config
├── cursor.toml                   # Cursor entries + launch config
├── git.toml                      # Git config entries (no launch)
├── gh.toml                       # GitHub CLI entries + launch config
├── shell.toml                    # Shell config entries (no launch)
├── editors.toml                  # Vim/Neovim entries (no launch)
├── vscode.toml                   # VS Code Server entries (no launch)
├── ssh.toml                      # SSH entries (disabled, no launch)
└── common.toml                   # tmux, fonts, starship, etc. (no launch)

~/.config/containai/manifests/    # User-defined agent manifests (host)
/mnt/agent-data/containai/manifests/  # User manifests in container
```

### Per-Agent Manifest Format

```toml
# claude.toml
[agent]
name = "claude"
binary = "claude"                          # Command to invoke
default_args = ["--dangerously-skip-permissions"]  # Default launch params
optional = false                           # Primary agent, always synced

[[entries]]
source = ".claude.json"
target = "claude/claude.json"
container_link = ".claude.json"
flags = "fjs"

[[entries]]
source = ".claude/.credentials.json"
target = "claude/credentials.json"
container_link = ".claude/.credentials.json"
flags = "fs"

# ... more entries
```

### Launch Wrapper Behavior

For each agent with `[agent]` section, generate a shell function:

```bash
# Auto-generated in /etc/profile.d/containai-agents.sh
claude() {
    command claude --dangerously-skip-permissions "$@"
}
```

- Works in interactive shells (bashrc.d sourced)
- Works in non-interactive SSH (profile.d sourced)
- User can override by passing conflicting flags

### No Intermediate File

- Generators read directly from `src/manifests/*.toml`
- `_IMPORT_SYNC_MAP` generated from per-agent files
- `sync-manifest.toml` deleted after migration

### Runtime Hook for User Manifests

- User drops TOML in `~/.config/containai/manifests/`
- `cai import` syncs to container volume
- `containai-init.sh` (startup) detects user manifests
- Lightweight runtime generators create symlinks + wrappers
- No Dockerfile knowledge needed - just works

## Acceptance Criteria

1. Each agent/tool has its own manifest file in `src/manifests/`
2. Per-agent files include `[agent]` section with launch config
3. Generators read directly from per-agent files (no intermediate)
4. Launch functions generated in container for all agents with `[agent]` section
5. Aliases removed from Dockerfile.agents (replaced by launch functions)
6. User can add custom manifests in `~/.config/containai/manifests/`
7. `scripts/check-manifest-consistency.sh` works with new structure
8. All existing tests pass
9. Documentation updated

## Out of Scope

- Runtime editing of manifests (build-time only for now)
- Per-agent enable/disable toggles (handled by `o` flag)
- Agent installation management (remains in Dockerfile)
