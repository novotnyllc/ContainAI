# fn-27-hbi.4 SSH shell TTY allocation and detached execution reliability

## Description
Fix SSH shell TTY allocation and detached command execution reliability. Currently `cai shell` sometimes exits without opening shell, and detached mode doesn't confirm command started.

**Size:** M
**Files:** `src/lib/ssh.sh`

## Approach

1. **Fix TTY allocation for shell** - Modify `_cai_ssh_shell()` at line 1727-1738:
   - Always use `ssh -tt` to force pseudo-TTY allocation
   - Ensure shell is always interactive regardless of stdin state

2. **Fix detached execution** - Modify `_cai_ssh_run_with_retry()` at line 2081-2094:
   - Use `bash -lc` wrapper for consistent command parsing (bash is guaranteed in ContainAI containers)
   - Note: `printf %q` produces bash-compatible escaping, so `bash -lc` matches our quoting
   - Add proper quoting for env vars and arguments
   - Return PID from remote command: `nohup cmd >/dev/null 2>&1 & echo $!`
   - Verify command started with `kill -0 $pid` before printing success

3. **Remove premature "Running in background" message** - Only print after confirming process started with PID verification

## Key context

- Current code at line 2093-2094 prints "Running command in background via SSH..." before confirmation
- Use `-tt` (double t) to force TTY even when stdin is not a terminal
- For background: `-n` prevents stdin reading, `-f` backgrounds before command execution
- ContainAI containers have bash installed - use `bash -lc` to match `printf %q` escaping
- Reuse `_cai_ssh_run()` infrastructure per conventions.md

## Acceptance
- [ ] `cai shell` always opens interactive shell with TTY
- [ ] `cai shell` works even when stdin is piped/redirected
- [ ] Detached mode (`cai run --detached`) confirms command started via PID
- [ ] Detached mode uses `bash -lc` for consistent parsing (matches printf %q escaping)
- [ ] No "Running in background" message until command confirmed running
- [ ] SSH handles env vars and special characters correctly in detached mode
- [ ] PID returned and verified with kill -0 before success message

## Done summary
Improved SSH shell TTY allocation and detached execution reliability. Shell now uses -tt flag to force TTY even when stdin is piped. Detached mode uses bash -lc wrapper with proper single-quote escaping for consistent command parsing, returns PID for verification, and handles short-lived commands gracefully.
## Evidence
- Commits: 3737684, 70d5a9d, d1f4ef4
- Tests: shellcheck -x src/lib/ssh.sh
- PRs:
