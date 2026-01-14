# dotnet-sandbox

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

# Source aliases (adds csd command)
source ./aliases.sh

# Start sandbox
csd
```

Most volumes are created automatically on first run. The `docker-claude-sandbox-data` volume is required and must exist before starting:

**Option 1** (new users without Claude on host - creates empty volume):
```bash
docker volume create docker-claude-sandbox-data
# Then authenticate inside the container with: claude login
```

**Option 2** (existing Claude users - syncs credentials and plugins):
```bash
../claude/sync-plugins.sh
```

## The `csd` Command

`csd` (Claude Sandbox Dotnet) is the main command for working with the sandbox.

### Basic Usage

```bash
csd              # Start or attach to sandbox
csd --restart    # Force recreate container
csd --force      # Skip sandbox availability check (not recommended)
csd --help       # Show help
```

### Container Naming

Containers are named automatically based on your git context:
- In a git repo: `<repo>-<branch>` (e.g., `myproject-main`)
- Detached HEAD: branch component becomes `detached-<sha>`, so full name is `<repo>-detached-<sha>` (e.g., `myproject-detached-abc1234`)
- Outside git repo: directory name (e.g., `myproject`)

Names are sanitized (lowercase, alphanumeric + dashes, max 63 chars).

### Auto-Attach Behavior

- If a container with the same name is running, `csd` attaches to it
- If the container exists but is stopped, `csd` starts it
- Use `csd --restart` to force a fresh container

### Stopping Containers

```bash
csd-stop-all     # Interactive selection to stop sandbox containers
```

## Volumes

| Volume Name | Mount Point | Purpose |
|-------------|-------------|---------|
| `docker-claude-sandbox-data` | `/mnt/claude-data` | Claude credentials (required - create empty or use sync-plugins.sh, do not manually edit contents) |
| `docker-claude-plugins` | `/home/agent/.claude/plugins` | Claude Code plugins |
| `dotnet-sandbox-vscode` | `/home/agent/.vscode-server` | VS Code Server data |
| `dotnet-sandbox-nuget` | `/home/agent/.nuget` | NuGet package cache |
| `dotnet-sandbox-gh` | `/home/agent/.config/gh` | GitHub CLI config |

The `docker-claude-sandbox-data` volume must exist before starting (see Quick Start for options). This volume stores Claude credentials and should not be manually edited. Other volumes are created automatically by `csd`.

## Port Forwarding

Ports 5000-5010 are exposed for web development. Access WASM apps at:
```
http://localhost:5000
```

Note: Port publishing requires `docker sandbox run` to support `-p`. If not supported, ports are not published (you'll see a message).

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

The `csd` wrapper detects Docker Sandbox availability before starting a container:

- **Blocks with actionable error** if sandbox is unavailable (command not found, feature disabled, daemon not running)
- **Proceeds** if sandbox is available (even if no containers exist yet)
- **Shows actual error** for unknown failures to help diagnose issues

### ECI Detection

ECI (Enhanced Container Isolation) detection is best-effort. The `csd` wrapper:
- Checks `docker info` for ECI indicators (userns, rootless, eci options)
- **Warns** if ECI is not detected or status is unknown
- **Proceeds anyway** - ECI detection does not block container start

ECI warnings help you know if enhanced isolation is active. Sandbox works without ECI; ECI adds additional hardening when enabled.

To bypass preflight detection (not recommended), use `csd --force`. Note: this only skips the check; `docker sandbox run` must still be functional.

## Security

Docker sandbox provides security isolation through:
- Capabilities dropping
- seccomp profiles
- User namespace isolation
- Enhanced Container Isolation (ECI) - when enabled in Docker Desktop settings

**Note:** ECI is optional and depends on your Docker Desktop configuration. The sandbox provides isolation regardless, but ECI adds additional security boundaries. See [Docker ECI documentation](https://docs.docker.com/security/for-admins/enhanced-container-isolation/) for details.

**No manual security configuration required.** The `csd` wrapper enforces sandbox usage: blocks when sandbox is definitely unavailable, and warns but attempts to proceed when status is unknown.

Plain `docker run` is allowed for CI/smoke tests (see Testing below).

## Testing the Image

### Interactive (via sandbox)

```bash
csd
```

### CI/Smoke Tests (plain docker run)

```bash
# .NET SDK
docker run --rm -u agent dotnet-sandbox:latest dotnet --list-sdks
docker run --rm -u agent dotnet-sandbox:latest dotnet workload list

# PowerShell
docker run --rm -u agent dotnet-sandbox:latest pwsh --version

# Node.js (requires login shell for nvm)
docker run --rm -u agent dotnet-sandbox:latest bash -lc "node --version"
docker run --rm -u agent dotnet-sandbox:latest bash -lc "nvm --version"
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

### "Required volume not found"

Create the required credentials volume using one of these options:

**Option 1** (new users - authenticate later):
```bash
docker volume create docker-claude-sandbox-data
# Then run: claude login (inside the container)
```

**Option 2** (sync existing host credentials):
```bash
../claude/sync-plugins.sh
```

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
