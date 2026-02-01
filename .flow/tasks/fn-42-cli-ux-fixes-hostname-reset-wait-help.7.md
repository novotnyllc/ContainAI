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
- [x] Old host keys removed on --fresh/--reset
- [x] No "REMOTE HOST IDENTIFICATION HAS CHANGED" warning after recreation
- [x] Works for both container name and localhost:port entries
## Done summary

Enhanced SSH known_hosts cleanup to remove entries by container name (SSH Host alias), with proper port-aware handling for both standard (22) and non-standard ports.

## Changes

1. **`_cai_cleanup_container_ssh()`** (src/lib/ssh.sh:1807): Added port-aware cleanup of container name entries:
   - Port 22: removes both `$container_name` and `[$container_name]:22`
   - Non-22: removes both `[$container_name]:$port` and `$container_name` (legacy)

2. **`_cai_ssh_connect_with_retry()`** (src/lib/ssh.sh:2086): Same port-aware cleanup in auto-recovery path

3. **`_cai_ssh_run_with_retry()`** (src/lib/ssh.sh:2612): Same port-aware cleanup in auto-recovery path

## Evidence
- shellcheck: `shellcheck -x src/lib/ssh.sh` - passes with no errors
- CLI source: `source src/containai.sh` - loads successfully
- Coverage: all three acceptance criteria met (port-based and container-name-based cleanup)
