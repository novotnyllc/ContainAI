# fn-10-vep.26 Add version management and update mechanism

## Description
Add version management with single source of truth and update mechanism.

**Size:** M
**Files:**
- `VERSION` (source of truth)
- `src/containai.sh` (add version/update commands)
- `src/lib/version.sh` (new)

## Approach

1. VERSION file at repo root (e.g., "0.1.0")
2. `cai version` command shows current version
3. `cai update` command:
   - Pulls latest from git/GHCR
   - Shows changelog if available
   - Rebuilds image if needed

## Key context

- Single source of truth: VERSION file
- Build script should embed version in image
- Update should handle both git-based and GHCR-based installs
## Acceptance
- [ ] VERSION file at repo root
- [ ] `cai version` shows current version
- [ ] `cai update` pulls latest changes
- [ ] Version embedded in Docker image labels
- [ ] Update works for git-cloned installs
- [ ] Update works for GHCR-based installs
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
