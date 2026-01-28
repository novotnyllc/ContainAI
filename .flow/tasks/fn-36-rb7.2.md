# fn-36-rb7.2 Implement consistent --container semantics

## Description
Update `--container` behavior to be command-appropriate: use-or-create for shell/run/exec, require-exists for stop/export/import. Update help text and error messaging for the behavior change.

## Acceptance
- [ ] `cai shell --container foo` uses if exists, creates if missing
- [ ] `cai run --container foo` uses if exists, creates if missing
- [ ] `cai exec --container foo` uses if exists, creates if missing
- [ ] `cai stop --container foo` errors "Container foo not found" if missing
- [ ] `cai export --container foo` errors if missing
- [ ] `cai import --container foo` errors if missing
- [ ] Container name is saved to workspace state on successful create/use
- [ ] Help text documents "uses existing or creates new" behavior
- [ ] Errors guide users who expected old behavior

## Verification
- [ ] Run each command with a non-existent container and verify behavior
- [ ] Check help output for updated semantics

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
