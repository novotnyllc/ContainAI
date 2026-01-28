# fn-36-rb7.3 Implement --fresh flag

## Description
Add `--fresh` to recreate containers with the same saved settings and volume, without modifying workspace state.

## Acceptance
- [ ] `--fresh` stops and removes existing container
- [ ] Creates new container with the same name from workspace state
- [ ] Uses the same data volume (no new volume)
- [ ] Does not modify workspace state entries
- [ ] Works if no container exists (just creates)
- [ ] Logs "[INFO] Recreating container..."

## Verification
- [ ] Create container, run `cai shell --fresh`, verify new container ID and same volume

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
