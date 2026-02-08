# ContainAI Source (src/)

> **⚠️ Path Changed:** This directory was formerly `agent-sandbox/`. A symlink at `agent-sandbox/` exists for backward compatibility. Please update your scripts to use `src/` paths. The `agent-sandbox/` symlink will be removed in v2.0.

Source code for ContainAI - the secure Docker sandbox for AI coding agents.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Commands](#commands)
- [Volumes](#volumes)
- [Port Forwarding](#port-forwarding)
- [Security](#security)
- [Container Management](#container-management)
- [Docker-in-Docker (DinD)](#docker-in-docker-dind)
- [Testing the Image](#testing-the-image)
- [Build Options](#build-options)
- [Testing with Dockerfile.test](#testing-with-dockerfiletest)
- [Known Limitations](#known-limitations)
- [Troubleshooting](#troubleshooting)

## Overview

This directory contains the ContainAI sandbox implementation:

**Container Contents:**
- .NET 10 SDK (LTS) with `wasm-tools` workload
- PowerShell
- Node.js LTS via nvm (with typescript, eslint, prettier)
- Claude Code CLI and credentials
- VS Code Server support

**Key Files:**
- `cai/Program.cs` - Native `.NET 10` CLI entry point
- `ContainAI.Cli/` - `System.CommandLine` routing and command surface
- `container/Dockerfile*` - Container image definitions
- `cai` native runtime commands (`cai system ...`) - Container init/link orchestration

**Manifest Files (`manifests/`):**

Per-agent manifest files define what config files are synced between host and container:

| File | Purpose |
|------|---------|
| `00-common.toml` | Shared entries (fonts, agents directory) |
| `01-shell.toml` | Shell configuration (bash, zsh, inputrc) |
| `02-git.toml` | Git configuration |
| `03-gh.toml` | GitHub CLI |
| `04-editors.toml` | Vim, Neovim |
| `05-vscode.toml` | VS Code Server |
| `06-ssh.toml` | SSH (disabled by default) |
| `07-tmux.toml` | tmux |
| `08-prompt.toml` | Starship, oh-my-posh |
| `10-claude.toml` | Claude Code agent |
| `11-codex.toml` | Codex agent |
| `12-gemini.toml` | Gemini agent |
| `13-copilot.toml` | GitHub Copilot |
| `14-opencode.toml` | OpenCode |
| `15-kimi.toml` | Kimi CLI |
| `16-pi.toml` | Pi agent |
| `17-aider.toml` | Aider |
| `18-continue.toml` | Continue |
| `19-cursor.toml` | Cursor |

Numeric prefixes ensure deterministic processing order. See [docs/adding-agents.md](../docs/adding-agents.md) for the manifest format.

## Quick Start

### Prerequisites

- Docker Desktop 4.50+ with sandbox feature, **OR** Docker Engine with Sysbox runtime
- macOS, Linux, or Windows (WSL2)
- .NET SDK 10.0+

### Enable Docker Sandbox (Docker Desktop)

1. Open Docker Desktop Settings
2. Go to "Features in development"
3. Enable "Docker sandbox"

### Start the Sandbox

```bash
# Build the image (first time only)
dotnet build ./cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest

# Start sandbox in your project directory
cd /path/to/your/project
cai
```

The data volume (`containai-data` by default) is created automatically on first run.

**New users** (authenticate inside container):
```bash
cai
# Inside the container, run: claude login
```

**Existing users** (sync settings from host):
```bash
cai import
```

`cai import` syncs plugins, settings, and credentials from host to the data volume. Supported on Linux, macOS, and Windows (WSL2).

**`cai import` prerequisites:**
- Docker Desktop (Linux, macOS, or Windows WSL2)
- No external parser executables required (`cai` uses in-process `.NET` JSON/TOML/YAML parsing)

**macOS users:** Docker Desktop must have file-sharing enabled for your home directory (`$HOME`). This is typically enabled by default in Settings > Resources > File sharing.

**Using a custom volume name:**
```bash
# Via CLI flag (highest precedence)
cai --data-volume my-custom-volume
cai import --data-volume my-custom-volume

# Via environment variable
CONTAINAI_DATA_VOLUME=my-custom-volume cai

# Via config file (~/.config/containai/config.toml or .containai/config.toml)
# [agent]
# data_volume = "my-custom-volume"
cai --config ~/.config/containai/config.toml
```

## Commands

ContainAI provides `cai` (short) and `containai` (full) as primary commands.

### Basic Usage

```bash
cai                               # Start or attach to sandbox
cai --restart                     # Force recreate container
cai --data-volume custom-vol      # Use a specific data volume
cai --config /path/to/config.toml # Use a specific config file
cai --force                       # Skip sandbox availability check (not recommended)
cai --help                        # Show help
```

### Container Naming

Containers are named automatically based on your git context:
- In a git repo: `<repo>-<branch>` (e.g., `myproject-main`)
- Detached HEAD: `<repo>-detached-<sha>` (e.g., `myproject-detached-abc1234`)
- Outside git repo: directory name (e.g., `myproject`)

Names are sanitized (lowercase, alphanumeric + dashes, max 63 chars).

### Auto-Attach Behavior

- If a container with the same name is running, `cai` attaches to it
- If the container exists but is stopped, `cai` starts it
- Use `cai --restart` to force a fresh container

### Related Commands

```bash
cai-stop-all              # Interactive selection to stop sandbox containers
cai-shell                 # Start sandbox with interactive shell instead of agent
caid                      # Start sandbox in detached mode
cai sandbox reset         # Remove sandbox for workspace (config changes require this)
containai sandbox reset   # Equivalent to 'cai sandbox reset'
```

## Volumes

### Mounted by `cai`

| Volume Name | Mount Point | Purpose |
|-------------|-------------|---------|
| configurable (default: `containai-data`) | `/mnt/agent-data` | Plugins and agent data |

The volume name can be configured via:
1. `--data-volume` flag (highest precedence)
2. `CONTAINAI_DATA_VOLUME` environment variable
3. Config file (`[agent].data_volume` or `[workspace."<path>"].data_volume`)
4. Default: `containai-data`

## Port Forwarding

Port 5000 is exposed for web development. Access WASM apps at:
```
http://localhost:5000
```

Note: Port publishing requires `docker sandbox run` to support `-p`. If not supported, ports are not published (you'll see a message). Additional ports can be exposed by rebuilding or using `docker --context containai-docker run` directly.

## Security

Docker sandbox provides security isolation through:
- Capabilities dropping
- seccomp profiles
- User namespace isolation
- Enhanced Container Isolation (ECI) - when enabled in Docker Desktop settings

**Note:** ECI is optional and depends on your Docker Desktop configuration. The sandbox provides isolation regardless, but ECI adds additional security boundaries. See [Docker ECI documentation](https://docs.docker.com/security/for-admins/enhanced-container-isolation/) for details.

**No manual security configuration required.** The `cai` command enforces sandbox usage with fail-closed behavior: blocks when sandbox is unavailable or status cannot be verified.

Plain `docker --context containai-docker run` is allowed for CI/smoke tests (see Testing below).

### Sandbox Detection

The `cai` command detects Docker Sandbox availability before starting a container:

- **Blocks with actionable error** if sandbox is unavailable (command not found, feature disabled, daemon not running, not Docker Desktop)
- **Proceeds** if sandbox is available (even if no containers exist yet)
- **Blocks for unknown failures** with error details (fail-closed for security)

Use `cai --force` to bypass sandbox detection if needed (not recommended).

### Isolation Detection

Isolation detection is best-effort. The `cai` command:
- For ECI: runs ephemeral containers to check uid_map (user namespace) and runtime (sysbox-runc)
- For Sysbox: checks `docker --context containai-docker info` for sysbox-runc runtime availability
- **Warns** if isolation is not detected or status is unknown
- **Proceeds anyway** - isolation detection does not block container start

Note: ECI detection requires the `alpine:3.20` image to be available locally (use `--pull=never` to avoid network dependency). If the image is missing, ECI detection fails gracefully with an actionable error message.

### Credential Syncing (`cai import`)

The `cai import` command syncs credentials and configuration from your host to the data volume:

| Host Path | Volume Path (relative to volume root) |
|-----------|---------------------------------------|
| `~/.claude/.credentials.json` | `claude/credentials.json` |
| `~/.codex/auth.json` | `codex/auth.json` |
| `~/.gemini/oauth_creds.json` | `gemini/oauth_creds.json` |
| `~/.local/share/opencode/auth.json` | `local/share/opencode/auth.json` |
| `~/.config/gh/` | `config/gh/` |

Inside the sandbox container, the volume mounts at `/mnt/agent-data` (e.g., `/mnt/agent-data/claude/credentials.json`).

Additional configuration (plugins, settings, shell aliases, tmux, copilot) is also synced. For the complete list of synced paths, see `src/manifests/*.toml` and validate with `cai manifest check src/manifests`.

**To remove synced credentials and reset the data volume:**
```bash
# Stop containers first
cai-stop-all                    # Interactive selection
cai sandbox reset               # Remove sandbox for current workspace

# Remove the volume
docker --context containai-docker volume rm containai-data

# Or with a custom volume name
docker --context containai-docker volume rm <your-volume-name>
```

The volume will be recreated on the next `cai` run. Use `cai import` again to re-sync your settings.

## Container Management

The `cai` command labels containers it creates with `containai.sandbox=containai`. This label enables:

- **Ownership verification**: `cai` checks this label before attaching to or restarting containers
- **Container discovery**: `cai-stop-all` uses this label to find ContainAI-managed containers

If `docker sandbox run` does not support the `--label` flag, `cai` falls back to image-based detection with a warning.

## Docker-in-Docker (DinD)

For testing or CI scenarios that require running Docker inside a container, use `container/Dockerfile.test` which provides a complete Docker-in-Docker environment.

### Runtime Model

When using `container/Dockerfile.test`:

```
Host (containai docker-ce + sysbox)
  └── Test container (runs with --runtime=sysbox-runc)
        └── dockerd on /var/run/docker-test.sock
              └── Inner containers (use sysbox-runc by default)
```

**Key points:**
- `container/Dockerfile.test` installs the sysbox-runc binary but does NOT start sysbox services
- The test container must be run with `--runtime=sysbox-runc` (NOT `--privileged`)
- The host's sysbox runtime provides coordination and isolation
- Inner Docker uses sysbox-runc as its default runtime for nested containers
- The test socket (`/var/run/docker-test.sock`) avoids conflicts with host Docker

**Usage:**
```bash
# Build the test image
docker --context containai-docker build -t containai-test -f src/container/Dockerfile.test src/

# Run with sysbox runtime (NOT --privileged)
docker --context containai-secure run --rm --runtime=sysbox-runc containai-test
```

### Main Image DinD

The main ContainAI image (`container/Dockerfile.base` and layered images) supports Docker-in-Docker when run with `--runtime=sysbox-runc`. The image includes sysbox and configures inner Docker with sysbox-runc as the default runtime for nested container security.

## Testing the Image

### Interactive (via sandbox)

```bash
cai
```

### CI/Smoke Tests (plain docker --context containai-docker run)

```bash
# .NET SDK
docker --context containai-docker run --rm -u agent containai:latest dotnet --list-sdks
docker --context containai-docker run --rm -u agent containai:latest dotnet workload list

# PowerShell
docker --context containai-docker run --rm -u agent containai:latest pwsh --version

# Node.js (requires login shell for nvm)
docker --context containai-docker run --rm -u agent containai:latest bash -lc "node --version"
docker --context containai-docker run --rm -u agent containai:latest bash -lc "nvm --version"
```

## Build Options

```bash
dotnet build ./cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest
dotnet build ./cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=base -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest
dotnet build ./cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=ghcr.io/ORG/containai -p:ContainAIImageTag=nightly -p:ContainAIPlatforms=linux/amd64,linux/arm64 -p:ContainAIPush=true -p:ContainAIBuildSetup=true
dotnet publish ./cai/cai.csproj -c Release -r linux-x64 -p:PublishAot=true -p:PublishTrimmed=true
```

The MSBuild image target supports layer-specific builds (`ContainAILayer`), multi-arch (`ContainAIPlatforms`), and optional buildx setup (`ContainAIBuildSetup=true`).

## Testing with Dockerfile.test

For CI environments or development testing where you need to build and test ContainAI images inside a container with its own Docker daemon, use `container/Dockerfile.test`.

### Overview

`container/Dockerfile.test` creates a testing container with:
- Its own Docker daemon (dockerd)
- Sysbox-runc binary (for inner Docker to use as default runtime)
- Isolated socket at `/var/run/docker-test.sock` (does NOT interfere with host Docker)

Note: Sysbox services (sysbox-mgr, sysbox-fs) are NOT started - the host's sysbox runtime provides coordination.

### Build and Run

```bash
# Build the test image (from repo root)
docker --context containai-docker build -t containai-test -f src/container/Dockerfile.test src/

# Or build from the src directory
cd src
docker --context containai-docker build -t containai-test -f container/Dockerfile.test .

# Run the built-in verification tests (use --runtime=sysbox-runc, NOT --privileged)
docker --context containai-secure run --rm --runtime=sysbox-runc containai-test

# Interactive testing
docker --context containai-secure run --rm -it --runtime=sysbox-runc containai-test bash

# Mount workspace and run custom commands
docker --context containai-secure run --rm --runtime=sysbox-runc \
    -v $(pwd):/workspace -w /workspace containai-test \
    bash -c "docker build -t myimage . && docker run --rm myimage"
```

### Features

- **Context isolation**: Uses `/var/run/docker-test.sock` to avoid conflicts with any host Docker socket
- **Sysbox runtime**: Inner Docker uses sysbox-runc as default for nested containers
- **No --privileged**: Uses `--runtime=sysbox-runc` for secure DinD (host sysbox provides coordination)
- **Build support**: Can build Docker images inside the container
- **Nested containers**: Can run containers (with sysbox-runc) inside the test container

### Use Cases

1. **CI pipelines**: Build and test ContainAI images in isolated environment
2. **Development**: Test Docker operations without affecting host Docker setup
3. **Sysbox testing**: Verify containers run correctly with sysbox-runc runtime

**Note:** The container sets `DOCKER_HOST` to the test socket. To test Docker context selection (e.g., `--context containai-secure`), clear the environment variable first:
```bash
env -u DOCKER_HOST docker --context containai-secure info
```

### Requirements

- BuildKit enabled (Docker 23.0+ has it by default, or set `DOCKER_BUILDKIT=1`)
- Host must have sysbox installed and `containai-secure` context configured (run `cai setup`)
- Must use `--runtime=sysbox-runc` flag (NOT `--privileged`)
- Host must support Linux kernel features needed by Sysbox (kernel 5.4+)

### Startup Script

The container runs `/usr/local/bin/start-dockerd.sh` on startup, which:
1. Starts dockerd on `/var/run/docker-test.sock`
2. Waits for Docker to be ready (with diagnostics on failure)
3. Executes the command passed to the container

### Test Helper

A test helper script is included at `/usr/local/bin/test-dind.sh` that verifies:
- Docker daemon is running
- Available runtimes (should include sysbox-runc)
- Default runtime is sysbox-runc (hard failure if not)
- Container runs with default runtime
- Container runs with explicit sysbox-runc runtime
- Image builds work

## Known Limitations

### nvm Symlinks

The image creates symlinks at `/usr/local/bin/node`, `/usr/local/bin/npm`, `/usr/local/bin/npx` pointing to the Node.js version installed at build time. If you run `nvm use` to switch versions, these symlinks become stale.

For correct nvm-aware access, use a login shell:
```bash
bash -lc "node --version"
```

### VS Code Insiders

VS Code and VS Code Insiders use separate settings directories and host paths. Use the appropriate sync script for your installation (`sync-vscode.sh` vs `sync-vscode-insiders.sh`).

## Troubleshooting

### "Docker sandbox is not available"

Ensure you have:
1. Docker Desktop 4.50 or later
2. Docker sandbox feature enabled in Settings > Features in development

### "Image not found"

Build the image first:
```bash
dotnet build ./cai/cai.csproj -t:BuildContainAIImages -p:ContainAILayer=all -p:ContainAIImagePrefix=containai -p:ContainAIImageTag=latest
```

### Node.js commands not found

Use a login shell to load nvm:
```bash
bash -lc "node --version"
```

Or use the symlinked version directly:
```bash
/usr/local/bin/node --version
```
