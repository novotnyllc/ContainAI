# fn-10-vep: Sysbox-Only Sandbox Runtime with SSH Access

## Overview

**Architectural Pivot**: Remove all Docker Desktop/ECI dependency. ContainAI uses its own Sysbox installation with a dedicated Docker context (`docker-containai`), systemd-based container lifecycle, and SSH-based agent access.

**Value Proposition**: 
- **Free Docker Desktop sandbox-equivalent isolation** - No Business subscription required
- **Real SSH access** - Agent forwarding, port tunneling, VS Code Remote-SSH
- **Docker-in-Docker built-in** - Run containers inside your dev environment
- **One command setup** - `cai setup && cai run .`

## Problem Statement

- Docker Desktop Business subscription required for sandbox/ECI features ($21/user/month)
- Users want isolation without enterprise licensing costs
- `docker exec` model lacks SSH features (agent forwarding, tunneling, IDE Remote-SSH)
- Lima socket issue: "socket exists but docker info failed"

## Architectural Model

### Container Lifecycle (Systemd + SSH)

```
┌─────────────────────────────────────────────────────────────┐
│ Container (sysbox-runc runtime)                             │
│  PID 1: /sbin/init (systemd)                                │
│  ├── sshd.service (auto-start, port 22)                     │
│  ├── dockerd.service (auto-start, DinD ready)               │
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
- sshd + dockerd: always auto-start (not optional)

### Setup Flow

```
cai setup
  ├── Docker context: docker-containai
  │   └── sysbox-runc default, userns mapping
  ├── SSH key: ~/.config/containai/id_containai (ed25519)
  ├── SSH config: ~/.ssh/containai.d/*.conf
  │   └── Include added to ~/.ssh/config (if not present)
  └── Config: ~/.config/containai/config.toml
```

### Container Launch Flow

```
cai run /workspace [--dry-run]
  ├── Find/create container (supports --name, --data-volume)
  ├── Container starts: systemd → sshd + dockerd ready
  ├── Pick available port (2300-2500 range, configurable)
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

**Acceptance**:
- [ ] `docker-containai` context created via `cai setup`
- [ ] sysbox-runc is default runtime in context
- [ ] userns mapping configured
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
- [ ] base layer: systemd as init, sshd auto-start, dockerd auto-start
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
- sshd.service: auto-start (always)
- dockerd.service: auto-start (always, not optional)
- Use SIGRTMIN+3 for graceful shutdown (100s timeout)

**Acceptance**:
- [ ] PID 1 is `/sbin/init --log-level=err`
- [ ] containai-init.service handles workspace discovery
- [ ] sshd enabled and auto-starts
- [ ] dockerd enabled and auto-starts (not optional)
- [ ] `docker stop --time=100` used for shutdown
- [ ] entrypoint.sh removed or deprecated

### Phase 6: SSH-Based Container Access
- Port allocation: find available in 2300-2500 range (configurable)
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

### Phase 7: CLI Enhancements
- `--dry-run` flag for all commands (show what would happen)
- `--data-volume` flag support (custom data volume name)
- `--name` flag support (custom container name)
- `cai import` for hot-reload of config into running container

**Acceptance**:
- [ ] `--dry-run` shows planned actions without executing
- [ ] `--data-volume` allows custom volume name
- [ ] `--name` allows custom container name
- [ ] `cai import` hot-reloads config (env, credentials) into container
- [ ] All flags documented in help

### Phase 8: Dynamic Resource Limits
- cgroup limits default to 50% of host machine (configurable)
- Auto-detect host resources (memory, CPUs)
- Configurable via `[container]` section in config.toml

**Acceptance**:
- [ ] Auto-detect host memory and CPUs
- [ ] Default: 50% of host memory, 50% of host CPUs
- [ ] Minimum: 2GB memory, 1 CPU
- [ ] Configurable via `[container].memory` and `[container].cpus`
- [ ] `--memory` and `--cpus` CLI flags override config

### Phase 9: SSH Config Options
- Config for agent forwarding, tunneled ports
- `config.toml` [ssh] section for user preferences
- Support VS Code Remote-SSH compatibility

**Acceptance**:
- [ ] `[ssh].forward_agent = true/false` in config.toml
- [ ] `[ssh].local_forward` for port tunneling
- [ ] Generated host configs include user settings
- [ ] VS Code can connect using containai SSH config

### Phase 10: Security Hardening
- Rely on Docker's default MaskedPaths/ReadonlyPaths
- SSH key-only auth (no passwords)
- sshd_config hardened (PermitRootLogin no, PasswordAuthentication no)

**Acceptance**:
- [ ] NO `systempaths=unconfined`
- [ ] SSH password auth disabled
- [ ] Root SSH login disabled

### Phase 11: DinD Support
- dockerd always auto-starts inside Sysbox container
- Inner containers use runc

**Acceptance**:
- [ ] dockerd auto-starts in Sysbox container
- [ ] Inner containers use runc
- [ ] DinD verification test passes

### Phase 12: Documentation Overhaul
- Main README: immediately attractive, clear value prop, quick start
- Architecture docs: updated diagrams, SSH flow, systemd lifecycle
- User guides: comprehensive setup and usage docs

**Acceptance**:
- [ ] README.md: Hero section with value prop
- [ ] README.md: One-liner install and first run
- [ ] README.md: Comparison table (vs Docker Desktop, vs devcontainers)
- [ ] docs/architecture.md: Updated diagrams (mermaid)
- [ ] docs/quickstart.md: Step-by-step with screenshots
- [ ] docs/configuration.md: All config options documented

### Phase 13: cai doctor --fix
- `cai doctor` diagnoses issues
- `cai doctor --fix` attempts auto-remediation

**Acceptance**:
- [ ] `cai doctor` shows all checks with pass/fail
- [ ] `cai doctor --fix` attempts to fix failed checks
- [ ] Fix actions: regenerate SSH key, recreate context, fix permissions
- [ ] Clear output showing what was fixed

### Phase 14: Distribution & Updates
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

## Future Work

- **cai as .NET AOT binary**: Single-file, no dependencies, fast startup
- **cai plugins**: Extensible agent support
- **Remote container support**: SSH to remote Docker hosts

## Quick Commands

```bash
# Setup
cai setup                  # Creates context, SSH key, config dirs

# Diagnostics  
cai doctor                 # Validates sysbox, context, SSH
cai doctor --fix           # Auto-fix common issues

# Container access
cai run /path/to/workspace           # Launch agent via SSH
cai run /path/to/workspace -- bash   # Run command via SSH
cai run --dry-run /path/to/workspace # Show what would happen
cai shell /path/to/workspace         # Interactive shell via SSH
cai shell --fresh /path/to/workspace # Recreate container, then shell

# Custom options
cai run --name mydev --data-volume mydata /path  # Custom names
cai run --memory 8g --cpus 4 /path               # Override resources

# Hot reload
cai import /path/to/workspace        # Reload config into running container

# SSH config location
cat ~/.ssh/containai.d/containai-*.conf
```

## Migration Notes

- **Breaking**: Containers now use systemd, not sleep infinity
- **Breaking**: Access via SSH, not docker exec
- **New**: SSH features available (agent forwarding, tunneling)
- **New**: VS Code Remote-SSH compatible
- **New**: dockerd always running (DinD ready)
- Existing containers will need `--fresh` to recreate

## Technical Details

### Container Naming

Default: `containai-$(hash "$workspace_path")`
Custom: `--name <name>` overrides

```bash
_cai_container_name() {
  local workspace="$1"
  local custom_name="${2:-}"
  
  if [[ -n "$custom_name" ]]; then
    printf '%s' "$custom_name"
    return 0
  fi
  
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

### Dynamic Resource Detection

```bash
_cai_detect_resources() {
  local mem_total_kb mem_total_gb cpus
  
  # Detect memory
  if [[ -f /proc/meminfo ]]; then
    mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_total_gb=$((mem_total_kb / 1024 / 1024))
  elif command -v sysctl >/dev/null 2>&1; then
    mem_total_gb=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
  fi
  
  # Detect CPUs
  cpus=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
  
  # 50% of resources, with minimums
  local mem_limit=$((mem_total_gb / 2))
  local cpu_limit=$((cpus / 2))
  
  [[ $mem_limit -lt 2 ]] && mem_limit=2
  [[ $cpu_limit -lt 1 ]] && cpu_limit=1
  
  printf '%dg %d' "$mem_limit" "$cpu_limit"
}
```

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
  --label "containai.data-volume=$data_volume" \
  --stop-timeout 100 \
  --name "${container_name}" \
  ghcr.io/containai/full:latest
```

## References

- Sysbox systemd guide: https://github.com/nestybox/sysbox/blob/master/docs/user-guide/systemd.md
- SSH Include directive (OpenSSH 7.3p1+): https://man.openbsd.org/ssh_config
- Docker contexts: https://docs.docker.com/engine/manage-resources/contexts/
- Kernel 5.12+ for ID-mapped mounts
