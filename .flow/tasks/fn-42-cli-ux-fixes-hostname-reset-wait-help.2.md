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
- [x] State flag created when --fresh/--reset starts recreation
- [x] State flag removed after new container SSH-ready
- [x] SSH functions detect flag and wait gracefully
- [x] No error spam during container recreation
- [x] Existing sessions reconnect smoothly after recreation completes
- [x] Timeout behavior: if recreation takes too long, eventually fail with clear error

## Done summary
Implemented graceful SSH waiting during container recreation with a per-container state flag mechanism:

1. **State flag management** (`src/lib/ssh.sh`):
   - Added `_CAI_STATE_DIR` (~/.local/state/containai) for ephemeral runtime state (XDG-compliant)
   - Added `_CAI_RECREATE_STATE_DIR` ($STATE_DIR/recreating) for flag storage
   - `_cai_set_recreating()`: Atomic flag creation (touch tmp + mv) with 700 permissions
   - `_cai_clear_recreating()`: Removes flag after SSH-ready or on failure
   - `_cai_is_recreating()`: Checks if recreation is in progress
   - `_cai_get_file_mtime()`: Portable mtime helper (Linux/macOS compatible)
   - `_cai_wait_for_recreation()`: Waits up to 60s with exponential backoff, uses mtime for stale detection
   - `_cai_wait_if_recreating()`: Centralized helper used by all SSH retry loops

2. **Recreation signaling** (`src/containai.sh`):
   - Set flag at start of --fresh/--reset block
   - Clear flag on early failures (ownership check, docker rm failure, container creation failure)
   - Flag automatically cleared by `_cai_setup_container_ssh` on success

3. **SSH connection graceful wait** (`src/lib/ssh.sh`):
   - `_cai_ssh_connect_with_retry`: Uses `_cai_wait_if_recreating` helper
   - `_cai_ssh_run`: Uses same helper for consistent behavior
   - On connection failure: detects recreation, resets retry counter after wait completes
   - Stale flags (>120s old) trigger failure with warning, not silent success

## Evidence
- Commits: (pending)
- Tests: shellcheck validation passed, bash -n syntax check passed
- PRs:
