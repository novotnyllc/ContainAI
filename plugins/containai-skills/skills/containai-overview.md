# ContainAI Overview

Use this skill when: explaining what ContainAI is, why to use sandboxed containers, understanding the security model, comparing to other approaches.

## What is ContainAI?

ContainAI is a sandboxed container environment for AI coding agents. It provides:

- **Secure isolation** - Run AI agents in containers with Sysbox for hardware-virtualized isolation
- **Persistent data** - Data volumes preserve agent state across sessions
- **Workspace mounting** - Your project directory is mounted read-write in the container
- **SSH access** - Real terminal experience with agent forwarding support
- **Config sync** - Import host configs (git, credentials) into containers

## Key Concepts

### Containers vs Sandboxes

ContainAI uses Docker containers with **Sysbox runtime** for secure isolation:
- Containers appear as full VMs to processes inside (systemd, nested Docker work)
- Host kernel is protected via user namespaces
- No privileged access needed

### Data Model

```
Host                          Container
────────────────────────────  ─────────────────────────────
~/projects/myapp/             /home/agent/workspace/
  (workspace mount)              (read-write)

Docker volume: <volume-name>  /mnt/agent-data/
  (default: sandbox-agent-data)  (volume mount)

                              ~/.gitconfig -> /mnt/agent-data/git/gitconfig
                              ~/.claude.json -> /mnt/agent-data/claude/claude.json
                              (symlinks to volume)
```

The `cai sync` command creates symlinks from user-facing config paths to the
persistent volume, so agents can edit normal dotfiles while data persists.

### Workspace Binding

Each workspace path gets a deterministic container:
- Same path = same container
- Different paths = different containers
- Container names: `{repo}-{branch}` format (e.g., `myapp-main`)
- Legacy containers: `containai-{hash}` format
- Override with `--container <name>` for explicit naming

## When to Use ContainAI

**Use ContainAI when:**
- Running AI coding agents (Claude Code, Codex, Gemini Code Assist)
- You want isolation from host system
- You need persistent agent state across sessions
- You want to test potentially risky code changes

**Don't need ContainAI when:**
- Running simple, trusted scripts
- You need direct host hardware access
- You're already in a VM or container

## Security Model

ContainAI provides defense-in-depth:

1. **Container isolation** - Processes cannot access host filesystem (except workspace)
2. **Sysbox hardening** - User namespace isolation, restricted capabilities
3. **Network policies** - Optional egress filtering via `.containai/network.conf`
4. **Credential isolation** - Containers run their own login flows by default

### What's Protected

- Host filesystem (only workspace is mounted)
- Host Docker socket (not mounted by default)
- Host SSH keys (not synced by default; use agent forwarding)
- Other containers and processes

### What's NOT Protected

- Your workspace directory (mounted read-write)
- Network access (unless restricted via network.conf)
- Data explicitly synced via `cai import`

## CLI Entry Point

ContainAI is accessed via the `cai` (or `containai`) command:

```bash
# Source the CLI (add to ~/.bashrc for persistence)
source /path/to/containai/src/containai.sh

# Now available
cai --help
```

## Common Workflow

```bash
# 1. Check system is ready
cai doctor

# 2. Start container for your project
cd ~/projects/myapp
cai run

# 3. Work in the container (agent or shell)
cai shell        # Interactive shell
cai exec ls -la  # Run single command

# 4. Stop when done
cai stop
```

## Related Skills

- `containai-quickstart` - Hands-on getting started guide
- `containai-lifecycle` - Container management commands
- `containai-setup` - System configuration
