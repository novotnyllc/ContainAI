# fn-10-vep.49 Update cai shell to use SSH instead of docker exec

## Description
Update `cai shell` to use SSH with bulletproof connection handling. The command must always succeed or provide clear, actionable error messages.

**Size:** M
**Files:** lib/container.sh, lib/ssh.sh

## Approach

1. Connection flow:
   - Find container for workspace
   - If not running, start it
   - Wait for sshd ready (from fn-10-vep.48)
   - Get SSH port from container label
   - Connect via SSH

2. Retry logic for transient failures:
   - Retry on "Connection refused" (sshd not ready)
   - Retry on timeout (network delay)
   - Max 3 retries with exponential backoff
   - Clear progress indication during retry

3. Auto-recovery from stale state:
   - If host key mismatch, auto-clean and retry
   - If SSH config missing, regenerate and retry
   - If port changed, update config and retry

4. Error handling:
   - Never fail silently
   - Provide specific error messages
   - Suggest remediation steps
   - Exit with appropriate codes

5. Handle `--fresh` flag:
   - Stop and remove existing container
   - Create new container
   - Regenerate SSH config

## Key context

- SSH must be transparent - user just runs `cai shell /path`
- Goal: user NEVER sees SSH errors unless container is truly broken
- Always provide next steps on failure
## Approach

1. Update `_containai_shell()`:
   - Find container for workspace
   - If not running, start it (or error)
   - Get SSH port from container label
   - Call SSH with: `ssh -F ~/.config/containai/ssh_config {container-name}`

2. Create SSH config helper that generates the connection string:
   - Uses `~/.config/containai/id_containai` as identity
   - Uses `~/.config/containai/known_hosts` for host verification
   - Connects to localhost on allocated port

3. Handle `--fresh` flag to recreate container

## Key context

- SSH must be transparent - user just runs `cai shell /path`
- Error clearly if container not found or SSH fails
- Preserve existing `--fresh` semantics
## Acceptance
- [ ] `cai shell /path/to/workspace` connects via SSH
- [ ] SSH uses dedicated containai key
- [ ] Retry on transient failures (connection refused, timeout)
- [ ] Max 3 retries with exponential backoff
- [ ] Auto-recover from stale host keys
- [ ] Auto-regenerate missing SSH config
- [ ] `--fresh` recreates container before connecting
- [ ] Clear error messages with remediation steps
- [ ] Agent forwarding works if configured
- [ ] Exit codes indicate specific failure types
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
