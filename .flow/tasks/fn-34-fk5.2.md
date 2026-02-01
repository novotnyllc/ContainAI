# fn-34-fk5.2: Verify stdio/stderr passthrough

## Goal
Verify that `_cai_ssh_run` properly allocates TTY for interactive commands and streams output to host terminal in real-time.

## Context
The existing `_cai_ssh_run` function in `src/lib/ssh.sh` handles SSH execution. This task verifies it works correctly.

## Verification Steps
1. Test interactive command with TTY: `cai exec -- htop` (should show TUI)
2. Test non-interactive command: `cai exec -- ls -la` (should output correctly)
3. Test stderr: `cai exec -- ls /nonexistent` (should show error on stderr)
4. Test long-running output: `cai exec -- seq 1 1000` (no buffering delay)

## Files
- `src/lib/ssh.sh`: `_cai_ssh_run` function (lines 2185-2290)

## Acceptance
- [ ] Interactive commands get TTY (`-t` flag when `allocate_tty=true`)
- [ ] Non-interactive commands work without TTY
- [ ] Stdout and stderr stream to host in real-time
- [ ] No output buffering delays
