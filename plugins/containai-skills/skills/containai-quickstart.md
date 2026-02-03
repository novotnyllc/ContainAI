# ContainAI Quickstart

Use this skill when: starting a sandbox, running commands in isolation, first-time setup, quick tasks in containers.

## Prerequisites

Before starting, ensure your system is configured:

```bash
cai doctor
```

This checks for Docker and Sysbox runtime. Follow any remediation steps shown.

## Start a Sandbox

### Basic Start (Current Directory)

```bash
cai run                    # Start/attach in current workspace
```

This will:
1. Create a container for the current directory (if needed)
2. Start it (if stopped)
3. Attach to the agent session

### Start for Specific Workspace

```bash
cai run /path/to/project   # Start container for specified workspace
cai run --workspace /path  # Alternative syntax
```

### Start in Background

```bash
cai run --detached         # Start in background (no attach)
cai run -d                 # Short form
```

### Start with Fresh Container

```bash
cai --fresh                # Recreate container (preserves data volume)
cai --restart              # Alias for --fresh
```

## Run Commands

### Interactive Shell

```bash
cai shell                  # Open bash shell in container
```

From inside the shell, you're in `/home/agent/workspace/` with your project mounted.

### Single Command

```bash
cai exec ls -la                    # List files
cai exec npm test                  # Run tests
cai exec -- git status             # Use -- to separate cai flags from command
cai exec -w /other/project pwd     # Run in different workspace
```

### Pass Arguments to Command

```bash
cai exec -- npm run build -- --watch    # Arguments after second --
```

## Stop Containers

### Stop Current Workspace Container

```bash
cai stop                   # Interactive selection or current workspace
```

### Stop All ContainAI Containers

```bash
cai stop --all             # Stop all containers
```

### Stop and Remove

```bash
cai stop --remove          # Stop and delete container
cai stop --all --remove    # Remove all containers
```

### Export Before Stop

```bash
cai stop --export          # Export data volume, then stop
```

## Check Status

```bash
cai status                 # Show current container status
cai status --json          # Machine-readable output
```

## Common Patterns

### Quick Test Run

```bash
cd ~/projects/myapp
cai exec npm test
```

### Interactive Development Session

```bash
cd ~/projects/myapp
cai shell
# Now in container shell
npm install
npm run dev
# Ctrl+D to exit
```

### Restart with Clean State

```bash
cai stop
cai run --fresh            # New container, same data volume
```

### Complete Reset (New Data Volume)

```bash
cai run --reset            # New container AND new data volume
```

## Gotchas

### Workspace Path Matters

Same path = same container. If you `cd` to a different project, you get a different container.

```bash
cd ~/project-a && cai run  # Container for project-a
cd ~/project-b && cai run  # Different container for project-b
```

### Data Persists in Volume

Files in `/home/agent/.containai/data/` persist across container recreations (with `--fresh`). Use `--reset` to start with a fresh data volume.

### SSH Agent Forwarding

Your host SSH keys are NOT copied. Use SSH agent forwarding:

```bash
# Start ssh-agent on host (if not running)
eval "$(ssh-agent)"
ssh-add ~/.ssh/id_ed25519

# ContainAI automatically forwards the agent
cai shell
# Keys available inside container via forwarding
```

### Exit Codes

`cai exec` passes through the exit code from the container command:

```bash
cai exec true && echo "success"   # success
cai exec false || echo "failed"   # failed
```

## Related Skills

- `containai-lifecycle` - Full container management reference
- `containai-sync` - Data persistence and config sync
- `containai-troubleshooting` - When things go wrong
