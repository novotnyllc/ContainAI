# fn-26-lsb.1 Modify _cai_ssh_connect_with_retry to start shell in workspace directory

## Description
Update the `_cai_ssh_connect_with_retry` function in `src/lib/ssh.sh` to start the SSH shell session in `/home/agent/workspace` instead of the user's home directory.

The change is simple: after building the SSH command with all options, add the remote command to change to the workspace directory and execute a login shell:

```bash
# Before:
ssh_cmd+=("$_CAI_SSH_HOST")
# After:
ssh_cmd+=("$_CAI_SSH_HOST")
ssh_cmd+=("cd /home/agent/workspace && exec \$SHELL -l")
```

This matches the pattern already used by `_cai_ssh_run_with_retry` for running commands in the workspace.

## Acceptance
- [ ] `cai shell` starts with cwd at `/home/agent/workspace`
- [ ] Shell is a login shell (proper .profile/.bashrc sourced)
- [ ] SSH retry logic still works on connection failures
- [ ] Host key auto-recovery still works

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
