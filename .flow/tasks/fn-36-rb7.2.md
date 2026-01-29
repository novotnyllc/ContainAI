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
Implemented consistent --container semantics: shell/run use-or-create (creates if missing, uses if exists), stop/export/import require-exists. Added --docker-context parameter to _containai_start_container for context consistency when reusing containers. Container name saved to workspace state on successful create/use. Help text updated to document new semantics and mutual exclusivity.
## Evidence
- Commits: 5464b5dfb095d0a0f1f032cef89df52854040808, 6af1e62, 13721cf, 661d795, ef16c35
- Tests: shellcheck -x src/containai.sh, cai shell --help | grep -A5 -- --container, cai stop --help | grep -A3 -- --container
- PRs:
