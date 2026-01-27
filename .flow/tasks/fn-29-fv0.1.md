# fn-29-fv0.1 Fix SSH double setup causing Permission denied

## Description
Fix the SSH double setup bug that causes "Permission denied (publickey)" after `cai shell --fresh`.

**Size:** M
**Files:** `src/lib/ssh.sh`, `src/lib/container.sh`

## Problem

The logs show SSH setup happening TWICE:
1. `container.sh:2263` calls `_cai_setup_container_ssh(force_update="true")` during container creation
2. `ssh.sh:1659` in `_cai_ssh_shell()` checks `if [[ ! -f "$config_file" ]] || [[ "$force_update" == "true" ]]` and calls setup AGAIN

The double setup appears to cause key/config corruption or race conditions.

## Approach

1. In `_cai_ssh_shell()` at `ssh.sh:1653-1676`:
   - Change condition to ONLY call setup if config file is actually missing
   - Remove `force_update` from SSH setup trigger (it's meant for container state, not SSH)
   - The caller (`container.sh`) already ran setup, so shell just needs to verify config exists

2. In `_cai_ssh_run()` at `ssh.sh:1956` - apply same fix

3. Verify `_cai_setup_ssh_key()` at `ssh.sh:153-233` is truly idempotent:
   - Check that it skips key generation when key already exists
   - Ensure `cai setup` doesn't regenerate keys blindly

## Key context

- `_cai_setup_container_ssh()` at `ssh.sh:1469-1509` does: inject key, update known_hosts, write host config
- Each of these should be idempotent but rapid double-calls may cause races
- The `force_update` flag is passed from container lifecycle, not from SSH needs
## Acceptance
- [ ] `cai shell --fresh` followed by `cai shell` connects without "Permission denied"
- [ ] SSH setup messages appear only ONCE in output (not twice)
- [ ] `cai setup` preserves existing SSH keys (doesn't regenerate if present)
- [ ] Existing containers continue to work (no regression)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
