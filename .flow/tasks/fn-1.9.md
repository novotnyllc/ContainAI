# fn-1.9 Apply security hardening (capabilities, seccomp)

## Description
**NOT NEEDED** - Docker sandbox handles all security automatically.

### Why This Task is Obsolete

When using `docker sandbox run`, Docker handles:
- Capability dropping/adding
- seccomp profiles  
- ECI (Enhanced Container Isolation)
- User namespace isolation

We do NOT manually configure security flags.

### What Was Removed

Originally this task planned to add:
- `--cap-drop=ALL` / `--cap-add=...`
- `--security-opt=seccomp=unconfined`
- Manual runArgs in devcontainer.json

All of this is now handled by `docker sandbox run` automatically.

### Action

Mark this task as **SKIPPED** or close immediately - no implementation needed.
## Acceptance
- [x] Task marked as not needed (docker sandbox handles security)
- [ ] Verify no manual security flags in devcontainer.json
- [ ] Verify no manual security flags in helper scripts
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
