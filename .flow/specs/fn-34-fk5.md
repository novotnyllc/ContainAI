# fn-34-fk5 One-Shot Execution & Container Lifecycle

## Overview

Redesign `cai run` to be the primary way to execute agents, with a simpler command syntax. Also address the complex problem of knowing when to spin down containers safely. This epic consolidates work from fn-12-css (exec), fn-18-g96 (container UX), and fn-19-qni (lifecycle/cleanup).

**Key Change:** `cai run` requires an agent and executes it directly. Running `cai` without parameters shows help.

## Scope

### In Scope
- **Redesigned `cai run`:** `cai run [options] <agent> -- <agent args>`
- Agent is **required** for `cai run`
- Default agent configurable (global and per-workspace)
- `cai` with no params shows help
- Handy aliases for common patterns
- Synchronous execution with stdio/stderr passthrough
- Exit code passthrough
- Session detection (VS Code, SSH connections)
- Graceful container lifecycle management
- **`cai gc` command** (from fn-19-qni) - prune stale containers/images
- **`--reset` flag** (from fn-19-qni) - wipe data volume
- **`cai status` command** - show container status and sessions
- **`--container` parameter** (from fn-18-g96) - explicit container selection
- **Container lookup helper** (from fn-18-g96) - `_cai_find_workspace_container()`

### Out of Scope
- Automatic container shutdown (too risky for data loss)
- Background job queuing
- Multi-command pipelines
- Container orchestration
- Shell completion (keep in separate epic or defer)

## Approach

### New `cai run` Syntax

```bash
# Run claude with arguments after --
cai run claude -- "Fix the bug in main.py"

# Run gemini
cai run gemini -- "Explain this code"

# Run with workspace option
cai run --workspace /path/to/project claude -- "Add tests"

# Short form with default agent (if configured)
cai run -- "Fix the bug"  # Uses default agent from config
```

**Syntax:** `cai run [run-options] <agent> -- <agent-arguments>`

**Run Options:**
- `--workspace PATH` - Override workspace directory
- `--template NAME` - Use specific template
- `--fresh` - Recreate container (keep volume)
- `--reset` - Recreate container AND wipe data volume (from fn-19-qni)
- `--import` - Run import before agent
- `--container NAME` - Explicit container name (from fn-18-g96)

**Agent is required** unless a default is configured. If no agent and no default:
```
$ cai run -- "Fix this bug"
[ERROR] No agent specified and no default agent configured.

Usage: cai run [options] <agent> -- <agent arguments>

Examples:
  cai run claude -- "Fix the bug in main.py"
  cai run gemini -- "Explain this code"

To set a default agent, add to ~/.config/containai/config.toml:
  [agent]
  default = "claude"

Or per-workspace in .containai/config.toml:
  [agent]
  default = "gemini"
```

### Default Agent Configuration

**Global default** (`~/.config/containai/config.toml`):
```toml
[agent]
default = "claude"
```

**Per-workspace** (`.containai/config.toml` in workspace):
```toml
[agent]
default = "gemini"  # Overrides global for this workspace
```

### `cai` Without Parameters Shows Help

```
$ cai
ContainAI - Sandboxed container environment for AI coding agents

Usage:
  cai run <agent> -- <args>    Run an agent with arguments
  cai shell                     Open interactive shell
  cai import                    Sync configs from host
  cai export                    Export data volume
  cai stop                      Stop container
  cai status                    Show container status
  cai gc                        Clean up stale containers
  cai doctor                    Check system health
  cai help                      Show detailed help

Examples:
  cai run claude -- "Fix the bug in main.py"
  cai shell
  cai import --dry-run

Run 'cai help' for full documentation.
```

### Handy Aliases

For common workflows, provide shell aliases or wrapper functions:

```bash
# In ~/.bashrc or suggested by cai
alias claude='cai run claude --'
alias gemini='cai run gemini --'
alias codex='cai run codex --'
```

Usage:
```bash
claude "Fix the bug in main.py"
gemini "Explain this code"
```

Document these aliases in help and quickstart.

### Container GC (from fn-19-qni)

New command to prune stale ContainAI resources:

```bash
cai gc                    # Interactive: show candidates, confirm
cai gc --dry-run          # List what would be removed
cai gc --force            # Skip confirmation
cai gc --age 7d           # Only prune containers older than 7 days
cai gc --images           # Also prune unused images
```

**Protection mechanism:**
- Resources with label `containai.keep=true` are never pruned
- Running containers are never pruned
- Containers with active sessions are never pruned
- Only prunes ContainAI-managed resources (label `containai.managed=true`)

### Execution Flow

1. Parse arguments, extract agent and agent-args
2. Resolve workspace (current directory or `--workspace`)
3. Find or create container for workspace (using lookup helper)
4. Start container if stopped
5. Run import if `--import` flag or new container
6. Execute via SSH: `ssh container '<agent> <agent-args>'`
7. Stream stdout/stderr to host terminal
8. Return agent's exit code
9. Do NOT stop container (may have other sessions)

### Session Detection

Before any container lifecycle action, detect active sessions:

**Detection Function:**
```bash
_cai_has_active_sessions() {
    local container="$1"
    local ssh_count pty_count

    # Count SSH connections
    ssh_count=$(ssh "$container" 'ss -t state established sport = :22 | tail -n +2 | wc -l' 2>/dev/null || echo 0)

    # Count active PTYs (terminals)
    pty_count=$(ssh "$container" 'ls /dev/pts/ 2>/dev/null | grep -c "^[0-9]"' 2>/dev/null || echo 0)

    # If multiple PTYs or SSH connections, likely has active sessions
    [[ "$ssh_count" -gt 1 || "$pty_count" -gt 1 ]]
}
```

### Container Lifecycle Rules

**Rule 1: Never Auto-Stop Running Containers**
- `cai run` does not stop the container after execution
- `cai shell` does not stop the container on exit
- Only explicit `cai stop` stops containers

**Rule 2: Warn Before Stopping with Active Sessions**
```
$ cai stop
[WARN] Container has 2 active sessions:
       - SSH connection from 192.168.1.100
       - VS Code attached (3 open files)

Stop anyway? [y/N]:
```

**Rule 3: Provide Session Information**
```
$ cai status
Container: containai-myproject-main
  Status: running
  Uptime: 3 days, 4 hours
  Sessions:
    - SSH: 2 connections
    - PTYs: 3 active
    - VS Code: attached
  Resources:
    - Memory: 1.2GB / 4GB
    - CPU: 5%
```

## Tasks

### fn-34-fk5.1: Redesign cai run command
Implement new syntax: `cai run [options] <agent> -- <agent args>`. Parse arguments, handle `--` separator.

### fn-34-fk5.2: Implement default agent configuration
Add `[agent].default` config option. Support global and per-workspace overrides.

### fn-34-fk5.3: Update cai with no params to show help
Remove default "run" behavior. Show concise help when no subcommand given.

### fn-34-fk5.4: Implement helpful error for missing agent
When agent not specified and no default, show helpful message with config example.

### fn-34-fk5.5: Implement stdio/stderr passthrough
Ensure terminal output from container streams to host correctly. Handle TTY allocation.

### fn-34-fk5.6: Implement exit code passthrough
Return the agent's exit code from `cai run`. Enable scripts to check success/failure.

### fn-34-fk5.7: Document handy aliases
Create documentation showing alias setup for common agents. Include in quickstart.

### fn-34-fk5.8: Implement session detection
Create `_cai_has_active_sessions()` function. Detect SSH connections, PTYs, VS Code.

### fn-34-fk5.9: Add session warning to cai stop
Before stopping, check for active sessions. Warn and prompt for confirmation.

### fn-34-fk5.10: Implement cai status command
Show container status including uptime, resource usage, and active sessions.

### fn-34-fk5.11: Implement cai gc command (from fn-19-qni)
Prune stale containers/images with configurable retention. Respect active sessions.

### fn-34-fk5.12: Add --reset flag to cai run (from fn-19-qni)
Wipe data volume AND recreate container. Require confirmation.

### fn-34-fk5.13: Implement --container parameter (from fn-18-g96)
Allow explicit container selection. Derive workspace/volume from container labels.

### fn-34-fk5.14: Implement container lookup helper (from fn-18-g96)
Create `_cai_find_workspace_container()` with workspace label and new naming format.

### fn-34-fk5.15: Document container lifecycle behavior
Write clear documentation on when containers are created, started, stopped, and destroyed.

### fn-34-fk5.16: Add --export flag to cai stop
Optional flag to run export before stopping for work preservation.

## Quick commands

```bash
# Run agent with prompt
cai run claude -- "Fix the bug in main.py"

# Run with workspace
cai run --workspace ~/project gemini -- "Explain this"

# Check container status
cai status

# Stop with session warning
cai stop

# Force stop (dangerous)
cai stop --force

# Stop with backup
cai stop --export

# Reset volume
cai run --reset claude -- "Start fresh"

# Garbage collect
cai gc --dry-run
cai gc --age 7d
```

## Acceptance

- [ ] `cai run <agent> -- <args>` executes agent with arguments
- [ ] Agent required for `cai run` (error if missing and no default)
- [ ] Default agent configurable (global and per-workspace)
- [ ] `cai` with no params shows concise help
- [ ] Helpful error message when no agent specified
- [ ] Output streams to host terminal in real-time
- [ ] Exit code from agent returned to host
- [ ] Session detection identifies SSH and VS Code connections
- [ ] `cai stop` warns when active sessions detected
- [ ] `cai stop --force` skips warning
- [ ] `cai status` shows sessions and resource usage
- [ ] `cai gc` prunes stale containers with configurable age
- [ ] `cai gc --dry-run` shows candidates without removing
- [ ] Running containers and `containai.keep=true` protected from GC
- [ ] `cai run --reset` wipes data volume (with confirmation)
- [ ] `--container` parameter works for explicit container selection
- [ ] Documentation includes alias examples
- [ ] GC never prunes containers with active sessions

## Supersedes

- **fn-12-css** `cai exec` tasks
- **fn-18-g96** container UX tasks (except templates and shell completion)
- **fn-19-qni** `cai gc`, `--reset` flag, lifecycle tasks

## Superseded By

- **fn-36-rb7** supersedes tasks: `--container` parameter, container lookup helper, workspace state persistence, container naming

## Dependencies

- **fn-36-rb7** (should complete first): CLI UX consistency provides workspace state, consistent `--container` semantics, container naming
- **fn-31-gib**: Import reliability (run needs working import)
- **fn-33-lp4**: User Templates (template building for containers)

## References

- fn-12-css spec: `.flow/specs/fn-12-css.md` (existing exec concept)
- fn-18-g96 spec: `.flow/specs/fn-18-g96.md` (container UX)
- fn-19-qni spec: `.flow/specs/fn-19-qni.md` (existing lifecycle concept)
- SSH session detection: `ss` command, `/dev/pts/` enumeration
- VS Code Remote: https://code.visualstudio.com/docs/remote/ssh
