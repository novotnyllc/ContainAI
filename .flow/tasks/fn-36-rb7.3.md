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
Implemented --fresh flag behavior per spec: logs "[INFO] Recreating container..." at start of --fresh block (regardless of container existence), skips workspace state writes to preserve existing settings.
## Evidence
- Commits: decee872da66f9dd5f6b6d0490d04fd4ca64b78a, a660552ac306769dd9ddc09737c576ca5a916852
- Tests: bash -n src/containai.sh, shellcheck -x src/containai.sh
- PRs:
