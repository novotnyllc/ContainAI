# fn-12-css Workspace-Centric UX & Config Improvements

## Overview

Transform ContainAI from a CLI that requires manual parameter specification to a workspace-centric tool that automatically remembers context. After creating a container for a workspace, all subsequent commands "just work" without extra flags.

**Key changes:**
1. Workspace state persistence (remember volume associations)
2. One-shot exec mode (`cai exec <cmd>`)
3. Config command (`cai config get/set/list/unset`)
4. Hierarchical .env file support (default → volume → workspace)
5. Import filtering (exclude `.bashrc.d/*.priv.*`)
6. Remove host env import (security: too easy to leak)
7. Consolidate `cai setup` (merge install-containai-docker.sh)

## Scope

### In Scope
- Workspace state persistence in user config
- `cai exec` one-shot command execution
- `cai config` for managing settings
- .env file hierarchy (default.env → volume.env → workspace.env)
- Import filtering for `.priv.` files
- Removal of `from_host` env import behavior
- Merging `scripts/install-containai-docker.sh` into `cai setup`

### Out of Scope
- Backwards compatibility (nothing shipped yet)
- Documentation updates (separate effort)
- Multi-container per workspace

## Approach

### Workspace State Persistence

Store workspace→volume associations in user config (`~/.config/containai/config.toml`):

```toml
# Auto-managed by cai commands
[workspace."/home/user/projects/myapp"]
data_volume = "myapp-agent-data"
created_at = "2025-01-23T10:00:00Z"
```

**All workspace-specific commands** use and respect this state:
- `cai run` / `cai shell` / `cai exec` - create/attach to container
- `cai import` / `cai export` - sync data to/from volume
- `cai stop` - stop container for workspace

When any workspace command is invoked:
1. Detect workspace from cwd
2. Check if workspace has saved volume association
3. If not, auto-generate volume name from workspace path
4. Persist the association after successful container creation (run/shell/exec only)

### One-Shot Exec Mode

New command: `cai exec <command> [args...]`
- Auto-creates/starts container if needed
- Executes command via SSH
- Streams stdout/stderr to caller
- Returns command exit code
- `--no-prompt` flag to skip import prompt

### Config Command

```
cai config get <key>           # Read value
cai config set <key> <value>   # Set global config
cai config set --workspace <key> <value>  # Set workspace config
cai config list                # Show all with source
cai config unset <key>         # Remove key
```

Supported keys:
| Key | Description |
|-----|-------------|
| `ssh.forward_agent` | Enable SSH agent forwarding |
| `ssh.allow_tunnel` | Allow SSH tunneling |
| `ssh.port_range_start` | SSH port range start |
| `ssh.port_range_end` | SSH port range end |
| `import.auto_prompt` | Prompt for import on new volume |
| `import.exclude_priv` | Exclude *.priv.* from .bashrc.d |
| `env.default_file` | Default .env file path |
| `container.memory` | Default memory limit |
| `container.cpus` | Default CPU limit |

### .env File Hierarchy

Load in order (later overrides earlier):
1. `~/.config/containai/default.env` - Global defaults
2. `~/.config/containai/volumes/<volume-name>.env` - Per-volume
3. `<workspace>/.containai/env` - Per-workspace

Remove `from_host = true` behavior - too easy to accidentally export secrets.

### Import Filtering

Exclude `.bashrc.d/*.priv.*` files during import to prevent accidental secret leakage. Controlled by `import.exclude_priv` config (default: true).

### Setup Consolidation

Merge `scripts/install-containai-docker.sh` functionality into `lib/setup.sh`. Single entry point: `cai setup` handles all Docker/Sysbox installation.

## Quick commands

```bash
# Lint
shellcheck -x src/*.sh src/lib/*.sh

# Integration tests
./tests/integration/test-secure-engine.sh
./tests/integration/test-sync-integration.sh

# Build images
./src/build.sh
```

## Acceptance

- [ ] All workspace commands work without `--data-volume` after first use (shell, run, import, export, stop, exec)
- [ ] `cai exec echo hello` returns "hello" and exit code 0
- [ ] `cai config set ssh.forward_agent true` persists to user config
- [ ] `cai config get ssh.forward_agent` returns "true"
- [ ] Environment merges default.env → volume.env → workspace.env
- [ ] `.bashrc.d/01_secrets.priv.sh` is not imported
- [ ] `from_host = true` in config is ignored (no host env import)
- [ ] `cai setup` installs Docker + Sysbox (replaces install-containai-docker.sh)

## References

- Current config: `docs/configuration.md`
- Architecture: `docs/architecture.md`
- Scripts to merge: `scripts/install-containai-docker.sh`
