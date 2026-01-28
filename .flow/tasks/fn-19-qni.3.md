# fn-19-qni.3 Fix workspace symlink creation

## Description
Fix workspace symlink creation so that the expected symlink (e.g., `/home/claire/dev/ContainAI -> /agent/home/workspace`) gets created inside the container. Users report this symlink is not appearing.

**Size:** S
**Files:** `src/lib/container.sh`, `src/container/containai-init.sh`

## Approach

### Diagnosis needed first

1. Check if `CAI_HOST_WORKSPACE` is being set during `docker run` in `_containai_start_container()`
2. Check if `CAI_HOST_WORKSPACE` reaches the init script (env var propagation)
3. Check if path validation at `containai-init.sh:282-297` is rejecting the path
4. Check if `run_as_root ln -sfn` is failing silently

### Likely fixes

1. Ensure `-e CAI_HOST_WORKSPACE=...` is passed to `docker run` at `src/lib/container.sh:1650-1750`
2. If path validation is too strict, add more allowed prefixes or fix pattern matching
3. Add better error reporting if symlink creation fails

### Key context

- Symlink implementation at `src/container/containai-init.sh:278-318`
- Path validation allows: `/home/`, `/tmp/`, `/mnt/`, `/workspaces/`, `/Users/`
- Must use `run_as_root` because symlink needs root privileges in container
- Pitfall from memory: `ln -sfn to directory paths needs rm -rf first if destination may exist as real directory`
## Acceptance
- [ ] `CAI_HOST_WORKSPACE` env var passed to container correctly
- [ ] Symlink created: `/home/*/dev/* -> /agent/home/workspace` (user's path)
- [ ] Symlink survives container restart
- [ ] Path validation accepts common workspace paths
- [ ] Error logged if symlink creation fails (not silent failure)
- [ ] Works on both systemd (containai-init.sh) and non-systemd (entrypoint.sh) paths
- [ ] Integration test verifies symlink existence
## Done summary
Superseded - merged into fn-34-fk5
## Evidence
- Commits:
- Tests:
- PRs:
