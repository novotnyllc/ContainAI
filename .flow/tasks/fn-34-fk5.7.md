# fn-34-fk5.7: Document container lifecycle behavior

## Goal
Write documentation on container lifecycle: when containers are created, started, stopped, and destroyed.

## Content Outline
1. **Container Creation**
   - `cai run` creates container on first use
   - Uses workspace state for naming
   - Labels with `containai.managed=true`

2. **Container Starting**
   - Automatic start when stopped container accessed
   - SSH setup verification on start

3. **Container Stopping**
   - `cai stop` stops container (keeps volume)
   - Session warning before stop (unless `--force`)
   - `cai stop --export` for data backup

4. **Container Destruction**
   - `cai stop --remove` deletes container
   - `cai gc` prunes old stopped containers
   - Volume preserved unless explicitly removed

5. **GC Behavior**
   - Staleness based on FinishedAt timestamp
   - Protection rules (running, keep label)

## Files
- `docs/lifecycle.md`: New documentation file
- `docs/quickstart.md`: Link to lifecycle docs

## Acceptance
- [ ] Documents container creation conditions
- [ ] Documents start/stop behavior
- [ ] Documents volume lifecycle
- [ ] Documents GC behavior and protection rules

## Done summary
Created comprehensive container lifecycle documentation covering creation, starting, stopping, destruction, backup/export, garbage collection (planned), and status monitoring. Added link from quickstart guide.
## Evidence
- Commits: a0f5611, 11c0ace, 4e9e25e
- Tests:
- PRs:
