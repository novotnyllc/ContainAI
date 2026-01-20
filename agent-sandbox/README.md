# agent-sandbox

Docker sandbox for .NET 10 development with WASM workloads and Claude Code integration.

## Overview

This sandbox provides:
- .NET 10 SDK (LTS) with `wasm-tools` workload
- PowerShell
- Node.js LTS via nvm (with typescript, eslint, prettier)
- Claude Code CLI with credentials
- VS Code Server support

## Prerequisites

- Docker Desktop 4.50+ with Docker sandbox feature enabled
- macOS, Linux, or Windows (WSL2)

To enable Docker sandbox:
1. Open Docker Desktop Settings
2. Go to "Features in development"
3. Enable "Docker sandbox"

## Quick Start

```bash
# Build the image
./build.sh

# Source ContainAI CLI (adds cai/containai commands)
# Note: requires bash (not zsh or other shells)
source ./containai.sh

# Start sandbox
cai
```

> **Note:** `containai.sh` sources the modular libraries (`lib/*.sh`) to provide
> all ContainAI functionality.

The data volume (`sandbox-agent-data` by default) is created automatically on first run.

**New users** (authenticate later inside container):
```bash
cai
# Then run: claude login (inside the container)
```

**Existing Claude users** (sync plugins and settings from host):
```bash
source ./containai.sh
cai import
```
Note: `cai import` syncs plugins, settings, and credentials from host to volume.

**`cai import` prerequisites:**
- Docker Desktop (Linux, macOS, or Windows WSL2)
- `jq` (JSON parsing)
- `python3` (config file parsing)

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
- Detached HEAD: branch component becomes `detached-<sha>`, so full name is `<repo>-detached-<sha>` (e.g., `myproject-detached-abc1234`)
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
containai sandbox reset   # Equivalent to 'cai sandbox reset' (aliases are interchangeable)
```

## Volumes

### Mounted by `cai`

| Volume Name | Mount Point | Purpose |
|-------------|-------------|---------|
| configurable (default: `sandbox-agent-data`) | `/mnt/agent-data` | Plugins and agent data (created automatically by `cai`) |

The volume name can be configured via:
1. `--data-volume` flag (highest precedence)
2. `CONTAINAI_DATA_VOLUME` environment variable
3. Config file (`[agent].data_volume` or `[workspace."<path>"].data_volume`)
4. Default: `sandbox-agent-data`

### Used by sync scripts

| Volume Name | Used By | Purpose |
|-------------|---------|---------|
| `sandbox-agent-data` | `cai import` | Agent configs synced from host (same as above) |
| `agent-sandbox-vscode` | `sync-all.sh` | VS Code Server settings |
| `agent-sandbox-gh` | `sync-all.sh` | GitHub CLI config |

Note: The `agent-sandbox-vscode` and `agent-sandbox-gh` volumes listed above are populated by `sync-all.sh` but are not currently mounted by `cai`. To use these synced settings inside the container, you would need to manually mount these volumes or modify the container setup. The `sandbox-agent-data` volume is already mounted by `cai`.

## Port Forwarding

Port 5000 is exposed for web development. Access WASM apps at:
```
http://localhost:5000
```

Note: Port publishing requires `docker sandbox run` to support `-p`. If not supported, ports are not published (you'll see a message). Additional ports can be exposed by rebuilding or using `docker run` directly.

## Sync Scripts

Sync host settings into the sandbox before starting:

```bash
# Sync VS Code settings and extensions
./sync-vscode.sh

# Sync VS Code Insiders
./sync-vscode-insiders.sh

# Sync everything (VS Code, Insiders, gh CLI)
./sync-all.sh
```

These scripts detect your OS and use the appropriate source paths.

**VS Code paths:**
- macOS: `~/Library/Application Support/Code/User/`
- Linux: `~/.config/Code/User/`
- Windows (WSL): `/mnt/c/Users/<user>/AppData/Roaming/Code/User/`

**VS Code Insiders paths:**
- macOS: `~/Library/Application Support/Code - Insiders/User/`
- Linux: `~/.config/Code - Insiders/User/`
- Windows (WSL): `/mnt/c/Users/<user>/AppData/Roaming/Code - Insiders/User/`

## Sandbox Detection

The `cai` command detects Docker Sandbox availability before starting a container:

- **Blocks with actionable error** if sandbox is unavailable (command not found, feature disabled, daemon not running, not Docker Desktop)
- **Proceeds** if sandbox is available (even if no containers exist yet)
- **Blocks for unknown failures** with error details (fail-closed for security)

Use `cai --force` to bypass sandbox detection if needed (not recommended).

### Isolation Detection

Isolation detection is best-effort. The `cai` command:
- For ECI: runs ephemeral containers to check uid_map (user namespace) and runtime (sysbox-runc)
- For Sysbox: checks `docker info` for sysbox-runc runtime availability
- **Warns** if isolation is not detected or status is unknown
- **Proceeds anyway** - isolation detection does not block container start

Note: ECI detection requires the `alpine:3.20` image to be available locally (use `--pull=never` to avoid network dependency). If the image is missing, ECI detection fails gracefully with an actionable error message.

Isolation warnings help you know if enhanced isolation is active. Sandbox works without additional isolation; sysbox-runc or rootless mode adds additional hardening when enabled.

To bypass preflight detection (not recommended), use `cai --force`. Note: this only skips the check; `docker sandbox run` must still be functional.

## Security

Docker sandbox provides security isolation through:
- Capabilities dropping
- seccomp profiles
- User namespace isolation
- Enhanced Container Isolation (ECI) - when enabled in Docker Desktop settings

**Note:** ECI is optional and depends on your Docker Desktop configuration. The sandbox provides isolation regardless, but ECI adds additional security boundaries. See [Docker ECI documentation](https://docs.docker.com/security/for-admins/enhanced-container-isolation/) for details.

**No manual security configuration required.** The `cai` command enforces sandbox usage with fail-closed behavior: blocks when sandbox is unavailable or status cannot be verified.

Plain `docker run` is allowed for CI/smoke tests (see Testing below).

### Credential Syncing (`cai import`)

The `cai import` command syncs credentials and configuration from your host to the data volume. Be aware of what gets synced:

| Host Path | Volume Path |
|-----------|-------------|
| `~/.claude/.credentials.json` | `/data/claude/credentials.json` |
| `~/.codex/auth.json` | `/data/codex/auth.json` |
| `~/.gemini/oauth_creds.json` | `/data/gemini/oauth_creds.json` |
| `~/.config/gh/` | `/data/config/gh/` |

Additional non-sensitive configuration (plugins, settings, shell aliases, tmux) is also synced.

**To remove synced credentials and reset the data volume:**
```bash
# Find the volume name (default: sandbox-agent-data)
docker volume ls | grep sandbox

# Remove the volume (container must be stopped first)
docker volume rm sandbox-agent-data

# Or with a custom volume name
docker volume rm <your-volume-name>
```

The volume will be recreated on the next `cai` run. Use `cai import` again to re-sync your settings.

## Container Management

The `cai` command labels containers it creates with `containai.sandbox=containai`. This label identifies containers as "managed by ContainAI" and enables:

- **Ownership verification**: `cai` checks this label before attaching to or restarting containers to prevent accidentally affecting containers with the same name created by other tools
- **Container discovery**: `cai-stop-all` uses this label to find ContainAI-managed containers across all branches/directories

If `docker sandbox run` does not support the `--label` flag, `cai` falls back to image-based detection with a warning. Use `cai --restart` to recreate the container with proper labeling when label support becomes available.

## Testing the Image

### Interactive (via sandbox)

```bash
cai
```

### CI/Smoke Tests (plain docker run)

```bash
# .NET SDK
docker run --rm -u agent agent-sandbox:latest dotnet --list-sdks
docker run --rm -u agent agent-sandbox:latest dotnet workload list

# PowerShell
docker run --rm -u agent agent-sandbox:latest pwsh --version

# Node.js (requires login shell for nvm)
docker run --rm -u agent agent-sandbox:latest bash -lc "node --version"
docker run --rm -u agent agent-sandbox:latest bash -lc "nvm --version"
```

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
./build.sh
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

## Build Options

```bash
./build.sh                    # Standard build
./build.sh --no-cache         # Force rebuild all layers
```

The build script tags the image as both `:latest` and `:<YYYY-MM-DD>` for reproducibility.

## Testing with Dockerfile.test

For CI environments or development testing where you need to build and test ContainAI images inside a container with its own Docker daemon and Sysbox runtime, use `Dockerfile.test`.

### Overview

`Dockerfile.test` creates a testing container with:
- Its own Docker daemon (dockerd)
- Sysbox runtime installed (available as `--runtime=sysbox-runc`)
- Isolated socket at `/var/run/docker-test.sock` (does NOT interfere with host Docker)

### Build and Run

```bash
# Build the test image (from repo root)
docker build -t containai-test -f agent-sandbox/Dockerfile.test agent-sandbox/

# Or build from the agent-sandbox directory
cd agent-sandbox
docker build -t containai-test -f Dockerfile.test .

# Run the built-in verification tests (requires --privileged for nested Docker)
docker run --privileged containai-test /usr/local/bin/test-docker-sysbox.sh

# Interactive testing
docker run --privileged -it containai-test

# Mount workspace and run custom commands
docker run --privileged -v $(pwd):/workspace -w /workspace containai-test \
    bash -c "docker build -t myimage . && docker run --rm --runtime=sysbox-runc myimage"
```

### Features

- **Context isolation**: Uses `/var/run/docker-test.sock` to avoid conflicts with any host Docker socket
- **Sysbox runtime**: Available as `--runtime=sysbox-runc` (NOT the default)
- **Build support**: Can build Docker images inside the container
- **Nested containers**: Can run containers (including Sysbox containers) inside the test container

### Use Cases

1. **CI pipelines**: Build and test ContainAI images in isolated environment
2. **Development**: Test Sysbox integration without affecting host Docker setup
3. **Sysbox runtime testing**: Verify containers run correctly with `--runtime=sysbox-runc`

**Note:** The container sets `DOCKER_HOST` to the test socket. To test Docker context selection
(e.g., `--context containai-secure`), clear the environment variable first:
```bash
env -u DOCKER_HOST docker --context containai-secure info
```

### Requirements

- BuildKit enabled (Docker 23.0+ has it by default, or set `DOCKER_BUILDKIT=1`)
- `--privileged` flag is required for nested Docker
- Host must support Linux kernel features needed by Sysbox (kernel 5.4+)

### Startup Script

The container runs `/usr/local/bin/start-test-docker.sh` on startup, which:
1. Starts Sysbox services (sysbox-mgr, sysbox-fs)
2. Starts dockerd on `/var/run/docker-test.sock`
3. Waits for Docker to be ready
4. Executes the command passed to the container

### Test Helper

A test helper script is included at `/usr/local/bin/test-docker-sysbox.sh` that verifies:
- Docker daemon is running
- Available runtimes (should include sysbox-runc)
- Container runs with default runtime
- Container runs with Sysbox runtime
- Image builds work
