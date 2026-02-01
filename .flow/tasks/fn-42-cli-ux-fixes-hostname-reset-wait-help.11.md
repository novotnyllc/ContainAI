# fn-42-cli-ux-fixes-hostname-reset-wait-help.11 Add --fresh/--reset wait-for-ready logic

## Description
Ensure that `--fresh` and `--reset` flags wait for SSH to become ready before returning control to the user. This prevents connection failures when the container is still starting up.

**Current Status:** Already implemented via existing SSH infrastructure.

## Implementation Notes

The wait-for-ready logic is already implemented through the SSH module's wait and retry mechanisms:

1. **`_cai_wait_for_sshd`** (`src/lib/ssh.sh:847-938`):
   - Waits up to 30 seconds (`_CAI_SSHD_WAIT_MAX=30`) for sshd to become ready
   - Uses exponential backoff starting at 100ms, doubling up to 2s max interval
   - Uses `ssh-keyscan` to detect when sshd is accepting connections
   - Verifies container is still running during wait

2. **`_cai_ssh_connect_with_retry`** (`src/lib/ssh.sh:1815-1980`):
   - Retries SSH connection up to 3 times with exponential backoff
   - Auto-recovers from stale host keys
   - Handles transient connection failures

3. **Fresh/Reset flow** (`src/containai.sh:3297-3554`):
   - Container is removed and recreated
   - SSH config is cleaned up via `_cai_cleanup_container_ssh`
   - `_cai_ssh_shell` is called with `force_update=true`
   - Since config file was removed, `_cai_setup_container_ssh` is invoked
   - `_cai_wait_for_sshd` waits for SSH to be ready before connecting

## Acceptance
- [x] `--fresh` waits for SSH-ready before connecting (via `_cai_wait_for_sshd`)
- [x] `--reset` waits for SSH-ready before connecting (same flow as `--fresh`)
- [x] Wait has configurable timeout (30s default via `_CAI_SSHD_WAIT_MAX`)
- [x] Exponential backoff prevents overwhelming the container
- [x] Clear error message if SSH doesn't become ready within timeout

## Done summary
Verified that the wait-for-ready logic is already implemented through the SSH module. The --fresh and --reset flags properly wait for SSH by:
1. Cleaning up old SSH config during container removal
2. Triggering full SSH setup on reconnection (since config file is missing)
3. Using _cai_wait_for_sshd which waits up to 30 seconds with exponential backoff

No code changes required - task documents existing implementation.
## Evidence
- Commits:
- Tests:
- PRs:
