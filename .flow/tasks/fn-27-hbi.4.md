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
   - Use `sh -lc` wrapper for consistent command parsing
   - Add proper quoting for env vars and arguments
   - Verify command started before printing success message
   - Use pattern: `ssh -n -f user@host "nohup cmd >/dev/null 2>&1 & echo \$!"`

3. **Remove premature "Running in background" message** - Only print after confirming process started

## Key context

- Current code at line 2093-2094 prints "Running command in background via SSH..." before confirmation
- Use `-tt` (double t) to force TTY even when stdin is not a terminal
- For background: `-n` prevents stdin reading, `-f` backgrounds before command execution
- Reuse `_cai_ssh_run()` infrastructure per conventions.md
## Acceptance
- [ ] `cai shell` always opens interactive shell with TTY
- [ ] `cai shell` works even when stdin is piped/redirected
- [ ] Detached mode (`cai run --detached`) confirms command started
- [ ] Detached mode uses `sh -lc` for consistent parsing
- [ ] No "Running in background" message until command confirmed running
- [ ] SSH handles env vars and special characters correctly in detached mode
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
