# fn-10-vep.27 Rewrite agent-sandbox/README.md comprehensively

## Description
Comprehensively rewrite src/README.md (formerly agent-sandbox/README.md) with updated structure and simplified DinD documentation.

**Size:** M
**Files:**
- `src/README.md`

## Approach

1. Update all paths for new repo structure
2. Simplify DinD section (no --privileged, no "ECI-only mode")
3. Clear explanation of sysbox runtime model
4. Update quick start commands
5. Fix any outdated information

## Key updates needed

- Remove --privileged from all examples
- Remove sysbox installation from Dockerfile.test docs
- Update file paths (agent-sandbox/ → src/)
- Clarify that we run IN sysbox, not that we install sysbox
## Acceptance
- [ ] All paths updated for new structure
- [ ] DinD section simplified
- [ ] No --privileged in examples
- [ ] Runtime model clearly explained
- [ ] Quick start commands work
- [ ] No outdated information
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
