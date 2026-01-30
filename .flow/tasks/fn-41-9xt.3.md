# fn-41-9xt.3 Update SSH and container functions for verbose state

## Description
Update SSH and container library functions to use the global verbose state instead of passing `quiet` parameter. Remove redundant info messages that are now gated by verbose.

**Size:** M
**Files:** `src/lib/ssh.sh`, `src/lib/container.sh`

## Approach

1. In `ssh.sh`: Remove explicit `quiet` parameter checks where `_cai_info` is now auto-gated
2. In `ssh.sh`: Keep function signatures but simplify internal logic
3. In `container.sh`: Same approach - rely on global verbose state
4. Test that `cai ssh` is silent by default
5. Test that `cai ssh --verbose` shows connection messages

Key locations in ssh.sh:
- `_cai_ssh_shell()` at line ~1700 (has quiet param)
- `_cai_ssh_connect_with_retry()` at line ~1812 (has quiet param)
- `_cai_ssh_run()` at line ~1987 (has quiet param)
- Connection message at line ~1877-1878

## Key context

Current pattern checks `[[ "$quiet" != "true" ]]` before emitting. After task 1, `_cai_info()` is self-gating, so these explicit checks become redundant and can be simplified.
## Acceptance
- [ ] `cai ssh <container>` is silent by default (no "Connecting..." message)
- [ ] `cai ssh <container> --verbose` shows connection messages
- [ ] `cai shell` is silent by default
- [ ] `cai shell --verbose` shows status messages
- [ ] Container lifecycle messages are gated by verbose
- [ ] shellcheck passes on ssh.sh and container.sh
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
