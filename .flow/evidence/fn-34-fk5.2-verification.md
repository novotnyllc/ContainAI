# fn-34-fk5.2: stdio/stderr passthrough verification

## Summary

Code inspection verified that `_cai_ssh_run` and `_containai_exec_cmd` properly implement TTY allocation and real-time output streaming.

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

To test non-TTY mode explicitly:
```bash
cai exec -- ls -la < /dev/null  # stdin is not a TTY
echo "test" | cai exec -- cat   # piped input
```

### 3. Stdout/Stderr Stream in Real-Time ✅

**Location**: `src/lib/ssh.sh:2525-2556`

For non-detached mode:
- **Stdout**: Streams directly to terminal (line 2546 - no redirection)
- **Stderr**: Uses FIFO-based approach for capture + display:
  1. Creates a named pipe (FIFO) for stderr
  2. Runs `tee` in background to copy stderr to both a file and the terminal
  3. SSH runs with stderr redirected to the FIFO

### 4. Buffering Behavior ✅

**When `allocate_tty=true` (interactive terminal)**:
- SSH allocates a PTY on the remote side (`-t` flag)
- PTY typically results in line-buffered output for many programs
- Stdout flows directly to local terminal

**When `allocate_tty=false` (piped/script)**:
- No PTY allocated - remote process may use full buffering for stdout
- This is expected POSIX behavior for non-TTY contexts
- Programs can use `stdbuf -oL` if line buffering is needed

**Stderr handling**:
- FIFO kernel buffer (~64KB on Linux) holds data briefly
- `tee` processes data as it arrives from the FIFO
- No significant delay for typical error output

## Test Commands (Manual Verification)

```bash
# Test interactive command with TTY (should show TUI if htop available)
cai exec -- htop

# Test non-interactive command with TTY
cai exec -- ls -la

# Test stderr output
cai exec -- ls /nonexistent

# Test long-running output (should show numbers without visible delay)
cai exec -- seq 1 1000

# Test non-TTY mode (no -t flag)
cai exec -- seq 1 100 < /dev/null
```

## Code References

- TTY detection: `src/containai.sh:4231-4234`
- SSH -t flag: `src/lib/ssh.sh:2395-2398`
- Real-time streaming: `src/lib/ssh.sh:2525-2556`
- Detached mode handling: `src/lib/ssh.sh:2515-2524`
