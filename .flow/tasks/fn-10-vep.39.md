# fn-10-vep.39 Implement workspace-to-container auto-mapping with name hashing

## Description
Implement workspace-to-container auto-mapping with clear lifecycle model: PID 1 is `sleep infinity`, agent sessions use `docker exec`.

**Size:** M  
**Files:** `src/lib/container.sh`

## Approach

1. **Container lifecycle model**:
   - PID 1 is `sleep infinity` (long-lived init process)
   - Agent sessions attach via `docker exec -it <container> <command>`
   - Container stays running between sessions

2. **Portable container naming**:
   ```bash
   _cai_hash_path() {
     local path="$1"
     local normalized
     normalized=$(cd "$path" 2>/dev/null && pwd -P || printf '%s' "$path")
     
     if command -v shasum >/dev/null 2>&1; then
       printf '%s' "$normalized" | shasum -a 256 | cut -c1-12
     elif command -v sha256sum >/dev/null 2>&1; then
       printf '%s' "$normalized" | sha256sum | cut -c1-12
     else
       printf '%s' "$normalized" | openssl dgst -sha256 | awk '{print substr($NF,1,12)}'
     fi
   }
   
   container_name="containai-$(_cai_hash_path "$workspace_path")"
   ```

3. **Container reuse logic**:
   ```bash
   existing=$(docker ps -aq --filter "name=^${container_name}$")
   if [[ -n "$existing" ]]; then
     if docker inspect -f '{{.State.Running}}' "$existing" 2>/dev/null | grep -q true; then
       docker exec -it "$existing" "$@"  # Attach to running
     else
       docker start "$existing"  # Start stopped container
       docker exec -it "$existing" "$@"  # Then attach
     fi
   else
     docker run -d --name "$container_name" ... sleep infinity
     docker exec -it "$container_name" "$@"
   fi
   ```

4. **Fresh start flag**: `cai run --fresh /path` removes existing container first

## Key context

- sha256sum is Linux only; macOS has shasum
- Path normalization with realpath/pwd -P before hashing
- sleep infinity is portable and low-resource
- docker exec preserves container state
## Approach

1. **Container naming convention**:
   ```bash
   container_name="containai-$(echo "$workspace_path" | sha256sum | cut -c1-12)"
   ```
   - Deterministic: same workspace always gets same container name
   - Short: 12-char hash is unique enough, fits in logs

2. **Container reuse logic** in `_containai_run()`:
   ```bash
   existing=$(docker ps -aq --filter "name=^${container_name}$")
   if [[ -n "$existing" ]]; then
     if [[ "$(docker inspect -f '{{.State.Running}}' "$existing")" == "true" ]]; then
       docker exec -it "$existing" "$@"  # Attach to running
     else
       docker start -ai "$existing"  # Start stopped container
     fi
   else
     docker run ... --name "$container_name" ...  # Create new
   fi
   ```

3. **Fresh start flag**:
   - `cai run --fresh /path` removes existing container first
   - Useful for resetting state or after config changes

4. **Label for tracking**:
   ```bash
   --label "containai.workspace=$workspace_path"
   --label "containai.created=$(date -Iseconds)"
   ```

## Key context

- Docker Desktop sandbox uses same pattern: one sandbox per workspace
- Container naming must be shell-safe (no special chars)
- sha256sum is available on all platforms (Linux, macOS, WSL)
- Data volume (`/mnt/agent-data`) is separate - not affected by container removal
## Acceptance
- [ ] Container PID 1 is `sleep infinity` (long-lived init)
- [ ] Agent sessions use `docker exec -it <container> <command>`
- [ ] Container stays running between sessions
- [ ] Container name uses portable hashing (shasum/sha256sum/openssl)
- [ ] Path normalized before hashing (realpath/pwd -P)
- [ ] `cai run /path` reuses existing container for same path
- [ ] Running container uses exec; stopped container is started then exec
- [ ] `cai run --fresh /path` removes and recreates container
- [ ] Hashing works on both Linux and macOS
- [ ] Data volume persists even when container is removed with --fresh
## Done summary
Implemented workspace-to-container auto-mapping with deterministic naming via SHA-256 path hashing. Containers now use sleep infinity as PID 1 (long-lived init) with agent sessions attaching via docker exec, allowing containers to persist between sessions. Added --fresh flag to remove and recreate containers while preserving data volumes.
## Evidence
- Commits: 793ab6bcaea1f8cffd9da226a3de50d09464202f
- Tests: bash -n src/lib/container.sh, bash -n src/containai.sh, source src/lib/core.sh && source src/lib/container.sh && _cai_hash_path /home/claire/dev/ContainAI, source src/lib/core.sh && source src/lib/container.sh && _containai_container_name /home/claire/dev/ContainAI
- PRs: