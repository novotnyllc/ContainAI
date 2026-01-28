# fn-36-rb7.6 Implement cai exec command

## Description
Add `cai exec` to run arbitrary commands inside the container via SSH. Extend `_cai_ssh_run` with a `--login-shell` mode that wraps commands with `bash -lc` using safe escaping.

## Acceptance
- [ ] `cai exec ls -la` runs inside the container
- [ ] Auto-creates/starts container if needed
- [ ] Allocates PTY if stdin is TTY (`ssh -t`)
- [ ] Streams stdout/stderr correctly
- [ ] Exit code passthrough from command
- [ ] `--` separates cai flags from command
- [ ] `_cai_ssh_run` supports `--login-shell`
- [ ] `--login-shell` uses `bash -lc '<escaped-command>'` with `printf %q`
- [ ] Existing `_cai_ssh_run` callers unchanged
- [ ] `--workspace` and `--container` flags work

## Verification
- [ ] `cai exec echo hello`
- [ ] `cai exec false` returns exit 1
- [ ] `cai exec -- --help` works
- [ ] Command with special chars is properly escaped

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
