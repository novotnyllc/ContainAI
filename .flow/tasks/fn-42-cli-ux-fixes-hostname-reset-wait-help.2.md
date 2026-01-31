# fn-42-cli-ux-fixes-hostname-reset-wait-help.2 Graceful SSH wait during --fresh/--reset

## Description
When `--fresh` or `--reset` recreates a container, other SSH connections retry too quickly and create error storms. Implement graceful waiting so existing sessions wait for the new container to be SSH-ready before reconnecting.

**Size:** M
**Files:** `src/containai.sh`, `src/lib/ssh.sh`, `src/lib/container.sh`

## Approach

1. Add state flag when fresh/reset starts recreation:
   ```bash
   # At src/containai.sh around line 3284 (before container removal)
   touch "$_CONTAINAI_STATE_DIR/.container_recreating"
   ```

2. Clear flag after SSH is ready:
   ```bash
   # After _cai_setup_container_ssh succeeds
   rm -f "$_CONTAINAI_STATE_DIR/.container_recreating"
   ```

3. Modify SSH retry functions to check flag and wait:
   - In `_cai_ssh_run` and `_cai_ssh_shell` at `src/lib/ssh.sh`
   - If flag exists, wait with backoff instead of retrying immediately
   - Use `docker wait` or poll container status

4. Consider using inotifywait for efficient flag watching (if available)

## Key context

- Fresh/reset at `src/containai.sh:3254-3300`
- SSH wait logic at `src/lib/ssh.sh:837-934` (30s timeout with exponential backoff)
- SSH retry at `src/lib/ssh.sh:1920-1951`
- State dir: `$_CONTAINAI_STATE_DIR` (typically `~/.local/state/containai`)
- Memory pitfall: "Bash exit status capture: Capture `$?` immediately after command"
## Acceptance
- [ ] State flag created when --fresh/--reset starts recreation
- [ ] State flag removed after new container SSH-ready
- [ ] SSH functions detect flag and wait gracefully
- [ ] No error spam during container recreation
- [ ] Existing sessions reconnect smoothly after recreation completes
- [ ] Timeout behavior: if recreation takes too long, eventually fail with clear error
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
