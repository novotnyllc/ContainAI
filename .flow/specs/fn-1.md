# .NET Docker Sandbox

## Overview

A Docker image template for a development sandbox with .NET SDK (latest LTS), Node.js, and WASM workloads.

**Primary workflow**: `docker sandbox run` with full security isolation
**Alias**: `csd` (Claude Sandbox Dotnet)

**Build Strategy**: Single-stage Dockerfile based on `docker/sandbox-templates:claude-code` with .NET SDK installed via `dotnet-install.sh` script. Layered RUN commands for maintainability; optimize later if needed.

## Naming Standards (AUTHORITATIVE)

| Item | Name | Notes |
|------|------|-------|
| Directory | `dotnet-sandbox/` | Contains all files |
| Image name | `dotnet-sandbox` | |
| Image tags | `:latest`, `:YYYY-MM-DD` | Date for reproducibility |
| Shell alias | `csd` | Claude Sandbox Dotnet |
| Container naming | `<repo>-<branch>` | Sanitized, fallback to dirname |

### Container Naming Rules

- Sanitize: replace all non-alphanumeric chars with `-`
- Lowercase all characters
- Strip leading/trailing dashes
- Truncate to max 63 characters (Docker limit)
- Detached HEAD: use `detached-<short-sha>`
- **Empty after sanitization**: use `sandbox-<dirname>` as fallback
- **Git not installed**: Silently fall back to directory name (no error output)

## Scope

**In Scope:**
- New `dotnet-sandbox/` directory with Dockerfile
- .NET SDK (latest LTS, currently .NET 10 as of 2026-01-14) via dotnet-install.sh with `wasm-tools` workload
- PowerShell installed via Microsoft's recommended method
- Node.js with nvm + common dev tools (typescript, eslint, prettier)
- Sandbox enforcement via `csd` wrapper (NOT entrypoint blocking)
- Zero-friction startup: volumes auto-created with correct permissions
- Named volumes (see Volume Strategy below)
- Claude CLI credentials symlink (same workaround as existing claude/Dockerfile)
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
- NuGet cache pre-warming (ineffective with mounted volumes)

## Approach

### Architecture Decisions

1. **Docker Sandbox Enforcement**:
   - Uses `docker sandbox run` with full security isolation
   - **Enforcement happens in `csd` wrapper script** (NOT in image entrypoint)
   - Wrapper checks for sandbox requirements BEFORE starting container
   - Plain `docker run` allowed for smoke tests/CI (no entrypoint block)
   - Alias: `csd` (Claude Sandbox Dotnet)
   - **Container naming**: `<repo-name>-<branch>` with all special chars sanitized (see rules above)
   - Falls back to directory name if not in git repo

2. **Auto-Attach Behavior**:
   - If container already running with same name, `csd` auto-attaches
   - **Identity verification before attach**: verify container has label `csd.sandbox=dotnet-sandbox`
   - **Label support check**: Before first container creation, verify `docker sandbox run --help` shows `--label` support
     - If supported: use labels for identity verification
     - If NOT supported: fall back to image name verification (`docker inspect --format '{{.Config.Image}}'` starts with `dotnet-sandbox:`)
   - **Collision handling**: If name matches but identity check fails, error message must include:
     - Container name that collided
     - Expected identity (label `csd.sandbox=dotnet-sandbox` or image `dotnet-sandbox:*`)
     - Actual value observed (or "missing"/"not a csd container")
     - Remediation: `--restart` to replace, or remove existing container
   - **Attach mechanism**: `docker exec -it <container> bash` for running containers
   - Use `--restart` flag to force recreate container (stops existing, starts new)
   - `csd-stop-all` prompts for which containers to stop (interactive selection)
   - If container exists but is stopped: start it with `docker start -ai <container>`
   - **Note**: `csd` does not support `--name` override; container name is auto-generated from repo/branch

3. **Build Strategy**:
   - Base: `docker/sandbox-templates:claude-code`
   - **Fail fast** if base is not Ubuntu Noble (check `/etc/os-release` for `VERSION_CODENAME=noble`)
   - Install .NET SDK via `dotnet-install.sh` (NOT apt repo) as root
   - **Ownership policy**: .NET install dir (`/usr/share/dotnet`) stays root-owned; only volume mountpoints are chowned to uid 1000
   - Install PowerShell via Microsoft's recommended method
   - Install nvm + Node.js LTS + typescript, eslint, prettier **as agent user**
   - Install workloads (SEPARATE commands for fail-open behavior):
     ```dockerfile
     # Required workload - build fails if unavailable
     RUN dotnet workload install wasm-tools

     # Optional workload - warn and continue if unavailable
     RUN dotnet workload install wasm-tools-net9 || echo "WARNING: wasm-tools-net9 unavailable (optional)"
     ```
   - **Claude credentials symlink**: Create `/home/agent/.claude/.credentials.json` -> `/mnt/claude-data/.credentials.json`
   - **uno-check**: NOT installed during build (user installs if needed: `dotnet tool install -g uno.check`)
   - Verify with `dotnet --info` (fails if deps missing)
   - Use separate RUN commands for maintainability; optimize layers later

4. **SDK Version Strategy**:
   - Default: latest LTS via `DOTNET_CHANNEL=lts` (currently .NET 10 as of 2026-01-14)
   - Build ARGs: `DOTNET_CHANNEL=lts` (options: `lts`, `sts`, `preview`, or specific like "10.0")
   - **Acceptance test**: `dotnet --version | grep -E '^10\.'` serves as a "drift alarm"
   - **Intent**: If LTS advances to .NET 12 and tests break, that's a signal to update the test expectations (not a bug)
   - For pinned reproducibility, build with `--build-arg DOTNET_CHANNEL=10.0`

5. **Sandbox and ECI Detection**:
   - **Detection is BEST-EFFORT with explicit outcomes**
   - `csd` wrapper performs detection BEFORE container start
   - **Three detection outcomes**: `yes`, `no`, `unknown`
   - **Known error classes** (implementation detail - exact regexes may vary):
     - Feature disabled / not enabled
     - Command not recognized / unknown command
     - Daemon not running / connection refused
     - Permission denied
   - **Policy by outcome**:
     - `yes`: proceed normally
     - `no`: block with actionable summary including raw docker output
     - `unknown`: warn with raw docker output shown, then attempt to proceed
   - ECI detection: best-effort using `docker info`, treat as advisory (warn if unknown)

6. **Volume Strategy** (AUTHORITATIVE):

   **IMPORTANT**: Use `docker-claude-sandbox-data` (matches existing `claude/sync-plugins.sh`), NOT `docker-claude-data`.

   | Volume Name | Mount Point | Purpose | Created By |
   |-------------|-------------|---------|------------|
   | `docker-claude-sandbox-data` | `/mnt/claude-data` | Claude credentials | **Required** - must exist (can be empty) |
   | `docker-claude-plugins` | `/home/agent/.claude/plugins` | Claude plugins | Auto-created by csd if missing |
   | `dotnet-sandbox-vscode` | `/home/agent/.vscode-server` | VS Code server data | Auto-created by csd |
   | `dotnet-sandbox-nuget` | `/home/agent/.nuget` | NuGet package cache | Auto-created by csd |
   | `dotnet-sandbox-gh` | `/home/agent/.config/gh` | GitHub CLI config | Auto-created by csd |

   **Volume requirements**:
   - `docker-claude-sandbox-data`: **MUST exist** (can be empty or pre-populated)
     - **Option A (recommended)**: Pre-populated via existing host Claude credentials
     - **Option B**: Create empty volume, then `claude login` inside container:
       ```bash
       docker volume create docker-claude-sandbox-data
       # csd will chown the volume to uid 1000 so claude login can write
       ```
   - If missing, `csd` errors with actionable message showing both options
   - All other volumes: auto-created by `csd` if missing (zero-friction startup)
   - **Ownership**: All volume mountpoints (including `docker-claude-sandbox-data`) chowned to uid 1000

7. **Volume Initialization**:
   - `csd` wrapper ensures required volumes exist on first run
   - **Required volume** (`docker-claude-sandbox-data`): check existence, error if missing
   - **Auto-created volumes** (all others): create with `docker volume create`
   - **Permission fixing**: chown ALL volume mountpoints to uid 1000 using helper image
     - Includes `docker-claude-sandbox-data` (enables `claude login` in empty volume)
     - Uses `dotnet-sandbox:latest` as helper if available
     - **If image not built yet**: use base image `docker/sandbox-templates:claude-code` instead
   - No separate init script required - `csd` handles everything

8. **Port Exposure**:
   - Dockerfile: `EXPOSE 5000-5010`
   - **Check if `docker sandbox run` supports `-p`**: verify with `docker sandbox run --help | grep -q '\-p\|--publish'`
   - **If supported**: `csd` explicitly publishes `-p 5000-5010:5000-5010`
   - **If NOT supported**: warn user "Port publishing not supported by docker sandbox, use `docker run -p` for port access"
   - **Acceptance criteria for ports is CONDITIONAL**:
     - If sandbox supports publishing: verify host can reach container on port 5000
     - If sandbox doesn't support publishing: verify via `docker run -p` smoke test instead

9. **nvm and Node.js Installation** (Dockerfile steps):
   ```dockerfile
   # Install nvm and node AS AGENT USER
   USER agent
   RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
       && . ~/.nvm/nvm.sh \
       && nvm install --lts \
       && nvm alias default lts/* \
       && npm install -g typescript eslint prettier

   # Create system-wide symlinks for non-interactive access (as root)
   USER root
   RUN ln -sf /home/agent/.nvm/versions/node/$(ls /home/agent/.nvm/versions/node)/bin/node /usr/local/bin/node \
       && ln -sf /home/agent/.nvm/versions/node/$(ls /home/agent/.nvm/versions/node)/bin/npm /usr/local/bin/npm \
       && ln -sf /home/agent/.nvm/versions/node/$(ls /home/agent/.nvm/versions/node)/bin/npx /usr/local/bin/npx

   # Create /etc/profile.d/nvm.sh for login shells
   RUN echo 'export NVM_DIR="/home/agent/.nvm"' > /etc/profile.d/nvm.sh \
       && echo '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' >> /etc/profile.d/nvm.sh

   USER agent
   ```
   - **Note**: Symlinks point to specific version; if user runs `nvm use` to switch, symlinks become stale. Document this limitation.

### Sync Scripts

**All scripts MUST use `alpine` for Docker operations**

1. **sync-vscode.sh**:
   - Syncs VS Code settings and extension list to `dotnet-sandbox-vscode` volume
   - **Source paths** (OS-specific):
     - macOS: `~/Library/Application Support/Code/User/`
     - Linux: `~/.config/Code/User/`
     - Windows (WSL): `/mnt/c/Users/<user>/AppData/Roaming/Code/User/`
   - Files synced: `settings.json`, `keybindings.json`
   - Extensions: use `code --list-extensions` to generate list, sync to volume (list-only, NOT auto-installed)
   - **Exit conditions**:
     - Exit 0: VS Code not installed (with info message)
     - Exit 0: Success
     - Exit 1: Path exists but unreadable (permission denied)
     - Exit 1: Docker failure during sync
   - **Note**: Does NOT require jq

2. **sync-vscode-insiders.sh**:
   - Same as above for VS Code Insiders
   - **Source paths**:
     - macOS: `~/Library/Application Support/Code - Insiders/User/`
     - Linux: `~/.config/Code - Insiders/User/`
   - Same exit conditions as sync-vscode.sh

3. **sync-all.sh**:
   - Detects what VS Code installations are available
   - Calls appropriate sync scripts
   - Won't call sync-vscode-insiders if no Insiders data exists
   - Also syncs gh CLI config (MUST use `alpine`)
   - **Exit conditions**:
     - Exit 0: All available syncs completed (or none available)
     - Exit 1: Any sync script returned 1

4. **claude/sync-plugins.sh** (existing script):
   - Syncs Claude plugins and settings to volumes
   - **Does NOT sync credentials** - credentials are created by `claude login` inside container
   - MUST use  `alpine`
### Integration with Existing Code

- Build on existing scripts in `claude/` directory
- Reuse `docker-claude-sandbox-data` and `docker-claude-plugins` volumes (same as sync-plugins.sh)
- **Error handling**: Prepend actionable summary for known error cases; include raw docker output for context

## Quick Commands

```bash
# Build the image
./dotnet-sandbox/build.sh

# Source aliases (adds csd)
source ./dotnet-sandbox/aliases.sh

# Start sandbox (auto-creates volumes, named after repo-branch)
csd

# Force restart (instead of attach)
csd --restart

# Smoke tests (CI/verification) - plain docker run allowed for testing
docker run --rm -u agent dotnet-sandbox:latest dotnet --list-sdks
docker run --rm -u agent dotnet-sandbox:latest dotnet workload list
docker run --rm -u agent dotnet-sandbox:latest bash -lc "node --version"
docker run --rm -u agent dotnet-sandbox:latest pwsh --version

# Stop sandboxes (interactive prompt)
csd-stop-all

# Sync VS Code data (run before starting container)
./dotnet-sandbox/sync-vscode.sh
./dotnet-sandbox/sync-all.sh
```

## Acceptance Criteria

### Build
- [ ] `docker build` succeeds with Dockerfile
- [ ] Build fails with clear error if base image is not Ubuntu Noble
- [ ] `wasm-tools` workload installation succeeds (required, separate RUN command)
- [ ] `wasm-tools-net9` workload: attempt install in separate RUN, warn if fails, build continues (optional)

### Runtime Tools
- [ ] `dotnet --version` (as agent) outputs .NET 10.x (drift alarm if LTS changes)
- [ ] `dotnet workload list` (as agent) shows `wasm-tools`
- [ ] `pwsh --version` (as agent) succeeds
- [ ] `bash -lc "node --version"` (as agent) outputs LTS version
- [ ] `bash -lc "nvm --version"` works for version switching
- [ ] `bash -lc "tsc --version && eslint --version && prettier --version"` work
- [ ] `/usr/local/bin/node --version` works (symlink for non-interactive)
- [ ] `command -v claude && claude --version` (as agent) succeeds
- [ ] Container runs as `uid=1000(agent)`
- [ ] Claude credentials symlink exists: `/home/agent/.claude/.credentials.json`

### Sandbox Enforcement
- [ ] `csd` wrapper blocks if docker sandbox not available (with actionable message + raw output)
- [ ] `csd` warns and proceeds if detection returns "unknown" (shows raw output)
- [ ] Plain `docker run` works for smoke tests (no entrypoint blocking)

### Container Management
- [ ] `csd` alias starts container with all volumes and ports
- [ ] `csd` checks for label support in `docker sandbox run`
- [ ] `csd` auto-attaches via `docker exec` if container with correct identity running
- [ ] `csd` errors if name collision with foreign container (message includes: name, expected identity, actual value, `--restart` hint)
- [ ] `csd` starts stopped containers via `docker start`
- [ ] `csd --restart` recreates container even if running
- [ ] Container name follows `<repo>-<branch>` pattern (sanitized, lowercase, max 63 chars)
- [ ] Falls back to directory name outside git repo (silently, no git error output)
- [ ] Detached HEAD uses `detached-<short-sha>` pattern
- [ ] Empty name after sanitization uses `sandbox-<dirname>`
- [ ] `csd-stop-all` prompts for which containers to stop

### Networking (CONDITIONAL)
- [ ] Ports 5000-5010 exposed in Dockerfile
- [ ] `csd` detects if sandbox supports port publishing
- [ ] **If sandbox supports publishing**: ports 5000-5010 published to host
- [ ] **If sandbox doesn't support publishing**: verify via `docker run -p` instead

### WASM Verification (fn-1.5)
- [ ] Blazor WASM project creates and builds successfully
- [ ] Uno Platform WASM project creates and builds successfully
- [ ] `uno-check` passes when installed and run interactively (not pre-installed in image)

### Volumes and Sync
- [ ] `csd` checks for required volume (`docker-claude-sandbox-data`) - must exist (can be empty)
- [ ] `csd` errors with actionable message if required volume missing (shows both creation options)
- [ ] `csd` auto-creates other volumes (`docker-claude-plugins`, `dotnet-sandbox-*`)
- [ ] `csd` chowns ALL volume mountpoints (including credentials volume) to uid 1000
- [ ] Permission fixing uses `dotnet-sandbox:latest` if available, else base image
- [ ] sync-vscode.sh detects host OS and uses correct source paths
- [ ] sync-vscode.sh syncs settings and extension list (list-only, not auto-install)
- [ ] sync-vscode.sh exits 0 if VS Code not installed, exits 1 on actual errors
- [ ] sync-vscode-insiders.sh works for Insiders
- [ ] sync-all.sh detects available VS Code installations
- [ ] All sync scripts use `alpine`
- [ ] gh CLI config synced to container

### Documentation
- [ ] README documents usage
- [ ] README documents nvm symlink limitation
- [ ] README documents port publishing behavior (conditional on sandbox support)
- [ ] README clarifies sync-plugins.sh syncs plugins/settings, NOT credentials
- [ ] Image tagged as both :latest and :YYYY-MM-DD

## Security Considerations

**Docker sandbox handles all security automatically:**
- Capabilities dropping
- seccomp profiles
- ECI (Enhanced Container Isolation)
- User namespace isolation

**Enforcement is in `csd` wrapper (not image):**
- Wrapper checks for docker sandbox availability
- Warns about ECI status if detectable
- Blocks non-sandbox runs with clear actionable error message
- Verifies container identity before auto-attach (prevents attaching to foreign containers)

**We do NOT configure:**
- `--cap-drop`, `--cap-add`
- `--security-opt=seccomp=...`
- Manual security flags in runArgs
- Entrypoint-based blocking

## References

- Existing scripts: `claude/sync-plugins.sh` (syncs plugins/settings, NOT credentials)
- Existing Dockerfile: `claude/Dockerfile` (has credentials symlink workaround)
- Docker sandbox commands: `docker sandbox run`, `docker sandbox ls`, `docker sandbox rm`
- dotnet-install.sh: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-install-script
- Uno Platform: https://platform.uno/
- nvm: https://github.com/nvm-sh/nvm
