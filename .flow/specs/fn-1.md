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
- Names starting with `-` after sanitization: prefix with `sandbox-`

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
   - **Comparison key**: container name only (not options/volumes)
   - **Attach mechanism**: `docker exec -it <container> bash` for running containers
   - Use `--restart` flag to force recreate container (stops existing, starts new)
   - `csd-stop-all` prompts for which containers to stop (interactive selection)
   - If container exists but is stopped: start it with `docker start -ai <container>`

3. **Build Strategy**:
   - Base: `docker/sandbox-templates:claude-code`
   - **Fail fast** if base is not Ubuntu Noble (check `/etc/os-release` for `VERSION_CODENAME=noble`)
   - Install .NET SDK via `dotnet-install.sh` (NOT apt repo) **as root, then fix ownership**
   - Install PowerShell via Microsoft's recommended method
   - Install nvm + Node.js LTS + typescript, eslint, prettier **as agent user**
   - Install wasm-tools workload
   - **Claude credentials symlink**: Create `/home/agent/.claude/.credentials.json` -> `/mnt/claude-data/.credentials.json`
   - **uno-check NOT run during build** (moved to verification task fn-1.5)
   - Verify with `dotnet --info` (fails if deps missing)
   - Use separate RUN commands for maintainability; optimize layers later

4. **SDK Version Strategy**:
   - Default: latest LTS (currently .NET 10 as of 2026-01-14)
   - Build ARGs: `DOTNET_CHANNEL=lts` (options: lts, sts, preview, or specific like "10.0")
   - **Acceptance test**: `dotnet --version | grep -E '^10\.'` (verify major version is 10, not preview)

5. **Sandbox and ECI Detection**:
   - **Detection is BEST-EFFORT, not guaranteed**
   - `csd` wrapper performs detection BEFORE container start
   - Detection logic:
     ```bash
     # Sandbox availability check
     if docker sandbox ls >/dev/null 2>&1; then
       SANDBOX="yes"
     elif ! command -v docker >/dev/null 2>&1; then
       SANDBOX="no"  # No docker at all
     elif docker sandbox --help 2>&1 | grep -q "not recognized\|unknown command"; then
       SANDBOX="no"  # Docker exists but sandbox not supported
     else
       SANDBOX="no"  # Sandbox command failed for other reason
     fi
     ```
   - **Policy**: Block if `sandbox=no` with clear actionable message (minimum Docker Desktop version, feature enablement steps)
   - ECI detection: best-effort using `docker info`, treat as advisory (warn if unknown)

6. **Volume Strategy** (AUTHORITATIVE):

   **IMPORTANT**: Use `docker-claude-sandbox-data` (matches existing `claude/sync-plugins.sh`), NOT `docker-claude-data`.

   | Volume Name | Mount Point | Purpose | Created By |
   |-------------|-------------|---------|------------|
   | `docker-claude-sandbox-data` | `/mnt/claude-data` | Claude credentials | Docker sandbox / sync-plugins.sh |
   | `docker-claude-plugins` | `/home/agent/.claude/plugins` | Claude plugins | sync-plugins.sh |
   | `dotnet-sandbox-vscode` | `/home/agent/.vscode-server` | VS Code server data | csd/init |
   | `dotnet-sandbox-nuget` | `/home/agent/.nuget` | NuGet package cache | csd/init |
   | `dotnet-sandbox-gh` | `/home/agent/.config/gh` | GitHub CLI config | sync-all.sh |

   - Reuse existing volumes from `claude/sync-plugins.sh` where possible
   - `csd` ensures volumes exist before starting container
   - Ownership: volumes created with uid 1000 (agent user)

7. **Volume Initialization**:
   - `csd` wrapper ensures all required volumes exist on first run
   - Uses `docker volume create` for missing volumes
   - Permission fixing: use `dotnet-sandbox:latest` as helper (avoids alpine dependency)
     ```bash
     docker run --rm -u root -v vol:/data dotnet-sandbox:latest chown 1000:1000 /data
     ```
   - No separate init script required - `csd` handles everything
   - Fallback: if dotnet-sandbox not built yet, skip permission fixing (user builds first)

8. **Port Exposure**:
   - Dockerfile: `EXPOSE 5000-5010`
   - **Verify `docker sandbox run` supports `-p`**: check `docker sandbox run --help` before relying on it
   - `csd` wrapper: explicitly publishes `-p 5000-5010:5000-5010` if supported
   - User tests in host browser via http://localhost:5000
   - **Acceptance**: verify host can reach container on port 5000

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

1. **sync-vscode.sh**:
   - Syncs VS Code settings and extension list to `dotnet-sandbox-vscode` volume
   - **Source paths** (OS-specific):
     - macOS: `~/Library/Application Support/Code/User/`
     - Linux: `~/.config/Code/User/`
     - Windows (WSL): `/mnt/c/Users/<user>/AppData/Roaming/Code/User/`
   - Files synced: `settings.json`, `keybindings.json`
   - Extensions: use `code --list-extensions` to generate list, sync to volume
   - Exits non-zero on failure (permission denied, doesn't exist)
   - **"Not found" vs error**: exit 0 with message if VS Code not installed; exit 1 on actual errors

2. **sync-vscode-insiders.sh**:
   - Same as above for VS Code Insiders
   - **Source paths**:
     - macOS: `~/Library/Application Support/Code - Insiders/User/`
     - Linux: `~/.config/Code - Insiders/User/`
   - Exits non-zero on failure

3. **sync-all.sh**:
   - Detects what VS Code installations are available
   - Calls appropriate sync scripts
   - Won't call sync-vscode-insiders if no Insiders data exists
   - Also syncs gh CLI config

4. **Existing sync-plugins.sh**:
   - Integrate with/build on existing script
   - One unified solution, not separate

### Integration with Existing Code

- Build on existing scripts in `claude/` directory
- Reuse `docker-claude-sandbox-data` and `docker-claude-plugins` volumes (same as sync-plugins.sh)
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

### Runtime Tools
- [ ] `dotnet --version` (as agent) outputs LTS version (10.x as of 2026-01)
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
- [ ] `csd` wrapper blocks if docker sandbox not available (with clear actionable message)
- [ ] `csd` warns if ECI detection returns unknown (but proceeds)
- [ ] Plain `docker run` works for smoke tests (no entrypoint blocking)

### Container Management
- [ ] `csd` alias starts container with all volumes and ports
- [ ] `csd` auto-attaches via `docker exec` if container with same name running
- [ ] `csd` starts stopped containers via `docker start`
- [ ] `csd --restart` recreates container even if running
- [ ] Container name follows `<repo>-<branch>` pattern (sanitized, lowercase, max 63 chars)
- [ ] Falls back to directory name outside git repo
- [ ] Detached HEAD uses `detached-<short-sha>` pattern
- [ ] `csd-stop-all` prompts for which containers to stop

### Networking
- [ ] Ports 5000-5010 exposed in Dockerfile
- [ ] `csd` publishes ports 5000-5010 to host (if `docker sandbox run` supports it)
- [ ] WASM app accessible at http://localhost:5000 from host

### WASM Verification (fn-1.5)
- [ ] Blazor WASM project creates and builds successfully
- [ ] Uno Platform WASM project creates and builds successfully
- [ ] `uno-check` passes when run interactively

### Volumes and Sync
- [ ] `csd` creates missing volumes automatically
- [ ] Volumes have correct ownership (uid 1000)
- [ ] Volume permission fixing uses `dotnet-sandbox:latest` as helper (not alpine)
- [ ] sync-vscode.sh detects host OS and uses correct source paths
- [ ] sync-vscode.sh syncs settings and extension list
- [ ] sync-vscode-insiders.sh works for Insiders
- [ ] sync-all.sh detects available VS Code installations
- [ ] gh CLI config synced to container

### Documentation
- [ ] README documents usage
- [ ] README documents nvm symlink limitation
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

**We do NOT configure:**
- `--cap-drop`, `--cap-add`
- `--security-opt=seccomp=...`
- Manual security flags in runArgs
- Entrypoint-based blocking

## References

- Existing scripts: `claude/sync-plugins.sh` (uses `docker-claude-sandbox-data` volume)
- Existing Dockerfile: `claude/Dockerfile` (has credentials symlink workaround)
- Docker sandbox commands: `docker sandbox run`, `docker sandbox ls`, `docker sandbox rm`
- dotnet-install.sh: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-install-script
- Uno Platform: https://platform.uno/
- nvm: https://github.com/nvm-sh/nvm
