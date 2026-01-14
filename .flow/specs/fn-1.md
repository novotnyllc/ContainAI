# .NET Docker Sandbox

## Overview

A Docker image template for a development sandbox with .NET SDK (latest LTS), Node.js, and WASM workloads.

**Primary workflow**: `docker sandbox run` with full security isolation
**Alias**: `csd` (Claude Sandbox Dotnet)

**Build Strategy**: Single-stage Dockerfile based on `docker/sandbox-templates:claude-code` with .NET SDK installed via `dotnet-install.sh` script. Single RUN for smallest image size.

## Scope

**In Scope:**
- New `dotnet-sandbox/` directory with Dockerfile
- .NET SDK (latest LTS) via dotnet-install.sh with `wasm-tools` workload
- PowerShell installed via Microsoft's recommended method
- Node.js with nvm + common dev tools (typescript, eslint, prettier)
- Container startup check: blocks if not Docker Sandbox, warns if ECI disabled
- Zero-friction startup: volumes auto-created with correct permissions
- Named volumes (strategy TBD via research task)
- Claude extension configured to use local `claude` CLI
- Helper alias `csd` with auto-attach and container naming
- VS Code settings sync scripts (sync-vscode.sh, sync-vscode-insiders.sh, sync-all.sh)
- gh CLI config sync
- Documentation (README.md)

**Out of Scope:**
- Manual seccomp/capabilities configuration (docker sandbox handles this)
- Playwright/browser automation (user adds via plugin/MCP if needed)
- Apt-based .NET installation (use dotnet-install.sh only)
- OpenAI Codex CLI integration (Phase 2)
- Gemini CLI integration (Phase 2)

## Approach

### Architecture Decisions

1. **Docker Sandbox Workflow**:
   - Uses `docker sandbox run` with full security isolation
   - **BLOCKS** if run via plain `docker run` - requires docker sandbox
   - Alias: `csd` (Claude Sandbox Dotnet)
   - **Container naming**: `<repo-name>-<branch>` with all special chars sanitized to `-`
   - Falls back to directory name if not in git repo

2. **Auto-Attach Behavior**:
   - If container already running, `csd` auto-attaches
   - If running container has different options/volumes than current config, offer to restart
   - `csd-stop-all` prompts for which containers to stop (interactive selection)

3. **Single-Stage Build**:
   - Base: `docker/sandbox-templates:claude-code`
   - **Fail fast** if base is not Ubuntu Noble (deps are distro-specific)
   - Install .NET SDK via `dotnet-install.sh` (NOT apt repo)
   - Install PowerShell via Microsoft's recommended method
   - Install nvm + Node.js LTS + typescript, eslint, prettier
   - Install wasm-tools workload
   - Run `uno-check` with auto-fix flags during build
   - Verify with `dotnet --info` (fails if deps missing)

4. **SDK Version Strategy**:
   - Default: latest LTS (no version pinning required)
   - Build ARGs available for: preview, STS, specific major.minor
   - No version check script needed

5. **Container Startup Environment Detection**:
   - **Docker Sandbox detection**: BLOCKS startup if not in Docker Sandbox
   - **ECI status**: Warns every time if disabled (doesn't block)
   - Research needed: best method to detect sandbox vs plain docker
   - Research needed: best method to detect ECI status

6. **Zero-Friction Volume Initialization**:
   - Users just run `csd` - no manual init required
   - Volumes auto-created with correct permissions if needed
   - sync-* scripts handle volume creation when run before container start
   - Use user namespace remapping for UID mismatch (host 501 vs container 1000)

7. **Volume Strategy** (REQUIRES RESEARCH):
   - `docker-claude-data` managed by docker sandbox itself - DO NOT TOUCH
   - Plugins volume can be refactored if it makes sense overall
   - Research task needed to determine optimal volume split for:
     - VS Code server
     - GitHub Copilot auth
     - gh CLI config
     - NuGet package cache
     - Node modules cache (optional)

8. **Port Exposure**:
   - Expose ports 5000-5010 for WASM app serving
   - User tests in host browser via port forwarding

9. **Image Naming**:
   - Image name: `dotnet-sandbox`
   - Tags: `:latest` AND `:YYYY-MM-DD` (date-based for reproducibility)

### Sync Scripts

1. **sync-vscode.sh**:
   - Syncs VS Code settings and extension list
   - Extension list synced so VS Code auto-downloads on launch
   - Exits non-zero on failure (permission denied, doesn't exist)

2. **sync-vscode-insiders.sh**:
   - Same as above for VS Code Insiders
   - Exits non-zero on failure

3. **sync-all.sh**:
   - Detects what's available to sync
   - Calls appropriate sync scripts
   - Won't call sync-vscode-insiders if no Insiders data exists

4. **Existing sync-plugins.sh**:
   - Integrate with/build on existing script
   - One unified solution, not separate

### Integration with Existing Code

- Build on existing scripts in `claude/` directory
- One unified solution - edit/incorporate/refactor as needed
- Require jq (consistent with existing scripts)
- Let docker errors surface as-is (no wrapper help)
- Let docker sandbox handle path mounting (current dir as /workspace)

## Quick Commands

```bash
# Build the image
./dotnet-sandbox/build.sh

# Source aliases (adds csd)
source ./dotnet-sandbox/aliases.sh

# Start sandbox (auto-creates volumes, named after repo-branch)
csd

# If container running, auto-attaches
# If different options, offers to restart

# Smoke tests (CI/verification)
docker run --rm -u agent dotnet-sandbox:latest dotnet --list-sdks
docker run --rm -u agent dotnet-sandbox:latest dotnet workload list
docker run --rm -u agent dotnet-sandbox:latest node --version
docker run --rm -u agent dotnet-sandbox:latest pwsh --version

# Stop sandboxes (interactive prompt)
csd-stop-all

# Sync VS Code data (run before starting container)
./dotnet-sandbox/sync-vscode.sh
./dotnet-sandbox/sync-all.sh
```

## Acceptance Criteria

- [ ] `docker build` succeeds with Dockerfile
- [ ] Build fails with clear error if base image is not Ubuntu Noble
- [ ] `dotnet --version` (as agent) outputs latest LTS
- [ ] `dotnet workload list` (as agent) shows `wasm-tools`
- [ ] `uno-check` passes during build (with auto-fix)
- [ ] `pwsh --version` (as agent) succeeds
- [ ] `node --version` (as agent) outputs LTS version
- [ ] `nvm --version` works for version switching
- [ ] `tsc --version`, `eslint --version`, `prettier --version` work
- [ ] `command -v claude && claude --version` (as agent) succeeds
- [ ] Container runs as `uid=1000(agent)`
- [ ] Container BLOCKS startup if not via `docker sandbox run`
- [ ] Container WARNS about ECI status (every time)
- [ ] `csd` alias starts container with all volumes
- [ ] `csd` auto-attaches if container already running
- [ ] `csd` offers restart if container has different options
- [ ] Container name follows `<repo>-<branch>` pattern (sanitized)
- [ ] Falls back to directory name outside git repo
- [ ] `csd-stop-all` prompts for which containers to stop
- [ ] Ports 5000-5010 exposed
- [ ] Blazor WASM project creates and builds successfully
- [ ] Uno Platform WASM project creates and builds successfully
- [ ] NuGet cache pre-warmed with basic packages (wasm, aspnet, console)
- [ ] sync-vscode.sh syncs settings and extension list
- [ ] sync-vscode-insiders.sh syncs Insiders settings
- [ ] sync-all.sh detects available data and syncs appropriately
- [ ] gh CLI config synced to container
- [ ] README documents usage
- [ ] Image tagged as both :latest and :YYYY-MM-DD

## Security Considerations

**Docker sandbox handles all security automatically:**
- Capabilities dropping
- seccomp profiles
- ECI (Enhanced Container Isolation)
- User namespace isolation

**Container startup enforces:**
- MUST run via `docker sandbox run` (blocks otherwise)
- Warns if ECI disabled (but allows)

**We do NOT configure:**
- `--cap-drop`, `--cap-add`
- `--security-opt=seccomp=...`
- Manual security flags in runArgs

## Research Tasks Identified

1. **Volume Strategy**: Determine optimal volume split and naming
2. **Docker Sandbox Detection**: Best method to detect sandbox vs plain docker from inside container
3. **ECI Detection**: Best method to detect ECI status from inside container

## References

- Existing scripts: `claude/sync-plugins.sh`
- Docker sandbox commands: `docker sandbox run`, `docker sandbox ls`, `docker sandbox rm`
- dotnet-install.sh: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-install-script
- Uno Platform: https://platform.uno/
- nvm: https://github.com/nvm-sh/nvm
