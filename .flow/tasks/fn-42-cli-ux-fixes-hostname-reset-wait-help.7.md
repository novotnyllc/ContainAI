# fn-42-cli-ux-fixes-hostname-reset-wait-help.7 Auto-cleanup stale SSH known_hosts on container recreation

## Description
When container is recreated (--fresh/--reset), automatically remove old SSH host key from known_hosts to prevent "REMOTE HOST IDENTIFICATION HAS CHANGED" warnings.

**Size:** S
**Files:** `src/lib/ssh.sh`

## Approach

In `_cai_cleanup_container_ssh()` (already called during fresh/reset):

```bash
# Remove old host key
ssh-keygen -R "$container_name" 2>/dev/null || true
ssh-keygen -R "[localhost]:$ssh_port" 2>/dev/null || true
```

This should already be happening - verify it works correctly.

## Key context

- SSH cleanup at `src/lib/ssh.sh` in `_cai_cleanup_container_ssh()`
- Called from fresh/reset paths in `src/containai.sh`
- `ssh-keygen -R` removes entries from known_hosts
## Acceptance
- [ ] Old host keys removed on --fresh/--reset
- [ ] No "REMOTE HOST IDENTIFICATION HAS CHANGED" warning after recreation
- [ ] Works for both container name and localhost:port entries
## Done summary
## Summary

Enhanced SSH known_hosts cleanup in `_cai_cleanup_container_ssh()` to also remove entries by container name (SSH Host alias), preventing "REMOTE HOST IDENTIFICATION HAS CHANGED" warnings after container recreation.

## Changes

1. **`_cai_cleanup_container_ssh()`** (src/lib/ssh.sh:1807): Added cleanup of container name entries in known_hosts file. Users connecting via `ssh <container_name>` get entries with the alias that need to be cleaned on recreation.

2. **`_cai_ssh_connect_with_retry()`** (src/lib/ssh.sh:2076): Added container name cleanup in the auto-recovery path for host key mismatches.

3. **`_cai_ssh_run_with_retry()`** (src/lib/ssh.sh:2595): Added container name cleanup in the auto-recovery path for host key mismatches.

## Verification

- shellcheck passes with no errors
- CLI sources successfully
- Changes are minimal and focused on the specific issue
## Evidence
- Commits:
- Tests:
- PRs:
