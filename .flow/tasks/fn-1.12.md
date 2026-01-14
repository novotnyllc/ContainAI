# fn-1.12 Research and define volume strategy

## Description
Research and define the optimal volume strategy for the dotnet-sandbox.

**Constraints:**
- `docker-claude-data` is managed by docker sandbox itself - DO NOT TOUCH
- Plugins volume can be refactored if it makes sense overall
- User namespace remapping for UID mismatch (host 501 vs container 1000)

**Areas to Research:**
1. VS Code server data persistence
2. GitHub Copilot auth persistence
3. gh CLI config persistence
4. NuGet package cache persistence
5. Node modules cache (optional)
6. How docker sandbox handles docker-claude-data ownership
7. Best approach for zero-friction volume initialization

**Deliverable:**
- Document the volume strategy in the epic spec
- Define volume names and mount points
- Document how ownership is handled
## Acceptance
- [ ] Volume strategy documented in epic spec
- [ ] Each volume has clear name and mount point
- [ ] Ownership strategy defined
- [ ] Integration with existing sync-plugins.sh considered
- [ ] Zero-friction startup approach documented
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
