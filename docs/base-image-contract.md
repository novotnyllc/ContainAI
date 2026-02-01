# ContainAI Base Image Contract

This document describes what ContainAI expects from base images used as runtime containers.

## Contract Target

This contract applies to images usable as ContainAI runtime images:

- Images used in template Dockerfiles (`FROM ...`)
- Images passed via `--image-tag`

The reference implementation is `ghcr.io/novotnyllc/containai:latest`.

## Required

### Filesystem Layout

| Path | Purpose |
|------|---------|
| `/home/agent` | Agent user home directory |
| `/mnt/agent-data` | Mount point for persistent data volume |
| `/opt/containai` | ContainAI scripts and tools |
| `/usr/local/lib/containai/init.sh` | Init script for workspace setup (invoked by containai-init.service) |

### User

| Requirement | Value |
|-------------|-------|
| Username | `agent` |
| UID | 1000 |
| Shell | `/bin/bash` |
| Sudo | Passwordless (`NOPASSWD:ALL`) |
| Home | `/home/agent` |

The agent user must have passwordless sudo to allow container initialization scripts to run with elevated privileges when needed.

### Services (systemd units)

| Service | Type | Purpose |
|---------|------|---------|
| `containai-init.service` | oneshot | Workspace setup - creates volume structure, sets up symlinks, loads `.env` |
| `ssh.service` | daemon | OpenSSH server listening on port 22 (Ubuntu uses `ssh.service`, not `sshd.service`) |
| `docker.service` | daemon | Docker daemon for Docker-in-Docker support |
| `containerd.service` | daemon | Container runtime for Docker |

All services are enabled via symlinks in `/etc/systemd/system/multi-user.target.wants/`.

### Entrypoint/CMD Requirements

ContainAI runs containers with **no command argument**:

```bash
docker run ... <image>  # No CMD passed
```

This means:

- **ENTRYPOINT** must start systemd as PID 1 (`/sbin/init` or equivalent)
- **CMD** should not be set (or must not interfere with systemd boot)
- Templates/custom images **MUST NOT** override ENTRYPOINT or CMD

If ENTRYPOINT/CMD is overridden, systemd won't be PID 1, and all services (SSH, Docker, containai-init) will fail to start.

The reference implementation uses:

```dockerfile
STOPSIGNAL SIGRTMIN+3
ENTRYPOINT [ "/sbin/init", "--log-level=err" ]
```

### Environment

| Variable | Value | Purpose |
|----------|-------|---------|
| `container` | `docker` | Systemd container detection |
| `STOPSIGNAL` | `SIGRTMIN+3` | Proper systemd shutdown signal |
| `PATH` | includes `/home/agent/.local/bin` | Agent-local binaries |

## Recommended

### AI Agents

| Agent | Location |
|-------|----------|
| Claude Code CLI | `/home/agent/.local/bin/claude` |

Additional agents may be installed in the agents layer.

### SDKs (for full development environment)

| SDK | Installation Method |
|-----|---------------------|
| Node.js | via nvm (`~/.nvm`) |
| Python | via uv/pipx |
| Go, Rust, .NET | as needed |

## Validation Behavior

ContainAI validates template Dockerfiles by parsing the first `FROM` line:

1. Collects `ARG` values defined before the `FROM` line
2. Resolves variable substitution in the `FROM` line (supports `$VAR`, `${VAR}`, `${VAR:-default}`)
3. Checks if the resolved base image matches one of these patterns:
   - `ghcr.io/novotnyllc/containai*`
   - `containai:*`
   - `containai-template-*:local` (locally built templates)
4. If not matched: **WARN** (not error) - ContainAI features may not work
5. If `ARG` variables cannot be resolved: **WARN** about unresolved variable

**Note:** This validates the *Dockerfile source*, not runtime layer history. The check happens at template build time by parsing the Dockerfile text.

### Warning Suppression

To suppress the warning for intentional non-ContainAI bases:

```toml
# ~/.config/containai/config.toml
[template]
suppress_base_warning = true
```

See [Configuration Reference](configuration.md#template-section) for details.

Warning is suppressed in:

- Template builds (`cai run`, `cai build`)
- Doctor checks (`cai doctor`)

## Quick Commands

Because the image ENTRYPOINT is `/sbin/init`, you cannot pass commands directly to `docker run`. Use `cai exec` against a running container instead.

```bash
# From a workspace directory, start a container
cd /path/to/workspace
cai shell  # or: cai shell --container test-contract

# Inspect via exec (from the same workspace, or use --container)
cai exec -- ls -la /home/agent /mnt/agent-data /opt/containai
cai exec -- id agent
cai exec -- systemctl list-unit-files | grep -E 'ssh|docker|containai'

# Target a specific container
cai exec --container test-contract -- id agent

# Or use docker exec directly (with ContainAI's docker context)
docker --context containai-docker exec <container-name> id agent

# Cleanup
cai stop
```

## See Also

- [Configuration Reference](configuration.md) - Full config schema including template options
- [Sync Architecture](sync-architecture.md) - How files sync between host and container
- [Architecture](architecture.md) - Overall system design
