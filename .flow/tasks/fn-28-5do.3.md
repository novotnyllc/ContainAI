# fn-28-5do.3 Investigate and fix SSH key issues

## Description

User reports "many keys" being generated incorrectly. The design specifies one SSH key per host (`~/.config/containai/id_containai`) with per-container entries in `known_hosts`. Need to investigate what's happening.

**Size:** S-M (depends on findings)
**Files:** `src/lib/ssh.sh`

## Investigation approach

1. Review key generation in `_cai_setup_ssh_key()` - should be idempotent
2. Check if `_cai_inject_ssh_key()` regenerates when it shouldn't
3. Review `_cai_update_known_hosts()` for accumulation issues
4. Check if container recreation causes key proliferation
5. Verify host key change detection works correctly

## Key context

- Single host key: `~/.config/containai/id_containai` (ed25519)
- Known hosts: `~/.config/containai/known_hosts` with per-port entries
- SSH config dir: `~/.ssh/containai.d/` for per-container configs
- `_cai_setup_ssh_key()` at line 153 - should skip if key exists
- `_cai_inject_ssh_key()` at line 942 - auto-generates if missing
- `_cai_update_known_hosts()` at line 1041 - handles host key storage

## Potential issues to check

1. Key regeneration on every container start?
2. known_hosts accumulating stale entries?
3. Multiple SSH config files in containai.d/?
4. Host key change warnings triggering incorrectly?

## Acceptance

- [ ] Root cause identified
- [ ] Fix implemented (if code issue found)
- [ ] One key per host confirmed
- [ ] known_hosts properly managed (stale entries cleaned)
- [ ] shellcheck passes (if code changed)
