# Container Image Reference

This document describes the container images that ContainAI builds, their contents, and how to modify them. For the complete build pipeline and script reference, see [build-architecture.md](build-architecture.md).

## Image Hierarchy

ContainAI uses a layered image architecture where specialized images inherit from a common base:

```
containai-base (Ubuntu 24.04 + runtimes)
    └── containai (all-agents entrypoint)
            ├── containai-copilot
            ├── containai-codex
            └── containai-claude

containai-proxy (standalone Squid proxy)
containai-log-forwarder (standalone log sidecar)
```

**Design rationale:**
- **Base image** (~3-4 GB) changes rarely; derived images are small deltas
- **All-agents image** supports any agent; specialized images are convenience wrappers
- **Sidecars** are independent; they don't inherit from the agent base

---

## Base Image (`containai-base`)

**Dockerfile:** `docker/base/Dockerfile`

The base image provides a complete development environment with all runtimes pre-installed.

### Contents

| Category | Components |
|----------|------------|
| **OS** | Ubuntu 24.04 LTS |
| **System** | curl, git, build-essential, sudo, zsh, jq, unzip, tmux, gosu |
| **Node.js** | v20.x (via NodeSource) |
| **Python** | 3.12 (system), tomli, pipx, uv |
| **.NET** | SDKs 8, 9, 10 with MAUI/WASM/mobile workloads |
| **PowerShell** | Latest stable |
| **GitHub CLI** | Latest (gh) |
| **Playwright** | Browser dependencies (not browsers) |
| **MCP Servers** | Pre-installed npm packages |
| **User** | `agentuser` (UID 1000, sudo access) |

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Ubuntu 24.04 | Latest LTS with long-term security support |
| UID 1000 | Matches first user on most Linux/WSL2 systems for volume permissions |
| Non-root default | Security best practice; sudo available when needed |
| Full .NET workloads | Enables MAUI, Blazor, WASM, mobile app development |
| No secrets | All authentication via runtime mounts; image is publicly distributable |

### Modifying the Base Image

**Add a system package:**
```dockerfile
RUN apt-get update && \
    apt-get install -y your-package && \
    rm -rf /var/lib/apt/lists/*
```

**Update Node.js version:**
```dockerfile
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs
```

**Add Python version (via deadsnakes):**
```dockerfile
RUN add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y python3.13
```

**Add MCP server:**
```dockerfile
RUN npm install -g @modelcontextprotocol/server-your-server@latest
```

---

## All-Agents Image (`containai`)

**Dockerfile:** `docker/agents/all/Dockerfile`

Adds the entrypoint scripts that configure MCP and validate authentication.

### Scripts Installed

| Script | Location | Purpose |
|--------|----------|---------|
| `entrypoint.sh` | `/usr/local/bin/` | Main startup: git config, MCP setup, auth validation |
| `setup-mcp-configs.sh` | `/usr/local/bin/` | Detects and processes `config.toml` |
| `convert-toml-to-mcp.py` | `/usr/local/bin/` | Converts TOML to agent-specific JSON configs |

### Startup Sequence

```
ENTRYPOINT entrypoint.sh
    ├── Display repository info
    ├── Configure git credential helper (gh CLI)
    ├── Run setup-mcp-configs.sh
    │       └── convert-toml-to-mcp.py (if config.toml exists)
    ├── Load ~/.mcp-secrets.env (if exists)
    ├── Validate authentication
    └── Execute user command (CMD)
```

### MCP Configuration

When `/workspace/config.toml` exists, the converter generates:
- `~/.config/github-copilot/mcp/config.json`
- `~/.config/codex/mcp/config.json`  
- `~/.config/claude/mcp/config.json`

---

## Specialized Agent Images

**Dockerfiles:** `docker/agents/{copilot,codex,claude}/Dockerfile`

Each specialized image adds:
- Agent-specific validation script (`/usr/local/bin/validate-<agent>-auth.sh`)
- Checks for `~/.config/<agent>/` mount
- Sets CMD to launch the agent directly

These are thin wrappers (~10 MB each) for convenience. The all-agents image can run any agent.

---

## Sidecar Images

### Proxy (`containai-proxy`)

**Dockerfile:** `docker/proxy/Dockerfile`

Squid-based HTTP proxy for network isolation. Supports two modes:
- **squid**: Full internet access through proxy
- **restricted**: Allowlist-only (*.github.com, *.nuget.org, etc.)

### Log Forwarder (`containai-log-forwarder`)

**Dockerfile:** `docker/log-forwarder/Dockerfile`

Captures and forwards container logs. Runs as a sidecar alongside agent containers.

---

## Image Sizes

| Image | Approximate Size | Notes |
|-------|------------------|-------|
| `containai-base` | ~3-4 GB | Ubuntu, Node.js, .NET SDKs, Playwright deps |
| `containai` | +50 MB | Entrypoint scripts |
| `containai-{agent}` | +10 MB each | Validation wrapper |
| `containai-proxy` | ~50 MB | Alpine + Squid |
| `containai-log-forwarder` | ~20 MB | Minimal forwarder |

### Optimization Tips

**Combine RUN commands** to reduce layers:
```dockerfile
RUN apt-get update && \
    apt-get install -y package1 package2 && \
    rm -rf /var/lib/apt/lists/*
```

**Remove build dependencies** after use:
```dockerfile
RUN apt-get install -y build-essential && \
    # compile something... && \
    apt-get remove -y build-essential && \
    apt-get autoremove -y
```

**Use multi-stage builds** for compiled artifacts:
```dockerfile
FROM base AS builder
RUN npm install -g large-package

FROM base
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
```

---

## Security

### Build-Time Security

| Control | Implementation |
|---------|----------------|
| No hardcoded secrets | All auth via runtime mounts |
| GPG verification | GitHub CLI package signature checked |
| Official repos only | NodeSource, Microsoft, Ubuntu |
| Cache cleanup | `rm -rf /var/lib/apt/lists/*` after installs |
| Secret scanning | Trivy scans every image before publish |

### Runtime Security

| Control | Implementation |
|---------|----------------|
| Non-root user | `agentuser` by default |
| `no-new-privileges` | Docker security opt |
| Seccomp profile | Blocks ptrace, clone3, mount, setns |
| AppArmor profile | Denies /proc and /sys writes |
| Read-only auth mounts | Credentials mounted read-only |

See [../security/architecture.md](../security/architecture.md) for the complete security model.

---

## Local Development

### Building Images

```bash
# Build all dev images
./scripts/build/build-dev.sh

# Build specific agents
./scripts/build/build-dev.sh --agents copilot,codex

# Manual single-image build
docker build -f docker/base/Dockerfile -t containai-dev-base:devlocal .
```

### Running Secret Scans

```bash
# Install Trivy (or set CONTAINAI_TRIVY_BIN)
# Then scan before publishing:

trivy image --scanners secret --exit-code 1 \
    --severity HIGH,CRITICAL containai-dev-base:devlocal

# Scan all images
for img in containai-dev-base containai-dev containai-dev-copilot; do
    trivy image --scanners secret --exit-code 1 \
        --severity HIGH,CRITICAL "${img}:devlocal"
done
```

### Debugging Build Issues

**Package not found:**
```bash
docker build --no-cache -f docker/base/Dockerfile -t containai-dev-base:devlocal .
```

**Permission errors:**
```dockerfile
COPY --chown=agentuser:agentuser script.sh /usr/local/bin/
```

**Script not executable:**
```dockerfile
RUN chmod +x /usr/local/bin/script.sh
```

---

## See Also

- [build-architecture.md](build-architecture.md) — Complete build pipeline and script reference
- [ghcr-publishing.md](ghcr-publishing.md) — GitHub repository setup and operations
- [contributing.md](contributing.md) — Development workflow and testing
- [../security/architecture.md](../security/architecture.md) — Security model
