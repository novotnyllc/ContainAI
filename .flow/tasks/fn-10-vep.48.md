# fn-10-vep.48 Implement SSH pub key injection and known_hosts management

## Description
Implement SSH public key injection and known_hosts management.

**Size:** M
**Files:** lib/ssh.sh, lib/container.sh

## Approach

1. Create `_cai_inject_ssh_key()`:
   - Read pubkey from `~/.config/containai/id_containai.pub`
   - Use `docker exec` to add key to `/home/agent/.ssh/authorized_keys`
   - Set proper permissions (700 on .ssh, 600 on authorized_keys)
   - Only inject if not already present (idempotent)

2. Create `_cai_update_known_hosts()`:
   - Run `ssh-keyscan -p $port localhost` to get container's host key
   - Append to `~/.config/containai/known_hosts`
   - Use `StrictHostKeyChecking=accept-new` in generated config

3. Create `_cai_write_ssh_host_config()`:
   - Write host entry to `~/.ssh/containai.d/{container-name}.conf`

## Key context

- Practice-scout: Use StrictHostKeyChecking=accept-new (not "no")
- ssh-keyscan can fail if sshd not ready - add retry with backoff
- Permissions are critical: 600 for authorized_keys, 700 for .ssh
## Acceptance
- [ ] Public key injected into container's authorized_keys
- [ ] Proper permissions set (700 .ssh, 600 authorized_keys)
- [ ] known_hosts updated with container's host key
- [ ] SSH host config written to `~/.ssh/containai.d/{name}.conf`
- [ ] StrictHostKeyChecking=accept-new in generated config
- [ ] Idempotent: re-running doesn't duplicate keys
- [ ] Handles sshd startup delay (retry logic)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
