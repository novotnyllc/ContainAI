# fn-34-fk5.2: stdio/stderr passthrough verification

## Summary

Code review verified that `_cai_ssh_run` and `_containai_exec_cmd` properly implement TTY allocation and real-time output streaming.

## Verification Results

### 1. TTY Allocation for Interactive Commands ✅

**Location**: `src/containai.sh:4231-4234`
```bash
# Allocate TTY if stdin is a TTY
if [[ -t 0 ]]; then
    allocate_tty="true"
fi
```

**Location**: `src/lib/ssh.sh:2395-2398`
```bash
# Allocate TTY for interactive commands
if [[ "$allocate_tty" == "true" ]]; then
    ssh_cmd+=(-t)
fi
```

The `-t` flag is added to SSH when `allocate_tty=true`, and `cai exec` correctly detects interactive terminals using `[[ -t 0 ]]`.

### 2. Non-Interactive Commands Work Without TTY ✅

When stdin is not a terminal (piped input, scripts), `[[ -t 0 ]]` returns false, so `allocate_tty` remains `"false"` and no `-t` flag is added. This allows proper operation for non-interactive batch commands.

### 3. Stdout/Stderr Stream in Real-Time ✅

**Location**: `src/lib/ssh.sh:2525-2556`

For non-detached mode, the implementation uses a FIFO-based approach:
1. Creates a named pipe (FIFO) for stderr
2. Runs `tee` in background to copy stderr to both a file and the terminal
3. SSH runs with stderr redirected to the FIFO
4. Stdout streams directly (no redirection)

This ensures:
- Stdout appears immediately on the terminal
- Stderr appears immediately on the terminal AND is captured for error classification
- No output is lost

### 4. No Output Buffering Delays ✅

The FIFO + background tee pattern avoids buffering because:
- Named pipes (FIFOs) have small buffers that force immediate reads
- `tee` processes data as it arrives
- SSH's stdout is not redirected at all - it flows directly to the terminal

## Test Commands (Manual Verification)

```bash
# Test interactive command with TTY (should show TUI if htop available)
cai exec -- htop

# Test non-interactive command
cai exec -- ls -la

# Test stderr output
cai exec -- ls /nonexistent

# Test long-running output (should show numbers without delay)
cai exec -- seq 1 1000
```

## Code References

- TTY detection: `src/containai.sh:4231-4234`
- SSH -t flag: `src/lib/ssh.sh:2395-2398`
- Real-time streaming: `src/lib/ssh.sh:2525-2556`
- Detached mode handling: `src/lib/ssh.sh:2515-2524`
