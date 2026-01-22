# fn-10-vep.39 Implement workspace-to-container auto-mapping with name hashing

## Description
Implement workspace-to-container auto-mapping with clear lifecycle model: `--init` (tini) as PID 1 for zombie reaping, running `sleep infinity`. Agent sessions use `docker exec`.

**Size:** M
**Files:** `src/lib/container.sh`

## Approach

1. **Container lifecycle model**:
   - PID 1 is tini (`--init`) for proper zombie reaping, running `sleep infinity`
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

- sha256sum is Linux only; macOS has shasum (implementation uses fallback chain)
- Path normalization with pwd -P before hashing
- tini (--init) + sleep infinity for proper zombie reaping
- docker exec preserves container state
- Docker Desktop sandbox uses same pattern: one sandbox per workspace
- Container naming must be shell-safe (no special chars)
- Data volume (`/mnt/agent-data`) is separate - not affected by container removal
- FR-4 mount validation ensures shell --volume cannot taint run containers
## Acceptance
- [ ] Container uses `--init` (tini) as PID 1 for zombie reaping, running `sleep infinity`
- [ ] Agent sessions use `docker exec -it <container> <command>`
- [ ] Container stays running between sessions
- [ ] Container name uses portable hashing (shasum/sha256sum/openssl)
- [ ] Path normalized before hashing (realpath/pwd -P)
- [ ] `cai run /path` reuses existing container for same path
- [ ] Running container uses exec; stopped container is started then exec
- [ ] `cai run --fresh /path` removes and recreates container
- [ ] Hashing works on both Linux and macOS
- [ ] Data volume persists even when container is removed with --fresh
- [ ] FR-4 mount validation prevents tainted containers from being used by run
## Done summary
Implemented workspace-to-container auto-mapping with deterministic naming via SHA-256 path hashing. Containers use tini (--init) as PID 1 for zombie reaping, running sleep infinity as a child process. Agent sessions attach via docker exec, allowing containers to persist between sessions. Added --fresh flag to remove and recreate containers while preserving data volumes. FR-4 mount validation prevents tainted containers from being used by run.
## Evidence
- Commits: 793ab6bcaea1f8cffd9da226a3de50d09464202f
- Tests: bash -n src/lib/container.sh, bash -n src/containai.sh, source src/lib/core.sh && source src/lib/container.sh && _cai_hash_path /home/claire/dev/ContainAI, source src/lib/core.sh && source src/lib/container.sh && _containai_container_name /home/claire/dev/ContainAI
- PRs: