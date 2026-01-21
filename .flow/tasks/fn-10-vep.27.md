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
# Summary

Comprehensively rewrote src/README.md with the following changes:

1. **Added Table of Contents** - Improved navigation for the long document

2. **Updated Overview section** - More structured with "Container Contents" and "Key Files" subsections

3. **Updated Prerequisites** - Added Bash 4.0+ requirement, clearer about Docker Desktop vs Sysbox options

4. **Simplified DinD section** - Complete rewrite:
   - Removed all `--privileged` flags from examples
   - Clear runtime model diagram showing we run IN Sysbox, not install it
   - Explained how DinD auto-detection works via uid_map
   - Added environment variable override documentation (CAI_ENABLE_DIND)
   - Added verification commands

5. **Simplified Dockerfile.test section** - Removed sysbox installation references:
   - Changed examples from `--privileged` to `--runtime=sysbox-runc`
   - Clarified the container is designed to RUN in Sysbox, not install it
   - Simplified startup script description (removed sysbox-mgr/sysbox-fs references)
   - Simplified test helper description

6. **Added Troubleshooting sections** for:
   - Docker commands failing inside container
   - Inner containers network issues

7. **Removed outdated information**:
   - Removed "Used by sync scripts" volume section (not currently mounted)
   - Removed "Sync Scripts" section (outdated paths)
   - Streamlined credential syncing documentation

## Evidence
- Commits:
- Tests:
- PRs:
