# fn-1.4 Create helper scripts (build and run)

## Description
Create helper scripts for building and running the sandbox:

**build.sh:**
- Build and tag image as `dotnet-sandbox:latest`
- Also tag with date: `dotnet-sandbox:YYYY-MM-DD`

**aliases.sh:**
- `csd` function (Claude Sandbox Dotnet):
  - **Sandbox detection BEFORE starting container** (see fn-1.11)
  - Auto-creates volumes with correct permissions if needed (uid 1000)
  - **Auto-attach mechanism**: `docker exec -it <container> bash` for running containers
  - **Stopped containers**: `docker start -ai <container>`
  - **Comparison key**: container name only (not options/volumes)
  - Use `--restart` flag to force recreate container (stops existing, starts new)
  - **Container naming rules**:
    - Pattern: `<repo-name>-<branch>`
    - Sanitize: replace non-alphanumeric with `-`
    - Lowercase all characters
    - Strip leading/trailing dashes
    - Truncate to max 63 characters
    - Detached HEAD: `detached-<short-sha>`
  - Falls back to directory name outside git repo
  - All volumes mounted (per spec Volume Strategy)
  - **Port publishing**: `-p 5000-5010:5000-5010` (verify sandbox supports `-p` first)
- `csd-stop-all` function:
  - Prompts for which containers to stop (interactive selection)

**Volume Creation (per spec - matches sync-plugins.sh):**
```bash
# Volumes csd creates/ensures:
# - dotnet-sandbox-vscode  -> /home/agent/.vscode-server
# - dotnet-sandbox-nuget   -> /home/agent/.nuget
# - dotnet-sandbox-gh      -> /home/agent/.config/gh
# - docker-claude-plugins  -> /home/agent/.claude/plugins (reused)
# Note: docker-claude-sandbox-data managed by sync-plugins.sh / sandbox
```

**Permission Fixing (use dotnet-sandbox, not alpine):**
```bash
docker run --rm -u root -v vol:/data dotnet-sandbox:latest chown 1000:1000 /data
```
- Fallback: skip permission fixing if dotnet-sandbox not built yet

**Integration:**
- Build on existing scripts in `claude/` directory
- Require jq (consistent with existing scripts)
- Let docker errors surface as-is
- Let docker sandbox handle path mounting
## Acceptance
- [x] build.sh creates dotnet-sandbox:latest
- [x] build.sh creates dotnet-sandbox:YYYY-MM-DD tag
- [x] `csd` checks for sandbox availability before starting (blocks if unavailable)
- [x] `csd` starts sandbox with all volumes and ports
- [x] `csd` auto-attaches via `docker exec -it` if container running
- [x] `csd` starts stopped containers via `docker start -ai`
- [x] `csd --restart` recreates container even if running
- [x] Container name follows `<repo>-<branch>` pattern (sanitized, lowercase, max 63)
- [x] Detached HEAD uses `detached-<short-sha>` pattern
- [x] Falls back to directory name outside git repo
- [x] `csd-stop-all` prompts interactively
- [x] Ports 5000-5010 published to host
- [x] Volume permission fixing uses dotnet-sandbox, not alpine
## Done summary
Implemented helper scripts for building and running the dotnet-sandbox:

**build.sh:**
- Builds dotnet-sandbox image from current directory
- Tags as both `:latest` and `:YYYY-MM-DD` (current date)
- Passes through any docker build arguments (e.g., `--no-cache`)
- Displays resulting image info after build

**aliases.sh:**
- `csd` function (Claude Sandbox Dotnet) with:
  - Sandbox availability check before starting (blocks with actionable error if unavailable)
  - Auto-volume creation with uid 1000 permission fixing using dotnet-sandbox image
  - Auto-attach to running containers via `docker exec -it`
  - Restart stopped containers via `docker start -ai`
  - `--restart` flag to force recreate existing containers
  - Container naming: `<repo>-<branch>` sanitized (lowercase, non-alphanum -> dash, max 63 chars)
  - Detached HEAD support with `detached-<short-sha>` pattern
  - Directory name fallback when not in git repo
  - Port publishing `-p 5000-5010:5000-5010`
  - All required volumes mounted per spec
- `csd-stop-all` function with interactive container selection

Both scripts pass bash syntax validation.
## Evidence
- Commits: 9c4ed4e
- Tests: bash -n syntax validation
- PRs:
