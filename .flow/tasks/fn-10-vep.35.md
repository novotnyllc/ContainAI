# fn-10-vep.35 Implement workspace symlink strategy in entrypoint

## Description
Implement workspace symlink strategy in entrypoint.sh using environment variable (not docker inspect). Keep existing `/home/agent/workspace` mount path to minimize blast radius.

**Size:** M  
**Files:** `src/scripts/entrypoint.sh`, `src/lib/container.sh`

## Approach

1. **In container.sh**: Pass original path via environment variable:
   ```bash
   -e CAI_HOST_WORKSPACE="$workspace_resolved"
   ```
   
2. **Keep existing mount path**: `/home/agent/workspace` (not `/workspace`)
   - This matches current codebase, CLI, docs, and tests
   - Minimizes changes needed

3. **In entrypoint.sh**: Read env var and create symlink:
   ```bash
   setup_workspace_symlink() {
     local host_path="${CAI_HOST_WORKSPACE:-}"
     local mount_path="/home/agent/workspace"
     
     if [[ -n "$host_path" && "$host_path" != "$mount_path" ]]; then
       mkdir -p "$(dirname "$host_path")" 2>/dev/null || true
       ln -sfn "$mount_path" "$host_path" 2>/dev/null || true
     fi
   }
   ```

4. **No docker inspect** - would require Docker socket inside container

## Key context

- Docker inspect from inside container requires mounting Docker socket (defeats isolation)
- Environment variables are the safe way to pass metadata into containers
- Keep /home/agent/workspace to avoid cross-cutting changes to CLI, docs, tests
## Approach

1. **In container.sh**: Mount workspace at `/workspace` (not original path):
   ```bash
   -v "$workspace_resolved:/workspace:rw"
   ```
   
2. **In container.sh**: Pass original path as label:
   ```bash
   --label "containai.workspace=$workspace_resolved"
   ```

3. **In entrypoint.sh**: Replace `discover_mirrored_workspace()`:
   - Workspace is always at `/workspace`
   - Read original path from container label via `/proc/1/environ` or inspect
   - Create symlink from original path to `/workspace`:
     ```bash
     mkdir -p "$(dirname "$ORIGINAL_PATH")"
     ln -sfn /workspace "$ORIGINAL_PATH"
     ```
   - This allows tools expecting `/home/user/project` to work

4. **Handle edge cases**:
   - Original path contains special characters (quote properly)
   - Original path matches /workspace (no symlink needed)
   - Symlink already exists (update it)
## Acceptance
- [ ] Workspace mounted at /home/agent/workspace (existing path)
- [ ] Original host path passed via CAI_HOST_WORKSPACE env var
- [ ] Entrypoint reads env var (not docker inspect)
- [ ] Entrypoint creates symlink from original path to mount point
- [ ] Symlink creation gracefully handles permission errors
- [ ] Works with paths containing spaces
- [ ] Idempotent - rerunning entrypoint doesn't break symlink
- [ ] No Docker socket needed inside container
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
