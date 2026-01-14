# .NET 10 WASM Docker Sandbox

## Overview

A Docker image template for a development sandbox with .NET SDK 10 and WASM workloads.

**Primary workflow**: `docker sandbox run` with full security isolation

**Build Strategy**: Single-stage Dockerfile based on `docker/sandbox-templates:claude-code` with .NET SDK 10 installed directly. The full SDK is required in the final image for development, so multi-stage provides no benefit.

## Scope

**In Scope:**
- New `dotnet-wasm/` directory with Dockerfile
- .NET SDK 10 with `wasm-tools` workload pre-installed
- Early container startup check for Docker Sandbox detection and ECI status
- Volume initialization script (for ownership fix)
- Named volumes for persistent data (5 total)
- Claude extension configured to use local `claude` CLI
- Helper aliases (`claude-sandbox-dotnet`) with automatic container naming
- VS Code settings pre-population script (best-effort)
- Documentation (README.md)

**Out of Scope:**
- Manual seccomp/capabilities configuration (docker sandbox handles this)
- OpenAI Codex CLI integration (Phase 2)
- Gemini CLI integration (Phase 2)
- Depending on docker-claude-* images (use only docker/sandbox-templates:claude-code)

## Approach

### Architecture Decisions

1. **Docker Sandbox Workflow**:
   - Uses `docker sandbox run` with full security isolation
   - All security handled automatically (ECI, capabilities, seccomp)
   - Alias: `claude-sandbox-dotnet`
   - **Container naming**: Defaults to `<repo-name>-<branch>` for easy identification

2. **Single-Stage Build**:
   - Base: `docker/sandbox-templates:claude-code`
   - **Fail fast** if base is not Ubuntu Noble (deps are distro-specific)
   - Install .NET SDK 10 from Microsoft apt repo
   - Install wasm-tools workload
   - Verify with `dotnet --info` (fails if deps missing)

   Single-stage is simpler and the full SDK must be in the final image anyway for development work.

3. **Container Startup Environment Detection**:

   On container startup, detect and report:
   - Whether running in Docker Sandbox (vs plain Docker)
   - ECI (Enhanced Container Isolation) status
   - Recommend enabling ECI if not detected

   This provides early feedback to users about their security posture.

4. **Volume Initialization Required**:

   Docker volume ownership is tricky - Dockerfile `chown` only helps new volumes. Users MUST run `init-volumes.sh` once before first use to fix ownership on all 5 volumes.

5. **Base Image Requirement**:

   `docker/sandbox-templates:claude-code` MUST be Ubuntu Noble (24.04). The Dockerfile fails fast if not. Before building, verify:
   ```bash
   docker run --rm docker/sandbox-templates:claude-code cat /etc/os-release | grep VERSION_CODENAME
   ```

6. **Volume Strategy** (5 volumes total):

   | Volume | Mount Point | Purpose |
   |--------|-------------|---------|
   | `docker-vscode-server` | `/home/agent/.vscode-server` | VS Code Server |
   | `docker-github-copilot` | `/home/agent/.config/github-copilot` | Copilot CLI auth |
   | `docker-dotnet-packages` | `/home/agent/.nuget/packages` | NuGet package cache |
   | `docker-claude-plugins` | `/home/agent/.claude/plugins` | Claude plugins |
   | `docker-claude-sandbox-data` | `/mnt/claude-data` | **REQUIRED** - Claude credentials |

7. **Helper Scripts**:
   - `build.sh` - Build and tag image
   - `init-volumes.sh` - Initialize all 5 volumes with correct ownership
   - `aliases.sh` - Shell aliases for sandbox commands (with auto container naming)
   - `sync-vscode-data.sh` - Pre-populate VS Code settings (best-effort)
   - `check-sandbox.sh` - Detect Docker Sandbox and ECI status

## Quick Commands

```bash
# Build the image
./dotnet-wasm/build.sh

# Initialize volumes (first time only)
./dotnet-wasm/init-volumes.sh

# Source aliases
source ./dotnet-wasm/aliases.sh

# Start sandbox (all 5 volumes, named after repo-branch)
claude-sandbox-dotnet

# Smoke tests (CI/verification)
docker run --rm -u agent dotnet-wasm:latest dotnet --list-sdks
docker run --rm -u agent dotnet-wasm:latest dotnet workload list

# Stop ALL sandboxes
claude-sandbox-stop-all
```

## Acceptance Criteria

- [ ] `docker build` succeeds with Dockerfile
- [ ] Build fails with clear error if base image is not Ubuntu Noble
- [ ] `dotnet --version` (as agent) outputs 10.x
- [ ] `dotnet workload list` (as agent) shows `wasm-tools`
- [ ] `command -v claude && claude --version` (as agent) succeeds
- [ ] Container runs as `uid=1000(agent)`
- [ ] `docker sandbox run ... dotnet-wasm` starts successfully
- [ ] Container name defaults to `<repo-name>-<branch>`
- [ ] Container startup detects Docker Sandbox vs plain Docker
- [ ] Container startup reports ECI status with recommendation if disabled
- [ ] `init-volumes.sh` creates and fixes ownership for all 5 volumes
- [ ] `claude-sandbox-dotnet` alias includes all 5 volumes
- [ ] Blazor WASM project creates and builds successfully
- [ ] Uno Platform WASM project creates and builds successfully
- [ ] README documents: run init-volumes.sh before first use
- [ ] Image does NOT depend on any docker-claude-* images

## Security Considerations

**Docker sandbox handles all security automatically:**
- Capabilities dropping
- seccomp profiles
- ECI (Enhanced Container Isolation)
- User namespace isolation

**We do NOT configure:**
- `--cap-drop`, `--cap-add`
- `--security-opt=seccomp=...`
- Manual security flags in runArgs

## References

- Existing scripts: `claude/update-claude-sandbox.sh`, `claude/sync-plugins.sh`
- Docker sandbox commands: `docker sandbox run`, `docker sandbox ls`, `docker sandbox rm`
- Volume patterns: `claude/sync-plugins.sh:21-23`
- Uno Platform: https://platform.uno/
