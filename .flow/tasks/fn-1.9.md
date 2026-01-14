# fn-1.9 Apply security hardening (capabilities, seccomp)

## Description
**SKIPPED** - Docker sandbox handles all security automatically.

### Why This Task is Not Needed

When using `docker sandbox run`, Docker handles:
- Capability dropping/adding
- seccomp profiles
- ECI (Enhanced Container Isolation)
- User namespace isolation

We do NOT manually configure security flags.

### What Was Not Implemented (by design)

This task originally planned to add:
- `--cap-drop=ALL` / `--cap-add=...`
- `--security-opt=seccomp=unconfined`
- Manual runArgs in devcontainer.json

All of this is handled by `docker sandbox run` automatically.

### Verification

- No devcontainer.json in this project (not using dev containers)
- Helper scripts use `csd` wrapper which uses `docker sandbox run`
- No manual security flags added anywhere

## Acceptance
- [x] Task marked as not needed (docker sandbox handles security)
- [x] No devcontainer.json exists (N/A - not using dev containers)
- [x] Helper scripts use docker sandbox (enforced by csd wrapper)
## Done summary
SKIPPED - Docker sandbox handles all security automatically. No manual security configuration needed.

## Evidence
- Commits: N/A (no implementation needed)
- Tests: N/A
- PRs: N/A
