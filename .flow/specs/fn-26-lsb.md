# fn-26-lsb Default cai shell and cai run to start in workspace directory

## Overview
When running `cai shell`, the SSH session should start with the current working directory set to `/home/agent/workspace` instead of the user's home directory (`/home/agent`). This matches the behavior of `cai run`, which already changes to the workspace directory before executing commands.

## Scope
- Modify `_cai_ssh_connect_with_retry` function in `src/lib/ssh.sh`
- No changes needed for `cai run` (already works correctly)

## Current Behavior
- `cai shell`: Opens SSH session at `/home/agent` (the user's home directory)
- `cai run`: Already changes to `/home/agent/workspace` before running commands (see lines 2076, 2079 in ssh.sh)

## Approach
Modify the SSH command in `_cai_ssh_connect_with_retry` to include a remote command that:
1. Changes to the workspace directory
2. Executes a login shell (preserving profile/bashrc processing)

The implementation will add the command after the host in the SSH invocation:
```bash
ssh_cmd+=("$_CAI_SSH_HOST")
ssh_cmd+=("cd /home/agent/workspace && exec \$SHELL -l")
```

This is the pattern already used by `_cai_ssh_run_with_retry` for running commands.

## Quick commands
- `source src/containai.sh && cai shell --help` - verify CLI loads
- Manual test: `cai shell` then run `pwd` to verify starting directory

## Acceptance
- [ ] `cai shell` starts with cwd at `/home/agent/workspace`
- [ ] Shell is a login shell with proper environment
- [ ] `cai run` behavior unchanged
- [ ] No regression in SSH connection/retry logic

## References
- `src/lib/ssh.sh` lines 1683-1860: `_cai_ssh_connect_with_retry` function
- `src/lib/ssh.sh` lines 2076, 2079: existing workspace cd pattern in `_cai_ssh_run_with_retry`
