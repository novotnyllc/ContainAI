# Container Lifecycle & Cleanup

## STATUS: SUPERSEDED

This epic has been **merged into fn-34-fk5** (One-Shot Execution & Container Lifecycle).

Moved to fn-34-fk5:
- `cai gc` command
- `--reset` flag
- Session detection integration
- Run/shell semantics

Remaining work (consider for separate epic):
- Uninstall improvements (--docker-bundle flag)
- Workspace symlink fix
- Sandboxing comparison documentation

---

## Overview

Comprehensive improvements to container lifecycle management, cleanup, and documentation. Adds garbage collection for stale resources, improves uninstall completeness, fixes workspace symlink creation, clarifies multi-agent `cai run` semantics, and documents how ContainAI compares to other AI agent sandboxing approaches.

**Deferred to future epic:**
- Auto-shutdown mode (blocked by fn-13-1c7 devcontainer research)
- Config file reading from inside container (depends on fn-12-css workspace-centric config)

## Scope

| Feature | Description | Files |
|---------|-------------|-------|
| `cai gc` command | Prune stale containers/images with configurable retention | `src/lib/gc.sh`, `src/containai.sh` |
| Uninstall improvements | Add `--docker-bundle` flag to remove managed Docker binaries | `src/lib/uninstall.sh` |
| Workspace symlink fix | Fix `CAI_HOST_WORKSPACE` passing so symlink gets created | `src/lib/container.sh`, `src/container/containai-init.sh` |
| Run/shell semantics | Clarify multi-agent behavior, add `--reset` flag | `src/containai.sh`, `src/lib/container.sh` |
| Sandboxing comparison doc | Compare ContainAI to other agent sandbox approaches | `docs/agent-sandboxing-comparison.md` |

## Approach

### Container GC (`cai gc`)

New command to prune stale ContainAI resources:

```bash
cai gc                    # Interactive: show candidates, confirm
cai gc --dry-run          # List what would be removed
cai gc --force            # Skip confirmation
cai gc --age 7d           # Only prune containers older than 7 days
cai gc --images           # Also prune unused images
```

**Protection mechanism:** Resources with label `containai.keep=true` are never pruned. Running containers are never pruned.

**Scope:** Only prunes ContainAI-managed resources (label `containai.managed=true`), not user's other Docker resources.

### Uninstall Improvements

Add `--docker-bundle` flag to `cai uninstall`:

```bash
cai uninstall --docker-bundle  # Remove /opt/containai/docker/
```

Must stop containai-docker.service first. Warn if other tools depend on it.

### Workspace Symlink Fix

Diagnose why symlink from host path to `/agent/home/workspace` isn't being created. Likely causes:
- `CAI_HOST_WORKSPACE` env var not passed to container
- Path validation rejecting legitimate paths
- Permission issues with `ln -sfn`

### Run/Shell Semantics

Clarify behavior:
- `cai run` = Ensure container exists and running, optionally start agent
- `cai shell` = Open interactive SSH shell to existing container

For multi-agent: One container per workspace. `--agent` flag changes which agent runs, doesn't create separate container.

Add `--reset` flag to wipe data volume (distinct from `--fresh` which only recreates container):

```bash
cai run --fresh        # Recreate container, keep data volume (existing behavior)
cai run --reset        # Recreate container AND wipe data volume (new)
```

### Documentation

New `docs/agent-sandboxing-comparison.md` comparing:
- ContainAI (this project)
- OpenAI Codex CLI (Landlock/Seatbelt/Windows sandbox)
- Google Gemini CLI (Seatbelt profiles, Docker)
- E2B (Firecracker microVMs)
- Claude Code built-in sandbox (srt)
- Daytona
- Third-party Claude containers (textcortex, tintinweb)

## Quick commands

```bash
# Test gc command (after implementation)
source src/containai.sh && cai gc --dry-run

# Test uninstall (in isolated environment)
cai uninstall --docker-bundle --dry-run

# Verify symlink creation
docker exec containai-<hash> ls -la /home/claire/dev/ContainAI

# Lint all changes
shellcheck -x src/lib/gc.sh src/lib/uninstall.sh src/lib/container.sh
```

## Acceptance

- [ ] `cai gc` command prunes stale containers with configurable age
- [ ] `cai gc --dry-run` shows candidates without removing
- [ ] Running containers and `containai.keep=true` resources protected from GC
- [ ] `cai uninstall --docker-bundle` removes `/opt/containai/docker/`
- [ ] Workspace symlink `/home/*/dev/* -> /agent/home/workspace` created correctly
- [ ] `cai run --reset` wipes data volume (with confirmation)
- [ ] `docs/agent-sandboxing-comparison.md` covers 6+ sandboxing approaches
- [ ] All shell scripts pass `shellcheck -x`

## Dependencies

- **fn-15-281** (ContainAI-managed dockerd bundle): Uninstall improvements depend on bundle structure at `/opt/containai/docker/<version>/`
- **fn-10-vep** (Sysbox): GC must handle Sysbox system containers correctly

## References

- Docker prune filters: https://docs.docker.com/reference/cli/docker/system/prune/
- Landlock (Codex): https://github.com/openai/codex/tree/main/codex-rs/linux-sandbox
- Gemini CLI sandbox: https://github.com/google-gemini/gemini-cli/tree/main/packages/cli/src/utils
- E2B Firecracker: https://github.com/e2b-dev/infra
- Existing uninstall: `src/lib/uninstall.sh:441-578`
- Existing symlink: `src/container/containai-init.sh:278-318`
