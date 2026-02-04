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
src/manifests/                    # Built-in agent manifests (numbered for ordering)
├── 00-common.toml                # Fonts, agents directory (no launch)
├── 01-shell.toml                 # Shell config entries (no launch)
├── 02-git.toml                   # Git config entries (no launch)
├── 03-gh.toml                    # GitHub CLI entries (no launch, no wrapper)
├── 04-editors.toml               # Vim/Neovim entries (no launch)
├── 05-vscode.toml                # VS Code Server + container symlinks (no launch)
├── 06-ssh.toml                   # SSH entries (disabled, no launch)
├── 07-tmux.toml                  # tmux entries (no launch)
├── 08-prompt.toml                # Starship/oh-my-posh (no launch)
├── 10-claude.toml                # Claude Code entries + launch config
├── 11-codex.toml                 # Codex entries + launch config
├── 12-gemini.toml                # Gemini CLI entries + launch config (optional)
├── 13-copilot.toml               # Copilot entries + launch config (optional)
├── 14-opencode.toml              # OpenCode entries (no wrapper - no autonomous flag)
├── 15-kimi.toml                  # Kimi CLI entries + launch config (optional, includes kimi-cli alias)
├── 16-pi.toml                    # Pi entries + launch config (optional)
├── 17-aider.toml                 # Aider entries (optional, check for autonomous flag)
├── 18-continue.toml              # Continue entries (optional, no launch)
└── 19-cursor.toml                # Cursor entries (optional, no launch)

~/.config/containai/manifests/    # User-defined agent manifests (host)
/mnt/agent-data/containai/manifests/  # User manifests in container
```

**Ordering:** Numeric prefixes ensure deterministic processing order matching the original monolithic manifest section order. Generators iterate `src/manifests/*.toml` in sorted order.

### Per-Agent Manifest Format

```toml
# 10-claude.toml
[agent]
name = "claude"
binary = "claude"                          # Command to invoke
default_args = ["--dangerously-skip-permissions"]  # Wrapper only generated if non-empty
aliases = []                               # Additional command aliases (optional)
optional = false                           # If true, wrapper wrapped in command -v check

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

**Schema notes:**
- `default_args`: Array of default arguments. Wrappers are ONLY generated when this is non-empty.
- `aliases`: Optional array of additional command names that should also get wrapper functions (e.g., `aliases = ["kimi-cli"]` for kimi.toml).
- `optional`: If true, wrapper generation is guarded by `command -v` check (safe if binary not installed). Defaults to false.
- Entry flags include `o` for optional (skip if host source doesn't exist during import).
- `[[container_symlinks]]`: Goes in the manifest file that owns those symlinks (e.g., vscode symlinks go in `05-vscode.toml`).

**Note:** The `[agent]` section is ONLY for agents that need launch wrappers. Manifests for config-only tools (editors, shell, vscode, gh, opencode) do NOT include `[agent]` sections.

### Launch Wrapper Behavior

For each agent with `[agent]` section AND non-empty `default_args`, generate shell functions:

```bash
# Auto-generated in /home/agent/.bash_env.d/containai-agents.sh
# (sourced from .bash_env for non-interactive, and from .bashrc for interactive)

# Required agents (optional = false)
claude() {
    command claude --dangerously-skip-permissions "$@"
}

# Optional agents (optional = true) - guarded
if command -v gemini >/dev/null 2>&1; then
gemini() {
    command gemini --yolo "$@"
}
fi
```

**Critical: Shell sourcing chain**
- Non-interactive SSH (`ssh container 'command'`): `BASH_ENV=/home/agent/.bash_env` → sources `.bash_env.d/*.sh`
- Interactive non-login: `.bashrc` → sources `.bash_env` → sources `.bash_env.d/*.sh`
- Login shell: `.bash_profile` → sources `.bashrc` → same chain

The `.bashrc` must be updated to source `.bash_env` (or `.bash_env.d/` directly) to ensure interactive shells get wrappers.

### TOML Parsing Approach

The existing `parse-manifest.sh` uses regex and cannot handle arrays or full TOML syntax. For `[agent]` section parsing:
- Extend `src/parse-toml.py` (uses tomllib/tomli) to emit agent sections
- Validation includes: proper TOML syntax, required fields present, flag characters valid
- Bash generators consume JSON output from Python parser for agent fields

### Import Map Generation

A new generator script creates `_IMPORT_SYNC_MAP` from per-agent manifests:
- `src/scripts/gen-import-map.sh` reads all manifests and outputs indexed array (same format as today)
- Output replaces the hardcoded `_IMPORT_SYNC_MAP` in `src/lib/import.sh`
- `check-manifest-consistency.sh` verifies generated map matches manifest entries

### User Manifests Runtime Hook

- User drops TOML in `~/.config/containai/manifests/`
- `cai import` syncs to container volume at `/mnt/agent-data/containai/manifests/`
- `containai-init.sh` (startup) detects user manifests and runs runtime generators
- Runtime generators create symlinks + wrappers for user-defined agents
- No Dockerfile rebuild needed - just restart container

**Runtime generators installed in image:**
- `/usr/local/lib/containai/gen-user-links.sh` - creates user symlinks with validation
- `/usr/local/lib/containai/gen-user-wrappers.sh` - creates user launch wrappers
- These are copied into the image during build (Dockerfile.agents)

**Security constraints for user manifests:**
- `target` path must resolve under `/mnt/agent-data` (enforced via `verify_path_under_data_dir()`)
- `container_link` must be relative path under `/home/agent` with no `..` segments
- Invalid TOML or constraint violations are logged and skipped (fail-safe, don't block startup)
- Binary must exist in PATH for wrapper to be generated

**Link repair integration:**
- Runtime generates user-specific link spec at `/mnt/agent-data/containai/user-link-spec.json`
- Schema matches built-in link-spec.json: `{"version": 1, "data_mount": "...", "home_dir": "...", "links": [{link, target, remove_first}]}`
- `link-repair.sh` extended to read both built-in and user link specs
- User symlinks are repaired alongside built-in ones

## Acceptance Criteria

1. Each agent/tool has its own manifest file in `src/manifests/` with numeric prefix for ordering
2. Per-agent files include `[agent]` section with launch config ONLY when `default_args` non-empty
3. Schema supports `aliases` array for commands with multiple names (e.g., kimi + kimi-cli)
4. Schema includes `optional` field for guarding wrapper generation with `command -v`
5. Generators read directly from per-agent files using sorted iteration for determinism
6. `src/scripts/gen-import-map.sh` generates `_IMPORT_SYNC_MAP` in indexed array format (same as today)
7. Wrappers generated in `/home/agent/.bash_env.d/containai-agents.sh`
8. `.bash_env` sources `.bash_env.d/*.sh` (for non-interactive SSH)
9. `.bashrc` sources `.bash_env` (for interactive shells)
10. Aliases removed from Dockerfile.agents (replaced by generated wrappers)
11. `[[container_symlinks]]` entries go in owning manifest (e.g., vscode symlinks in `05-vscode.toml`)
12. User manifests in `~/.config/containai/manifests/` work at container runtime
13. Runtime generators (`gen-user-links.sh`, `gen-user-wrappers.sh`) installed in image
14. User manifest security: path validation enforced, invalid manifests logged and skipped
15. User link spec uses same schema as built-in (`{link, target, remove_first}`)
16. `scripts/check-manifest-consistency.sh` works with new structure
17. TOML parsing uses `parse-toml.py` for arrays/validation, generators consume JSON output
18. All existing tests pass
19. E2E tests include plain `ssh container 'cmd'` (not just `bash -c` variant)
20. Documentation updated

## Out of Scope

- Runtime editing of manifests (build-time only for built-in, startup-time for user)
- Per-agent enable/disable toggles (handled by entry `o` flag)
- Agent installation management (remains in Dockerfile)
- User manifest hot-reload (requires container restart)
- OpenCode wrapper (no known autonomous flag)
