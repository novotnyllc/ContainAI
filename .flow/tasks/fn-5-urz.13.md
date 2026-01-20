# fn-5-urz.13 containai sandbox reset command

## Description
## Overview

Implement `containai sandbox reset` to remove the current workspace sandbox so configuration changes can take effect.

## Background

Docker Sandboxes are "one per workspace" and configuration changes (env vars, mounts, socket access, credentials mode) require removing and recreating the sandbox.

## Command

```bash
containai sandbox reset [--workspace <path>]
```

## What It Does

1. Identify sandbox for current/specified workspace
2. Stop the sandbox if running
3. Remove the sandbox (`docker sandbox rm`)
4. Confirm removal

## Implementation

```bash
containai_sandbox_reset() {
    local workspace="${1:-.}"
    workspace=$(realpath "$workspace")
    
    # Find sandbox by workspace
    local sandbox_id
    sandbox_id=$(docker sandbox ls --format '{{.ID}} {{.Workspace}}' | \
        grep " ${workspace}$" | awk '{print $1}')
    
    if [[ -z "$sandbox_id" ]]; then
        _cai_info "No sandbox found for workspace: $workspace"
        return 0
    fi
    
    _cai_info "Removing sandbox $sandbox_id for workspace: $workspace"
    docker sandbox rm "$sandbox_id"
    _cai_info "[OK] Sandbox removed. New config will apply on next run."
}
```

## Edge Cases

- Sandbox is currently running: stop first, then remove
- Multiple sandboxes for same workspace (shouldn't happen, but handle gracefully)
- Workspace path doesn't match exactly (symlinks, relative paths)

## References

- Docker docs: "config changes require removing/recreating the sandbox"
- https://docs.docker.com/ai/sandboxes/advanced-config/
## Acceptance
- [ ] Finds sandbox by workspace path
- [ ] Handles running sandbox (stops first)
- [ ] Handles no sandbox found (no error, info message)
- [ ] Works with relative and absolute paths
- [ ] Resolves symlinks for workspace matching
- [ ] Confirms successful removal
- [ ] Does not affect sandboxes for other workspaces
## Done summary
Implemented `containai sandbox reset` command to remove Docker Desktop sandboxes for a workspace, allowing config changes to take effect on next run. The command properly handles running sandboxes (stops first), multiple sandboxes for the same workspace, symlink resolution, and verifies removal.
## Evidence
- Commits: 7916085, b9af55b, 3b3432e, f016a1d, fa3db03, 760eddb
- Tests: bash -n containai.sh
- PRs: