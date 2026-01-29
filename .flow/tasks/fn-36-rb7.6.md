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
# fn-36-rb7.6 Implementation Summary: cai exec command

## Changes Made

### src/containai.sh
- Added `_containai_exec_help()` function documenting usage, options, TTY handling, exit codes, and examples
- Added `_containai_exec_cmd()` implementing the full exec command:
  - Argument parsing supporting all standard flags (--workspace, --container, --data-volume, --config, --fresh, --force, --quiet, --verbose, --debug)
  - `--` separator to distinguish cai flags from command arguments
  - Auto-create/start container if needed (same pattern as shell command)
  - Validates container ownership before exec
  - SSH port conflict detection and auto-recovery for stopped containers
  - TTY allocation when stdin is a terminal
  - Calls `_cai_ssh_run` with `--login-shell` for proper environment sourcing
- Added routing in `containai()` case statement for "exec" subcommand
- Updated main help text to include `cai exec` in subcommand list and examples
- All progress/info messages redirected to stderr for pipeline safety

### src/lib/ssh.sh
- Extended `_cai_ssh_run()` to support `--login-shell` as first argument
- Extended `_cai_ssh_run_with_retry()` to support `--login-shell` mode
- When `--login-shell`:
  - Wraps command in `bash -lc '<escaped-command>'`
  - Uses `printf %q` for safe argument escaping
  - Handles environment variable prefix arguments (VAR=value)
- Fixed TOCTOU race with FIFO creation (uses temp directory instead of mktemp -u)
- Improved fallback handling when mkfifo fails
- Updated function documentation

## All Acceptance Criteria Met
- [x] `cai exec ls -la` runs inside the container
- [x] Auto-creates/starts container if needed
- [x] Allocates PTY if stdin is TTY (`ssh -t`)
- [x] Streams stdout/stderr correctly (progress to stderr)
- [x] Exit code passthrough from command
- [x] `--` separates cai flags from command
- [x] `_cai_ssh_run` supports `--login-shell`
- [x] `--login-shell` uses `bash -lc '<escaped-command>'` with `printf %q`
- [x] Existing `_cai_ssh_run` callers unchanged
- [x] `--workspace` and `--container` flags work

## Review Issues Fixed
1. stdout contamination - All progress messages now go to stderr
2. TOCTOU race in FIFO creation - Uses temp directory
3. SSH port conflict recovery for stopped containers - Added detection and auto-recreate
4. Help text accuracy - Updated bash login shell documentation
5. Exit code consistency - Foreign containers now return 15 consistently
## Evidence
- Commits:
- Tests:
- PRs:
