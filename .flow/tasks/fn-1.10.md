# fn-1.10 Create README.md documentation

## Description
Create `dotnet-sandbox/README.md` with comprehensive usage documentation.

### Documentation Sections

1. **Overview**: What this sandbox provides (.NET 10 + WASM + Claude)

2. **Prerequisites**: Docker Desktop 4.50+, Docker sandbox feature enabled

3. **Quick Start**:
   - Build the image: `./build.sh`
   - Source aliases: `source ./aliases.sh`
   - Start sandbox: `csd`
   - Note: volumes created automatically on first run

4. **Volume Details** (per spec Volume Strategy):
   - `docker-claude-sandbox-data` - Claude credentials (managed by docker sandbox / sync-plugins.sh - DO NOT TOUCH)
   - `docker-claude-plugins` - Claude Code plugins
   - `dotnet-sandbox-vscode` - VS Code Server extensions and data
   - `dotnet-sandbox-nuget` - NuGet package cache
   - `dotnet-sandbox-gh` - GitHub CLI config

5. **Security**:
   - **No manual security configuration required**
   - Docker sandbox automatically handles: capabilities, seccomp profiles, ECI, user namespace isolation
   - Do NOT add `--cap-drop`, `--security-opt`, or similar flags
   - Enforcement happens in `csd` wrapper (not image entrypoint)

6. **Sandbox Detection**:
   - `csd` wrapper detects Docker Sandbox availability before starting
   - Blocks with actionable error if sandbox unavailable (version requirements, how to enable)
   - Warns if ECI status unknown (proceeds anyway)
   - Plain `docker run` allowed for smoke tests/CI

7. **Sync Scripts**:
   - sync-vscode.sh - syncs VS Code settings and extensions
   - sync-vscode-insiders.sh - same for Insiders
   - sync-all.sh - detects available VS Code installations and syncs
   - OS-specific paths handled automatically

8. **Testing the Image**:
   - Interactive sandbox: `csd`
   - Force restart: `csd --restart`
   - CI/smoke tests: `docker run --rm -u agent dotnet-sandbox:latest <command>`
   - Node.js tests: `docker run ... bash -lc "node --version"` (needs login shell for nvm)

9. **Port Forwarding**:
   - `csd` publishes ports 5000-5010 to host
   - Access WASM apps at http://localhost:5000

10. **Container Naming**:
    - Defaults to `<repo>-<branch>` (sanitized, lowercase, max 63 chars)
    - Falls back to directory name outside git repo
    - Detached HEAD uses `detached-<short-sha>` pattern

11. **nvm Symlink Limitation**:
    - `/usr/local/bin/node` symlinks point to specific node version installed at build time
    - If you run `nvm use` to switch versions, symlinks become stale
    - Use `bash -lc "node ..."` for correct nvm-aware access

12. **Known Limitations**:
    - VS Code Insiders uses different cache path
    - ECI detection is best-effort
    - nvm symlinks don't update when version changes

13. **Troubleshooting**: Common issues and solutions

### Reference

- Pattern: Existing `README.md` in parent project
- Include command examples from spec's "Quick Commands" section

## Acceptance
- [ ] `dotnet-sandbox/README.md` exists
- [ ] Contains build instructions
- [ ] Documents all volumes and their purposes
- [ ] States "No manual security configuration required - docker sandbox handles it"
- [ ] Does NOT mention runArgs, --cap-drop, --security-opt
- [ ] Documents sandbox detection in `csd` wrapper
- [ ] Documents sync scripts and OS-specific paths
- [ ] Lists known limitations including nvm symlink limitation
- [ ] Clarifies `csd` (interactive) vs `docker run` (CI/smoke tests)
- [ ] Documents port forwarding (5000-5010)
- [ ] Documents container naming convention including detached HEAD

## Done summary
- Added comprehensive README.md documentation for dotnet-sandbox
- Covers all required sections: prerequisites, quick start, csd command, volumes, security, sync scripts, testing, limitations, troubleshooting
- Documents that docker sandbox handles all security automatically (no --cap-drop, --security-opt)
- Includes nvm symlink limitation documentation

Why:
- Per task spec fn-1.10 acceptance criteria
- Users need documentation to use the sandbox effectively

Verification:
- README.md exists with all required sections
- Security section states "No manual security configuration required"
- Does not mention runArgs, --cap-drop, --security-opt
## Evidence
- Commits: af7f6b3f239ca6f43dbcf908fe039babc036f075
- Tests: manual README review
- PRs:
