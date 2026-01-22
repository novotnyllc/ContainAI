# fn-10-vep: Sysbox System Containers with SSH Access

## Overview

ContainAI provides **system containers** - lightweight, VM-like environments that can run systemd, services, and even Docker itself. Using Nestybox's Sysbox runtime, these containers provide stronger isolation than regular containers while enabling capabilities that normally require `--privileged` (like Docker-in-Docker) without the security risks.

**What is a System Container?**

A system container is a container that acts like a light-weight virtual host:
- Runs **systemd as PID 1** (like a real Linux system)
- Can run **multiple services** (sshd, dockerd, your apps)
- Enables **Docker-in-Docker** without `--privileged` flag
- Provides **VM-like isolation** with container efficiency

**Value Proposition**:
- **Secure by default** - Sysbox provides automatic user namespace isolation (root in container → unprivileged on host)
- **Docker-in-Docker built-in** - Agents can build and run containers without `--privileged`
- **Real SSH access** - Agent forwarding, port tunneling, VS Code Remote-SSH
- **Works alongside Docker Desktop** - Separate installation, no conflicts
- **No manual userns config** - Sysbox handles UID/GID mapping automatically via `/etc/subuid` and `/etc/subgid`

## Architecture

```
Host System (may have Docker Desktop)
│
├── Docker Desktop (if present) ─────────────────────────────────
│    └── /var/run/docker.sock (NOT USED by containai)
│
└── ContainAI docker-ce ─────────────────────────────────────────
     ├── Socket: /var/run/containai-docker.sock
     ├── Config: /etc/containai/docker/daemon.json
     ├── Data: /var/lib/containai-docker/
     ├── Runtime: sysbox-runc (default)
     └── Service: containai-docker.service
          │
          └── Sysbox System Container ────────────────────────────
               ├── PID 1: /sbin/init (systemd)
               ├── sshd.service (port 22 → mapped to 2300-2500)
               ├── docker.service (inner Docker, default: sysbox-runc)
               │    └── /var/lib/docker (inside container)
               └── containai-init.service (workspace setup)

               Note: Inner Docker uses sysbox-runc by default for DinD.
               Sysbox enables this without --privileged.
```

### Why Separate docker-ce?

1. **Docker Desktop doesn't support sysbox** - Only supports its own Enhanced Container Isolation (ECI), which has different limitations
2. **System containers need sysbox** - For systemd, DinD without `--privileged`, and VM-like behavior
3. **Sysbox provides comprehensive isolation** - Automatic user namespace mapping, procfs/sysfs virtualization, syscall interception
4. **No conflicts** - ContainAI docker uses its own socket and paths (`/var/run/containai-docker.sock`)

### Container Lifecycle

```
┌─────────────────────────────────────────────────────────────┐
│ Sysbox System Container (created by containai docker-ce)    │
│  Runtime: sysbox-runc                                       │
│  PID 1: /sbin/init (systemd)                                │
│  ├── sshd.service (auto-start, port 22)                     │
│  ├── docker.service (auto-start, DinD with sysbox-runc)     │
│  └── containai-init.service (workspace setup, one-shot)     │
└─────────────────────────────────────────────────────────────┘
         ▲
         │ SSH (port 2300-2500 mapped)
         │
┌────────┴────────┐
│ Host CLI        │
│ cai shell → ssh │
│ cai run → ssh   │
└─────────────────┘
```

### Setup Flow

```
cai setup
  ├── Install docker-ce (if not present)
  │   ├── Socket: /var/run/containai-docker.sock
  │   ├── Config: /etc/containai/docker/daemon.json
  │   ├── Data: /var/lib/containai-docker/
  │   └── Runtime: sysbox-runc (default)
  ├── Install sysbox (if not present)
  │   └── sysbox-mgr, sysbox-fs services
  ├── Docker context: docker-containai
  │   └── Points to containai-docker.sock
  ├── SSH key: ~/.config/containai/id_containai (ed25519)
  ├── SSH config: ~/.ssh/containai.d/*.conf
  │   └── Include added to ~/.ssh/config
  └── Config: ~/.config/containai/config.toml
```

### Container Launch Flow

```
cai run /workspace [--dry-run]
  ├── Use docker-containai context (NOT Docker Desktop)
  ├── Find/create container (supports --name, --data-volume)
  ├── Container starts: systemd → sshd + dockerd ready
  ├── Pick available port (2300-2500 range, configurable)
  ├── Add pub key to container's authorized_keys
  ├── Wait for sshd ready with retry
  ├── Update known_hosts
  ├── Write SSH host config to ~/.ssh/containai.d/{container}.conf
  └── SSH into container, run agent command
```

## Scope

### Phase 1: Clean Slate
- Remove all legacy code paths from lib/container.sh
- Delete lib/eci.sh entirely
- Start fresh with Sysbox-only implementation

### Phase 2: Separate docker-ce Installation
- Install docker-ce alongside Docker Desktop
- Configure isolated socket, config, data directories
- Install and configure sysbox
- Create docker-containai context

**Acceptance**:
- [ ] docker-ce installed with isolated paths
- [ ] Socket at `/var/run/containai-docker.sock`
- [ ] Config at `/etc/containai/docker/daemon.json`
- [ ] Data at `/var/lib/containai-docker/`
- [ ] sysbox-runc is default runtime
- [ ] sysbox services running
- [ ] `docker-containai` context created
- [ ] Docker Desktop (if present) unaffected

### Phase 3: SSH Infrastructure
- Generate dedicated SSH key during `cai setup`
- Create `~/.ssh/containai.d/` directory
- Add `Include ~/.ssh/containai.d/*.conf` to `~/.ssh/config`
- SSH config cleanup command

**Acceptance**:
- [ ] SSH key at `~/.config/containai/id_containai`
- [ ] `~/.ssh/containai.d/` created with 700 permissions
- [ ] Include directive added (no duplicates)
- [ ] `cai ssh cleanup` removes stale configs
- [ ] Auto-cleanup on container removal

### Phase 4: Split Dockerfile (base/sdks/full)
- **base**: Ubuntu 24.04 LTS + systemd + sshd + dockerd + agent user
- **sdks**: .NET SDK, Rust, Go, Node (via nvm), Python tools
- **full** (default): AI agents, gh CLI

**Acceptance**:
- [ ] base layer: systemd as init, sshd + dockerd auto-start
- [ ] base layer: agent user with docker group membership
- [ ] Inner Docker uses runc (not sysbox)
- [ ] DinD works: `docker run hello-world` inside container
- [ ] All layers build successfully

### Phase 5: Systemd Container Lifecycle
- containai-init.service: workspace setup (one-shot)
- sshd.service: auto-start (always)
- docker.service: auto-start (always, for DinD)
- Use SIGRTMIN+3 for graceful shutdown

**Acceptance**:
- [ ] PID 1 is `/sbin/init --log-level=err`
- [ ] sshd enabled and auto-starts
- [ ] dockerd enabled and auto-starts
- [ ] DinD verification passes

### Phase 6: SSH-Based Container Access (Bulletproof)
- Port allocation with graceful exhaustion handling
- sshd readiness retry with exponential backoff
- Auto-recovery from stale host keys
- `cai shell` always connects or provides clear error

**Acceptance**:
- [ ] Port allocation via `ss -tulpn`
- [ ] Clear error if ports exhausted
- [ ] sshd readiness retry (max 30s)
- [ ] Stale known_hosts auto-cleaned on `--fresh`
- [ ] `cai shell` retries on transient failures
- [ ] Auto-recover from stale SSH state

### Phase 7: CLI Enhancements
- `--dry-run` flag
- `--data-volume` and `--name` flags
- `cai import` for hot-reload
- `cai ssh cleanup`

### Phase 8: Dynamic Resource Limits
- cgroup limits default to 50% of host
- Configurable via config.toml

### Phase 9: SSH Config Options
- Agent forwarding, port tunneling
- VS Code Remote-SSH compatibility

### Phase 10: Security Hardening
- SSH key-only auth
- Host socket access blocked by default

### Phase 11: DinD Verification
- Verify nested Docker works
- Test container builds inside container

### Phase 12: Documentation
- README with value prop
- Architecture docs
- Troubleshooting guide

### Phase 13: cai doctor --fix
- Diagnose and auto-remediate issues

### Phase 14: Distribution
- GHCR publishing
- install.sh script

## Quick Commands

```bash
# Setup (installs containai docker-ce + sysbox)
cai setup

# Diagnostics  
cai doctor                 # Validates containai docker, sysbox, SSH
cai doctor --fix           # Auto-fix common issues

# Container access
cai run /path/to/workspace           # Launch agent via SSH
cai run /path/to/workspace -- bash   # Run command via SSH
cai shell /path/to/workspace         # Interactive shell via SSH

# SSH management
cai ssh cleanup                      # Remove stale SSH configs

# Inside the container (DinD works)
docker run hello-world               # Nested containers work
docker build -t myimage .            # Builds work
```

## Technical Details

### Host: ContainAI Docker Configuration

`/etc/containai/docker/daemon.json` - The docker-ce instance on the host:

```json
{
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  },
  "default-runtime": "sysbox-runc",
  "hosts": ["unix:///var/run/containai-docker.sock"],
  "data-root": "/var/lib/containai-docker"
}
```

### Inner Docker Configuration (Inside System Container)

`/etc/docker/daemon.json` - The Docker daemon inside the system container also defaults to sysbox-runc for DinD:

```json
{
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  },
  "default-runtime": "sysbox-runc"
}
```

This allows agents to run containers inside the system container with the same security benefits.

### Container Creation

```bash
docker --context docker-containai run -d \
  --runtime=sysbox-runc \
  --memory="${mem_limit}g" --memory-swap="${mem_limit}g" \
  --cpus="${cpu_limit}" \
  -e CAI_HOST_WORKSPACE="$workspace_resolved" \
  -v "$workspace_resolved:/home/agent/workspace:rw" \
  -v "${data_volume}:/mnt/agent-data:rw" \
  -p "${ssh_port}:22" \
  -w /home/agent/workspace \
  --label "containai.workspace=$workspace_resolved" \
  --label "containai.ssh-port=$ssh_port" \
  --stop-timeout 100 \
  --name "${container_name}" \
  ghcr.io/containai/full:latest
```

## References

- Sysbox: https://github.com/nestybox/sysbox
- Sysbox systemd guide: https://github.com/nestybox/sysbox/blob/master/docs/user-guide/systemd.md
- Sysbox DinD guide: https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md
- SSH Include directive: https://man.openbsd.org/ssh_config
- Docker contexts: https://docs.docker.com/engine/manage-resources/contexts/
