# ContainAI Container Lifecycle

Use this skill when: managing container state, understanding run/stop/status commands, cleaning up resources, working with multiple containers.

## Container States

ContainAI containers have these states:

| State | Description | Transitions |
|-------|-------------|-------------|
| (none) | Container doesn't exist | `cai run` creates it |
| created | Created but never started | `cai run` starts it |
| running | Active and accessible | `cai stop` stops it |
| exited | Stopped | `cai run` restarts it |

## Run Command

Start or attach to a container.

```bash
cai run [path] [options]
```

### Options

```bash
--workspace <path>    # Workspace path (default: current directory)
--container <name>    # Use specific container name
--template <name>     # Template for container (default: "default")
--channel <channel>   # Release channel: stable or nightly
--image-tag <tag>     # Specific image tag (advanced)
--memory <size>       # Memory limit (e.g., "4g", "8g")
--cpus <count>        # CPU limit (e.g., 2, 4)
--data-volume <vol>   # Override data volume name
--config <path>       # Config file path
--fresh / --restart   # Recreate container (preserve data)
--reset               # New container AND new data volume
--force               # Skip isolation checks
--detached / -d       # Run in background
--quiet / -q          # Suppress output
--verbose             # Enable verbose output
--dry-run             # Show what would happen
-e, --env <VAR=val>   # Set environment variable
-- <args>             # Pass arguments to agent
```

### Examples

```bash
cai run                          # Current directory, default options
cai run /path/to/project         # Specific workspace
cai run --container my-project   # Named container
cai run --detached               # Background mode
cai run --fresh                  # Recreate container
cai run --memory 8g --cpus 4     # Resource limits
cai run -e API_KEY=xxx           # With environment variable
cai run --dry-run                # Preview actions
```

## Shell Command

Open interactive bash shell in container.

```bash
cai shell [path] [options]
```

Creates container if needed, starts if stopped, then opens shell.

```bash
cai shell                        # Shell in current workspace container
cai shell /path/to/project       # Shell in specific workspace
cai shell --container foo        # Shell in named container
cai shell --fresh                # Recreate then shell
```

## Exec Command

Run single command in container.

```bash
cai exec [options] [--] <command> [args...]
```

### Examples

```bash
cai exec ls -la                  # List files
cai exec npm test                # Run tests
cai exec -- git status           # Separate cai flags from command
cai exec -w /other/project pwd   # Different workspace
cai exec --container foo npm ci  # In named container
```

### TTY Handling

- PTY allocated automatically if stdin is a TTY
- stdout/stderr streamed in real-time
- Exit code passed through

## Stop Command

Stop containers.

```bash
cai stop [options]
```

### Options

```bash
--container <name>    # Stop specific container
--all                 # Stop all ContainAI containers
--export              # Export data volume before stopping
--remove              # Also remove containers (not just stop)
--force               # Skip session warning, continue on export failure
--verbose             # Enable verbose output
```

### Examples

```bash
cai stop                         # Interactive selection
cai stop --container my-project  # Stop specific container
cai stop --all                   # Stop all
cai stop --export                # Export then stop
cai stop --remove                # Stop and remove
cai stop --all --remove          # Remove all
cai stop --force                 # Skip confirmation prompts
```

### Session Detection

When stopping a specific container, active sessions are detected and you'll be prompted to confirm. Use `--force` to skip the prompt.

## Status Command

Show container status and resource usage.

```bash
cai status [options]
```

### Options

```bash
--workspace <path>    # Status for specific workspace
--container <name>    # Status for specific container
--json                # JSON output
--verbose             # Verbose output
```

### Output Fields

- Container name, status, image (always shown)
- Uptime, sessions, memory, CPU (best-effort, 5s timeout)

### Examples

```bash
cai status                       # Current workspace
cai status --container my-proj   # Specific container
cai status --json                # Machine-readable
cai status --workspace ~/proj    # Specific workspace
```

## Garbage Collection

Clean up stale containers and images.

```bash
cai gc [options]
```

### Options

```bash
--dry-run             # Preview without removing
--force               # Skip confirmation
--age <duration>      # Minimum age (default: 30d)
--images              # Also prune unused images
--verbose             # Verbose output
```

### Age Format

`Nd` for days, `Nh` for hours: `7d`, `24h`, `30d`

### Protection Rules

- Never prunes running containers
- Never prunes containers with `containai.keep=true` label
- Only prunes containers with `containai.managed=true` label

### Examples

```bash
cai gc                           # Interactive, list candidates
cai gc --dry-run                 # Preview only
cai gc --force                   # No confirmation
cai gc --age 7d                  # Older than 7 days
cai gc --images                  # Also prune images
cai gc --force --images          # Full cleanup
```

## Common Patterns

### Development Workflow

```bash
# Start session
cai run

# Work, work, work...

# End session (container stays running)
# Ctrl+D or exit

# Later: reconnect
cai shell

# End of day: stop container
cai stop
```

### Fresh Start (Keep Data)

```bash
cai stop
cai run --fresh
```

### Complete Reset

```bash
cai run --reset    # New container, new data volume
```

### Cleanup Old Containers

```bash
cai gc --dry-run   # See what would be removed
cai gc --force     # Actually remove
```

### Multiple Projects

```bash
# Each workspace gets its own container
cd ~/project-a && cai run -d
cd ~/project-b && cai run -d

# Check status for each workspace
cd ~/project-a && cai status
cd ~/project-b && cai status

# Or use --workspace flag
cai status --workspace ~/project-a
cai status --workspace ~/project-b

# Stop all
cai stop --all
```

## Gotchas

### Container Naming

Containers are named deterministically from workspace path:
- New format: `{repo}-{branch}` (e.g., `myapp-main`)
- Legacy format: `containai-{hash}`
- Same path always gives same container
- Use `--container` to override
- Use `cai status` to see container name for a workspace

### Data Volume vs Container

- `--fresh` recreates container, keeps data volume
- `--reset` recreates both container AND data volume
- Data volume persists agent state, caches, configs

### Port Conflicts

Each container gets a unique SSH port. If you have many containers, ensure the port range is large enough in config.

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 11 | Container failed to start |
| 12 | SSH setup failed |
| 13 | SSH connection failed |
| 14 | Host key mismatch |
| 15 | Container not owned by ContainAI |

## Related Skills

- `containai-quickstart` - Getting started
- `containai-sync` - Data import/export
- `containai-troubleshooting` - Error handling
