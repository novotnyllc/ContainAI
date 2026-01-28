# fn-36-rb7 CLI UX Consistency & Workspace State

## Overview

Make the ContainAI CLI consistent, intuitive, and predictable. This epic consolidates UX improvements from fn-12-css, fn-18-g96, and fn-34-fk5, with a focus on:

1. **Consistent parameter semantics** - same flag means same thing everywhere
2. **Workspace state persistence** - remember settings, don't require re-specifying
3. **Better container naming** - human-readable, predictable names
4. **Shell completions** - everywhere, including for `cai docker`
5. **`cai exec`** - general command execution with hidden complexity
6. **Nested workspace detection** - find parent workspace if exists

**Priority:** HIGH - Do this FIRST

## Scope

### In Scope
- Workspace state persistence in config
- Consistent `--container` semantics (doesn't error if exists, uses it)
- `--fresh` vs `--reset` clarification
- Human-readable container naming (repo-branch format)
- `cai exec <command>` for general command execution
- Shell completion for all cai commands (bash/zsh)
- `cai docker` passthrough with auto-injected `--context` (including `logs`, `exec`, etc.)
- `cai config` command for managing settings (workspace-aware)
- Nested workspace detection with parent container handling
- `cai setup` installs shell completion to `.bashrc.d/`

### Out of Scope
- Agent-specific execution (that's `cai run <agent>` in fn-34-fk5)
- Import reliability (fn-31-gib)
- User templates (fn-33-lp4)
- Base image contract documentation (separate epic)

## Approach

### Design Principles

1. **Predictable**: Same inputs always produce same behavior
2. **Remembering**: Once you specify something, we remember it
3. **Intuitive**: Flag names match what they do
4. **Progressive disclosure**: Simple commands work simply, options add power

### Workspace State Persistence

Store workspace settings in user config (`~/.config/containai/config.toml`):

```toml
# Auto-managed by cai commands
[workspace."/home/user/projects/myapp"]
data_volume = "myapp-agent-data"
container_name = "containai-myapp-main"
template = "default"
agent = "claude"
created_at = "2026-01-23T10:00:00Z"
```

**Behavior:**
- First time running `cai shell` in a workspace: auto-generate names, save to config
- Subsequent times: use saved settings
- `--data-volume`, `--container`, `--template`, `--agent`: override AND save to config
- `--fresh`: recreate container using SAME saved settings
- `--reset`: clear workspace config, use defaults, start fresh

### Consistent Parameter Semantics

**`--container NAME`** - Target a specific container:
- If container exists: use it
- If container doesn't exist: create it with that name
- Works the same on ALL commands (shell, run, import, export, stop)

**`--data-volume NAME`** - Use specific data volume:
- If volume exists: use it
- If volume doesn't exist: create it
- Saved to workspace config after first use

**`--fresh`** - Recreate container:
- Stop and remove existing container
- Create new container with SAME saved settings (volume, template, etc.)
- Does NOT change workspace config

**`--reset`** - Reset workspace to defaults:
- Stop and remove existing container
- Remove workspace-specific config entries
- Start with fresh defaults
- Next command will regenerate names/settings

### Better Container Naming

**Format:** `containai-{repo}-{branch}`

Examples:
- `/home/user/projects/myapp` on `main` branch → `containai-myapp-main`
- `/home/user/work/frontend` on `feature/login` → `containai-frontend-feature-login`

**Rules:**
- Repo name: directory name (last path component)
- Branch name: from git, sanitized (/ → -)
- Lowercase, alphanumeric and hyphens only
- Max 63 chars (Docker limit)
- Collision handling: append `-2`, `-3`, etc.

**Lookup order:** (1) workspace config, (2) workspace label, (3) new format

### `cai exec` Command

General command execution inside the container:

```bash
# Run any command
cai exec ls -la
cai exec npm test
cai exec "echo hello world"

# With options
cai exec --workspace /path/to/project npm install
cai exec --container my-project make build
```

**Key Features:**
- Auto-creates/starts container if needed
- Runs command via SSH with proper TTY handling
- Streams stdout/stderr to host
- Returns command's exit code
- **Hides complexity**: automatically includes `--context` and `-u agent` for docker operations

**How it differs from `cai run`:**
- `cai exec`: Run any command (general purpose)
- `cai run`: Run an AI agent with a prompt (agent-focused)

### Shell Completions

**`cai completion bash/zsh`** - Generate completion scripts

Completions for:
- Subcommands: `shell`, `run`, `exec`, `import`, `export`, `stop`, `status`, `gc`, `doctor`, `config`, `docker`
- Flags: `--container`, `--data-volume`, `--template`, `--workspace`, `--fresh`, `--reset`
- Values: container names, volume names, template names, agent names

**Special handling for `cai docker`:**
- Pass completion to docker
- Filter out `--context` (we set it automatically)
- Filter out `-u` for exec (we set it automatically)

```bash
# These work:
cai docker ps<TAB>
cai docker exec <TAB>  # Shows container names

# We auto-inject:
# cai docker exec foo -> docker --context containai-docker exec -u agent foo
```

### Setup Installs Completions

`cai setup` automatically adds completion to user's shell:

**For bash:**
```bash
# Creates ~/.bashrc.d/containai-completion.sh
# Adds source line if ~/.bashrc.d/ exists, else adds to ~/.bashrc
```

**Contents of completion file:**
```bash
# ContainAI shell completion
# Auto-installed by cai setup
eval "$(cai completion bash)"
```

**For zsh:**
```bash
# Creates ~/.zsh/completions/_cai
# Ensures fpath includes ~/.zsh/completions
```

This ensures completions work immediately after setup without manual configuration.

### Nested Workspace Detection

When detecting the implicit workspace (from cwd), check if a parent directory has an existing container:

```bash
# User is in /foo/bar/zaz, but there's already a container for /foo/bar
$ cd /foo/bar/zaz
$ cai shell
[INFO] Using existing workspace at /foo/bar (parent of /foo/bar/zaz)
Starting shell in containai-bar-main...
```

**Rules:**
1. Walk up from cwd checking each parent for workspace config entry
2. If found, use that parent as the implicit workspace
3. This is automatic and silent (just INFO message)

**Explicit `--workspace` with nested path = ERROR:**
```bash
$ cai shell --workspace /foo/bar/zaz
[ERROR] Cannot use /foo/bar/zaz as workspace.
        A container already exists at parent path /foo/bar.
        Use --workspace /foo/bar or remove the existing container.
```

This prevents accidentally creating overlapping containers for nested directories.

### `cai docker` Passthrough

All `cai docker` commands automatically inject `--context containai-docker`:

```bash
# User types:
cai docker ps
cai docker logs containai-myapp-main
cai docker exec containai-myapp-main bash

# Actually runs:
docker --context containai-docker ps
docker --context containai-docker logs containai-myapp-main
docker --context containai-docker exec -u agent containai-myapp-main bash
```

**Important:** This ensures `cai docker logs`, `cai docker inspect`, and all other docker commands work correctly with the ContainAI Docker context.

### `cai config` Command

```bash
cai config list                        # Show all settings with source
cai config get <key>                   # Get value (workspace if in one, else global)
cai config set <key> <value>           # Set (workspace if in one, else global)
cai config set --global|-g <key> <value>  # Force global
cai config set --workspace <path> <key> <value>  # Explicit workspace
cai config unset <key>                 # Remove setting
```

**Workspace scope detection:**
- If in a workspace directory (or nested child): settings apply to that workspace
- If `--global` or `-g` specified: force global scope
- If `--workspace <path>` specified: apply to that specific workspace
- Outside any workspace and no flags: apply globally

**Workspace-specific keys:**
- `data_volume` - Data volume name
- `container_name` - Container name
- `template` - Template name
- `agent` - Default agent

**Global keys:**
- `agent.default` - Default agent (global)
- `ssh.forward_agent` - Enable SSH agent forwarding
- `ssh.port_range_start` / `ssh.port_range_end` - SSH port range
- `import.auto_prompt` - Prompt for import on new volume

## Tasks

### fn-36-rb7.1: Implement workspace state persistence
Store workspace settings in config. Auto-save on first use, reuse on subsequent.

### fn-36-rb7.2: Implement consistent --container semantics
Same behavior everywhere: use if exists, create if not, save to config.

### fn-36-rb7.3: Implement --fresh flag
Recreate container with same saved settings. Don't touch workspace config.

### fn-36-rb7.4: Implement --reset flag
Clear workspace config, remove container, start fresh with defaults.

### fn-36-rb7.5: Implement human-readable container naming
repo-branch format, sanitization, collision handling.

### fn-36-rb7.6: Implement cai exec command
General command execution with TTY handling, exit code passthrough.

### fn-36-rb7.7: Implement cai config command
get/set/list/unset with workspace-aware scope (auto-detect workspace from cwd).

### fn-36-rb7.8: Implement shell completion for cai commands
bash/zsh completion for subcommands, flags, and values.

### fn-36-rb7.9: Implement shell completion for cai docker
Pass to docker completion, filter --context and -u.

### fn-36-rb7.10: Update cai setup to install shell completions
Add completion script to ~/.bashrc.d/ or ~/.bashrc during setup.

### fn-36-rb7.11: Update container lookup helper
Check workspace config first, then labels, then new naming.

### fn-36-rb7.12: Update all commands to use workspace state
shell, run, exec, import, export, stop all use persisted settings.

### fn-36-rb7.13: Implement nested workspace detection
Walk up from cwd to find parent workspace. Error if explicit --workspace conflicts.

### fn-36-rb7.14: Fix cai docker passthrough for all commands
Ensure logs, inspect, and all docker commands get --context injected.

## Quick commands

```bash
# Test workspace state persistence
cd /tmp/test-project && git init
cai shell  # Creates with auto-generated names
cai shell  # Uses saved names (no flags needed)

# Test --fresh
cai shell --fresh  # Recreate with same settings

# Test --reset
cai shell --reset  # Clear config, start fresh

# Test exec
cai exec ls -la
cai exec npm test

# Test config (workspace-aware)
cd /tmp/test-project
cai config list              # Shows workspace settings
cai config set agent claude  # Sets for this workspace
cai config set -g agent.default claude  # Sets globally

# Test cai docker passthrough
cai docker ps
cai docker logs containai-test-project-main

# Test nested workspace detection
mkdir -p /tmp/test-project/subdir
cd /tmp/test-project/subdir
cai shell  # Should use /tmp/test-project container

# Test completions
source <(cai completion bash)
cai <TAB>
cai shell --<TAB>
cai docker ps <TAB>
```

## Acceptance

- [ ] Workspace settings saved to config on first use
- [ ] Subsequent commands use saved settings (no flags needed)
- [ ] `--container` works consistently: use or create
- [ ] `--data-volume` saved to workspace config
- [ ] `--fresh` recreates container with same settings
- [ ] `--reset` clears workspace config and starts fresh
- [ ] Container names use repo-branch format
- [ ] `cai exec` runs commands with proper TTY/exit code
- [ ] `cai config` auto-detects workspace from cwd
- [ ] `cai config --global` forces global scope
- [ ] Shell completion works for bash/zsh
- [ ] `cai setup` installs completion to ~/.bashrc.d/ or ~/.bashrc
- [ ] `cai docker logs` works (context injected)
- [ ] `cai docker` completion works with filtering
- [ ] Nested workspace: cwd in /foo/bar/zaz uses existing /foo/bar container
- [ ] Explicit --workspace /foo/bar/zaz errors if parent /foo/bar has container

## Supersedes

- **fn-12-css** workspace state, config command, cai exec
- **fn-18-g96** container naming, --container semantics, shell completion
- **fn-34-fk5** --container, --reset, container lookup (keep session detection, gc, run)

## Dependencies

None - this should be done FIRST

## References

- fn-12-css spec: `.flow/specs/fn-12-css.md`
- fn-18-g96 spec: `.flow/specs/fn-18-g96.md`
- Bash completion: https://www.gnu.org/software/bash/manual/html_node/Programmable-Completion.html
- Docker completion: https://docs.docker.com/compose/completion/
