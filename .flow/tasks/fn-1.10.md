# fn-1.10 Create README.md documentation

## Description
Create `dotnet-wasm/README.md` with comprehensive usage documentation.

### Documentation Sections

1. **Overview**: What this sandbox provides (.NET 10 + WASM + Claude)

2. **Prerequisites**: Docker Desktop 4.50+, Docker sandbox feature enabled

3. **Quick Start**:
   - Build the image: `./build.sh`
   - Initialize volumes: `./init-volumes.sh` (first time only)
   - Source aliases: `source ./aliases.sh`
   - Start sandbox: `claude-sandbox-dotnet`

4. **Volume Details**: What each of the 5 volumes stores and why
   - `docker-vscode-server` - VS Code Server extensions and data
   - `docker-github-copilot` - Copilot CLI authentication
   - `docker-dotnet-packages` - NuGet package cache
   - `docker-claude-plugins` - Claude Code plugins
   - `docker-claude-sandbox-data` - Claude credentials (REQUIRED for `claude` CLI)

5. **Security**:
   - **No manual security configuration required**
   - Docker sandbox automatically handles: capabilities, seccomp profiles, ECI, user namespace isolation
   - Do NOT add `--cap-drop`, `--security-opt`, or similar flags

6. **Sandbox/ECI Detection**:
   - Container startup detects Docker Sandbox vs plain Docker
   - Reports ECI (Enhanced Container Isolation) status
   - Recommends enabling ECI if not detected

7. **Sync Script**: How to use `sync-vscode-data.sh` (best-effort, recommend Settings Sync)

8. **Testing the Image**:
   - Interactive sandbox: `docker sandbox run ... dotnet-wasm`
   - CI/smoke tests: `docker run --rm -u agent dotnet-wasm:latest <command>`
   - Note: `docker run` is acceptable for non-interactive verification; use `docker sandbox run` for development

9. **Known Limitations**:
   - VS Code Insiders uses different cache path
   - Container-internal Docker socket not exposed by default

10. **Troubleshooting**: Common issues and solutions

### Reference

- Pattern: Existing `README.md` in parent project
- Include command examples from spec's "Quick Commands" section

## Acceptance
- [ ] `dotnet-wasm/README.md` exists
- [ ] Contains build instructions
- [ ] Documents all 5 volumes and their purposes
- [ ] States "No manual security configuration required - docker sandbox handles it"
- [ ] Does NOT mention runArgs, --cap-drop, --security-opt
- [ ] Documents sandbox/ECI detection feature
- [ ] Documents sync script as best-effort
- [ ] Lists known limitations
- [ ] Clarifies docker sandbox run (interactive) vs docker run (CI/smoke tests)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
