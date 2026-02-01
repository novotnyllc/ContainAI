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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
