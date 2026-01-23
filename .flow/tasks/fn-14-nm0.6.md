# fn-14-nm0.6 Update documentation for new paths

## Description
Update all documentation to reflect the new isolated Docker paths and remove references to system Docker modification.

**Size:** M
**Files:** `docs/setup-guide.md`, `docs/architecture.md`, `docs/troubleshooting.md`, `CHANGELOG.md`

## Current State

Documentation has inconsistent socket naming and references to system Docker paths:
- `setup-guide.md`: References `/var/run/docker-containai.sock` (8+ places)
- `architecture.md`: References `/var/run/containai-docker.sock` (inconsistent)
- `troubleshooting.md`: Mixed socket references

## Approach

1. Standardize all socket references to `/var/run/containai-docker.sock`
2. Update "Component Locations" tables in setup-guide.md
3. Update architecture diagram showing isolated Docker
4. Update troubleshooting for isolated Docker checks
5. Add CHANGELOG entry for the isolation fix

**Files to update:**
- `docs/setup-guide.md:174-209, 252-263, 454-570` - Component locations and troubleshooting
- `docs/architecture.md:117, 143-164` - Diagrams and config examples
- `docs/troubleshooting.md:320-350, 719` - Socket permission sections
- `CHANGELOG.md` - Add "Fixed" entry

## Key Context

- Use Keep-a-changelog format for CHANGELOG
- All paths should use inline code backticks
- Tables follow existing format in setup-guide.md
## Acceptance
- [ ] All docs reference `/var/run/containai-docker.sock` (unified naming)
- [ ] No docs reference `/etc/docker/daemon.json` as being modified
- [ ] Component Locations tables updated for WSL2 and Native Linux
- [ ] Architecture diagram shows isolated Docker flow
- [ ] CHANGELOG.md has entry under "Fixed" section
- [ ] `grep -r "etc/docker/daemon.json" docs/` shows only "not modified" context
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
