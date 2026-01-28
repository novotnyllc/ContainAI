# fn-36-rb7.12 Update all commands to use workspace state

## Description
Update shell, run, exec, import, export, and stop to read/write workspace state with proper precedence and persistence.

## Acceptance
- [ ] `cai shell` reads workspace state, creates if missing, saves on first use
- [ ] `cai run` same behavior as shell
- [ ] `cai exec` same behavior as shell
- [ ] `cai import` reads workspace state to resolve container/volume
- [ ] `cai export` reads workspace state
- [ ] `cai stop` reads workspace state
- [ ] Precedence order enforced: CLI > env > workspace > repo-local > user-global > defaults
- [ ] CLI overrides are saved back to workspace state
- [ ] `--data-volume` with existing container using different volume errors with guidance

## Verification
- [ ] `cai shell` in new dir, exit, `cai import` uses same container/volume
- [ ] Set env/CLI overrides and verify precedence

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
