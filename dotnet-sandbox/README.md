# dotnet-sandbox

Docker sandbox for .NET 10 development with WASM workloads and Claude Code integration.

## Prerequisites

- Docker Desktop 4.29+ with Docker sandbox feature enabled
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

Volumes are created automatically on first run.

## What's Included

- .NET 10 SDK (LTS) with `wasm-tools` workload
- PowerShell
- Node.js LTS via nvm (with typescript, eslint, prettier)
- Claude Code CLI with credentials
- VS Code Server support

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
- Detached HEAD: `<repo>-detached-<sha>` (e.g., `myproject-detached-abc1234`)
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
| `docker-claude-sandbox-data` | `/mnt/claude-data` | Claude credentials (required, managed by sync-plugins.sh) |
| `docker-claude-plugins` | `/home/agent/.claude/plugins` | Claude Code plugins |
| `dotnet-sandbox-vscode` | `/home/agent/.vscode-server` | VS Code Server data |
| `dotnet-sandbox-nuget` | `/home/agent/.nuget` | NuGet package cache |
| `dotnet-sandbox-gh` | `/home/agent/.config/gh` | GitHub CLI config |

The `docker-claude-sandbox-data` volume must exist before starting. If missing, run:
```bash
../claude/sync-plugins.sh
```

Other volumes are created automatically by `csd`.

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

These scripts detect your OS and use the appropriate source paths:
- macOS: `~/Library/Application Support/Code/User/`
- Linux: `~/.config/Code/User/`
- Windows (WSL): `/mnt/c/Users/<user>/AppData/Roaming/Code/User/`

## Security

Docker sandbox handles all security automatically:
- Capabilities dropping
- seccomp profiles
- Enhanced Container Isolation (ECI)
- User namespace isolation

**No manual security configuration required.** The `csd` wrapper enforces sandbox usage - it blocks if Docker sandbox is unavailable and warns if ECI status cannot be determined.

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

### ECI Detection

Enhanced Container Isolation (ECI) detection is best-effort. The `csd` wrapper warns if ECI status cannot be determined but proceeds anyway.

### VS Code Insiders

VS Code and VS Code Insiders use separate settings directories. Use the appropriate sync script for your installation.

## Troubleshooting

### "Docker sandbox is not available"

Ensure you have:
1. Docker Desktop 4.29 or later
2. Docker sandbox feature enabled in Settings > Features in development

### "Required volume not found"

Run `../claude/sync-plugins.sh` to create required volumes, or manually:
```bash
docker volume create docker-claude-sandbox-data
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
