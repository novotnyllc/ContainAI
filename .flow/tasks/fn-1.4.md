# fn-1.4 Create helper scripts (build and run)

## Description
Create helper scripts for building and running the sandbox:

**build.sh:**
- Build and tag image as `dotnet-sandbox:latest`
- Also tag with date: `dotnet-sandbox:YYYY-MM-DD`

**aliases.sh:**
- `csd` alias (Claude Sandbox Dotnet):
  - Auto-creates volumes with correct permissions if needed
  - Auto-attaches if container already running
  - Offers restart if container has different options
  - Container naming: `<repo>-<branch>` (all special chars sanitized to `-`)
  - Falls back to directory name outside git repo
  - All volumes mounted
- `csd-stop-all` alias:
  - Prompts for which containers to stop (interactive selection)

**Integration:**
- Build on existing scripts in `claude/` directory
- Require jq (consistent with existing scripts)
- Let docker errors surface as-is
- Let docker sandbox handle path mounting
## Acceptance
- [ ] build.sh creates dotnet-sandbox:latest
- [ ] build.sh creates dotnet-sandbox:YYYY-MM-DD tag
- [ ] `csd` starts sandbox with all volumes
- [ ] `csd` auto-attaches if container running
- [ ] `csd` offers restart if different options
- [ ] Container name follows `<repo>-<branch>` pattern
- [ ] Branch names have special chars sanitized
- [ ] Falls back to directory name outside git repo
- [ ] `csd-stop-all` prompts interactively
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
