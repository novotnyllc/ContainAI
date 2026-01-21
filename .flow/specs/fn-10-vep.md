# fn-10-vep: Sysbox-Only Sandbox Runtime with SSH Access

## Overview

**Architectural Pivot**: Remove all Docker Desktop/ECI dependency. ContainAI uses its own Sysbox installation with a dedicated Docker context (`docker-containai`), systemd-based container lifecycle, and SSH-based agent access.

**Value Proposition**: Users get Docker Desktop sandbox-like isolation WITHOUT requiring Docker Desktop Business subscription, plus real SSH access (agent forwarding, port tunneling, IDE integration).

## Problem Statement

- Docker Desktop Business subscription required for sandbox/ECI features
- Users want isolation without enterprise licensing costs
- `docker exec` model lacks SSH features (agent forwarding, tunneling, IDE Remote-SSH)
- Lima socket issue: "socket exists but docker info failed"

## Architectural Model

### Container Lifecycle (Systemd + SSH)

```
┌─────────────────────────────────────────────────────────────┐
│ Container (sysbox-runc runtime)                             │
│  PID 1: /sbin/init (systemd)                                │
│  ├── sshd.service (port 22 internal)                        │
│  ├── dockerd.service (DinD support)                         │
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

**Key changes from previous Phase 7:**
- PID 1: `systemd` (was: `sleep infinity`)
- Agent access: SSH (was: `docker exec`)
- entrypoint.sh logic: migrated to systemd units
- Container naming: per-workspace only (was: per-workspace + per-image)

### Setup Flow

```
cai setup
  ├── Docker context: docker-containai
  │   └── sysbox-runc default, userns mapping, cgroup limits
  ├── SSH key: ~/.config/containai/id_containai (ed25519)
  ├── SSH config: ~/.ssh/containai.d/*.conf
  │   └── Include added to ~/.ssh/config (if not present)
  └── Config: ~/.config/containai/config.toml
```

### Container Launch Flow

```
cai run /workspace
  ├── Find/create container (per-workspace naming)
  ├── Container starts: systemd → sshd ready
  ├── Pick available port (2300-2500 range)
  ├── Add pub key to container's authorized_keys
  ├── Update known_hosts (StrictHostKeyChecking=accept-new)
  ├── Write SSH host config to ~/.ssh/containai.d/{container}.conf
  └── SSH into container, run agent command
```

## Scope

### Phase 1: Remove ECI Dependency ✅ (fn-10-vep.32 done)
- Remove `docker sandbox run` code path from lib/container.sh
- Remove ECI detection logic (lib/eci.sh deprecated)
- Update `_cai_select_context()` to always prefer Sysbox context

### Phase 2: Docker Context (docker-containai)
- Create dedicated Docker context with sysbox-runc enabled by default
- Configure userns mapping in context
- Add cgroup limits (memory, CPU) as defaults

**Acceptance**:
- [ ] `docker-containai` context created via `cai setup`
- [ ] sysbox-runc is default runtime in context
- [ ] userns mapping configured
- [ ] Default cgroup limits (4GB memory, 2 CPUs)
- [ ] `cai doctor` validates context

### Phase 3: SSH Infrastructure
- Generate dedicated SSH key during `cai setup`
- Create `~/.ssh/containai.d/` directory
- Add `Include ~/.ssh/containai.d/*.conf` to `~/.ssh/config`
- Validate OpenSSH version (7.3p1+ for Include)

**Acceptance**:
- [ ] SSH key generated at `~/.config/containai/id_containai`
- [ ] `~/.ssh/containai.d/` created with 700 permissions
- [ ] Include directive added (no duplicates)
- [ ] OpenSSH version check with clear error if < 7.3p1
- [ ] Existing SSH config preserved

### Phase 4: Split Dockerfile (base/sdks/full)
- **base**: Ubuntu 24.04 LTS + systemd + sshd + dockerd + agent user + .bashrc.d
- **sdks**: .NET SDK, Rust, Go, Node (via nvm), Python tools (uv, pipx)
- **full** (default): AI agents (claude, gemini, copilot, codex), gh CLI

**Acceptance**:
- [ ] base layer: systemd as init, sshd running, dockerd available
- [ ] base layer: agent user, /home/agent/.bashrc.d/ pattern
- [ ] base layer: tmux, jq, yq, bun installed
- [ ] sdks layer: .NET SDK (latest LTS), Rust, Go
- [ ] sdks layer: nvm with latest Node LTS
- [ ] sdks layer: uv, pipx installed
- [ ] full layer: all current agents installed
- [ ] full layer: gh CLI installed
- [ ] All layers build successfully
- [ ] Images tagged: containai/base, containai/sdks, containai/full

### Phase 5: Systemd Container Lifecycle
- Replace entrypoint.sh with systemd services
- containai-init.service: workspace setup (one-shot)
- sshd.service: SSH daemon
- dockerd.service: DinD support (optional)
- Use SIGRTMIN+3 for graceful shutdown (100s timeout)

**Acceptance**:
- [ ] PID 1 is `/sbin/init --log-level=err`
- [ ] containai-init.service handles workspace discovery
- [ ] sshd enabled and running by default
- [ ] dockerd enabled when DinD requested
- [ ] `docker stop --time=100` used for shutdown
- [ ] entrypoint.sh removed or deprecated

### Phase 6: SSH-Based Container Access
- Port allocation: find available in 2300-2500 range
- Add pub key to container's `/home/agent/.ssh/authorized_keys`
- Update known_hosts with container's host key
- Generate host config in `~/.ssh/containai.d/{container}.conf`
- `cai shell` calls SSH underneath

**Acceptance**:
- [ ] Port allocation via `ss -tulpn` (not netstat)
- [ ] Port stored in container label `containai.ssh-port`
- [ ] Pub key injected on first connection
- [ ] known_hosts managed with StrictHostKeyChecking=accept-new
- [ ] Host config written per-container
- [ ] `cai shell <ws>` connects via SSH transparently
- [ ] `cai run <ws>` runs agent via SSH
- [ ] `cai run <ws> -- <cmd>` runs arbitrary command via SSH

### Phase 7: SSH Config Options
- Config for agent forwarding, tunneled ports
- `config.toml` [ssh] section for user preferences
- Support VS Code Remote-SSH compatibility

**Acceptance**:
- [ ] `[ssh].forward_agent = true/false` in config.toml
- [ ] `[ssh].local_forward` for port tunneling
- [ ] Generated host configs include user settings
- [ ] VS Code can connect using containai SSH config

### Phase 8: Container Naming (Simplified)
- Per-workspace naming (no per-image complexity)
- Formula: `containai-$(hash "$workspace_path")`
- No `--agent` or `--image-tag` disambiguation needed

**Acceptance**:
- [ ] Container name is workspace-only hash
- [ ] One container per workspace
- [ ] `--fresh` recreates container
- [ ] No multi-container disambiguation needed

### Phase 9: Security Hardening
- cgroup limits enforced (memory, CPU)
- Rely on Docker's default MaskedPaths/ReadonlyPaths
- SSH key-only auth (no passwords)
- sshd_config hardened (PermitRootLogin no, PasswordAuthentication no)

**Acceptance**:
- [ ] Memory limit: 4GB default (configurable)
- [ ] CPU limit: 2 cores default (configurable)
- [ ] NO `systempaths=unconfined`
- [ ] SSH password auth disabled
- [ ] Root SSH login disabled

### Phase 10: DinD Support (existing)
- dockerd auto-start inside Sysbox container
- Inner containers use runc

**Acceptance**:
- [ ] dockerd starts in Sysbox container
- [ ] Inner containers use runc
- [ ] DinD verification test passes

### Phase 11: Distribution & Updates (existing)
- GHCR publishing
- install.sh script
- cai update command

**Acceptance**:
- [ ] GHCR images published (base, sdks, full)
- [ ] install.sh works Linux/macOS
- [ ] `cai update` works

## Out of Scope

- Docker Desktop ECI support (removed)
- Windows native (WSL2 only)
- Aggressive capability dropping (future)
- `cai stop --remove` command
- Hot-reload of config without `--fresh`
- Multi-container per workspace (simplified to single container)
- `--name` flag (removed, was deprecated)

## Quick Commands

```bash
# Setup
cai setup                  # Creates context, SSH key, config dirs

# Diagnostics  
cai doctor                 # Validates sysbox, context, SSH

# Container access
cai run /path/to/workspace           # Launch agent via SSH
cai run /path/to/workspace -- bash   # Run command via SSH
cai shell /path/to/workspace         # Interactive shell via SSH
cai shell --fresh /path/to/workspace # Recreate container, then shell

# SSH config location
cat ~/.ssh/containai.d/containai-*.conf
```

## Migration Notes

- **Breaking**: Containers now use systemd, not sleep infinity
- **Breaking**: Access via SSH, not docker exec
- **Breaking**: One container per workspace (no per-image split)
- **New**: SSH features available (agent forwarding, tunneling)
- **New**: VS Code Remote-SSH compatible
- Existing containers will need `--fresh` to recreate

## Technical Details

### Container Naming

```bash
_cai_container_name() {
  local workspace="$1"
  local normalized
  normalized=$(cd "$workspace" 2>/dev/null && pwd -P || printf '%s' "$workspace")
  
  if command -v shasum >/dev/null 2>&1; then
    printf 'containai-%s' "$(printf '%s' "$normalized" | shasum -a 256 | cut -c1-12)"
  elif command -v sha256sum >/dev/null 2>&1; then
    printf 'containai-%s' "$(printf '%s' "$normalized" | sha256sum | cut -c1-12)"
  else
    printf 'containai-%s' "$(printf '%s' "$normalized" | openssl dgst -sha256 | awk '{print substr($NF,1,12)}')"
  fi
}
```

### Port Allocation

```bash
_cai_find_available_port() {
  local start=${1:-2300}
  local end=${2:-2500}
  
  # Get used ports via ss (more reliable than netstat)
  local used_ports
  used_ports=$(ss -Htan | awk '{print $4}' | grep -oE '[0-9]+$' | sort -nu)
  
  for port in $(seq "$start" "$end"); do
    if ! echo "$used_ports" | grep -qx "$port"; then
      printf '%d' "$port"
      return 0
    fi
  done
  
  return 1  # No port available
}
```

### SSH Host Config Template

```bash
# ~/.ssh/containai.d/containai-{hash}.conf
Host containai-{hash}
    HostName 127.0.0.1
    Port {allocated_port}
    User agent
    IdentityFile ~/.config/containai/id_containai
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.config/containai/known_hosts
    ForwardAgent {yes|no from config}
    # LocalForward lines from config
```

### Container Creation

```bash
docker --context docker-containai run -d \
  --runtime=sysbox-runc \
  --memory=4g --cpus=2 \
  -e CAI_HOST_WORKSPACE="$workspace_resolved" \
  -v "$workspace_resolved:/home/agent/workspace:rw" \
  -v "$data_volume:/mnt/agent-data:rw" \
  -p "${ssh_port}:22" \
  -w /home/agent/workspace \
  --label "containai.workspace=$workspace_resolved" \
  --label "containai.ssh-port=$ssh_port" \
  --label "containai.data-volume=$data_volume" \
  --stop-timeout 100 \
  --name "$(_cai_container_name "$workspace_resolved")" \
  ghcr.io/containai/full:latest
```

### Pub Key Injection

```bash
_cai_inject_ssh_key() {
  local container="$1"
  local pubkey
  pubkey=$(cat ~/.config/containai/id_containai.pub)
  
  docker exec "$container" sh -c "
    mkdir -p /home/agent/.ssh
    chmod 700 /home/agent/.ssh
    echo '$pubkey' >> /home/agent/.ssh/authorized_keys
    chmod 600 /home/agent/.ssh/authorized_keys
    chown -R agent:agent /home/agent/.ssh
  "
}
```

## References

- Sysbox systemd guide: https://github.com/nestybox/sysbox/blob/master/docs/user-guide/systemd.md
- SSH Include directive (OpenSSH 7.3p1+): https://man.openbsd.org/ssh_config
- Docker contexts: https://docs.docker.com/engine/manage-resources/contexts/
- Kernel 5.12+ for ID-mapped mounts
