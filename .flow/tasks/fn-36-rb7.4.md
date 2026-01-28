# fn-36-rb7.4 Implement --reset flag

## Description
Add `--reset` to regenerate workspace state values while keeping the workspace section. Generate a new unique volume name and persist it immediately.

## Acceptance
- [ ] `--reset` stops and removes existing container
- [ ] Workspace section is kept but values are regenerated
- [ ] Generates NEW unique volume name (`{repo}-{branch}-{timestamp}`)
- [ ] Writes new values to workspace state immediately (before container ops)
- [ ] Never falls back to `sandbox-agent-data`
- [ ] Next command uses newly persisted values
- [ ] Logs "[INFO] Resetting workspace state..."

## Verification
- [ ] Run `cai shell`, note volume, run `cai shell --reset`, verify different volume and workspace section still present

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
