# fn-10-vep.48 Implement SSH pub key injection and known_hosts management

## Description
Implement SSH pub key injection and known_hosts management with sshd readiness checking and retry logic.

**Size:** M
**Files:** lib/ssh.sh

## Approach

1. Wait for sshd ready before key injection:
   - Poll with exponential backoff (100ms, 200ms, 400ms...)
   - Max wait: 30 seconds
   - Check via `docker exec` to test sshd status

2. Pub key injection:
   - Inject public key to `/home/agent/.ssh/authorized_keys`
   - Set proper permissions (600 for file, 700 for .ssh dir)

3. known_hosts management:
   - Use `ssh-keyscan` to get container's host key
   - Store in `~/.config/containai/known_hosts`
   - Auto-clean stale entries on `--fresh` flag

4. Handle stale host keys:
   - On connection failure due to host key mismatch, offer to clean
   - Auto-clean when container is recreated with `--fresh`

## Key context

- sshd may take 1-5 seconds to start after container boot
- Host key changes when container is recreated
- Use `ssh-keyscan -p <port> localhost` for key retrieval
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
- [ ] sshd readiness check with exponential backoff (max 30s)
- [ ] Pub key injected to /home/agent/.ssh/authorized_keys
- [ ] Proper permissions set (600/700)
- [ ] known_hosts populated via ssh-keyscan
- [ ] Stale known_hosts entries cleaned on `--fresh`
- [ ] Clear error if sshd doesn't start within timeout
- [ ] No host key prompts during normal operation
## Done summary
Implemented complete SSH pub key injection and known_hosts management with sshd readiness checking and exponential backoff retry logic.

Added functions to lib/ssh.sh:
- `_cai_wait_for_sshd()` with exponential backoff (100ms-2s, max 30s) using wall-clock time tracking
- `_cai_inject_ssh_key()` for authorized_keys management with proper 700/600 permissions (idempotent)
- `_cai_update_known_hosts()` with ssh-keyscan, flock-based concurrency safety, and per-key-type change detection
- `_cai_clean_known_hosts()` using ssh-keygen -R for safe removal
- `_cai_check_ssh_accept_new_support()` for OpenSSH version detection
- `_cai_write_ssh_host_config()` with fallback to StrictHostKeyChecking=yes on OpenSSH < 7.6
- `_cai_setup_container_ssh()` as main entry point with quick_check mode for running containers
- `_cai_cleanup_container_ssh()` for --fresh/--restart cleanup

Code review fixes applied:
- Filter ssh-keyscan comment lines to prevent known_hosts corruption
- Use awk for exact field matching instead of regex with [localhost]:port
- Check lock FD open result for graceful permission handling
- Move SSH cleanup after container removal confirmation
- Add quick_check mode for running containers to reduce latency
## Evidence
- Commits: ce940bc feat(ssh): implement SSH pub key injection and known_hosts management, 7f2333c fix(ssh): address code review issues for known_hosts management
- Tests:
- PRs: