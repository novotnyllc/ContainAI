# fn-10-vep.49 Update cai shell to use SSH instead of docker exec

## Description
Update `cai shell` to use SSH instead of docker exec.

**Size:** M
**Files:** lib/container.sh, lib/ssh.sh

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
- [ ] No host key prompts (managed known_hosts)
- [ ] `--fresh` recreates container before connecting
- [ ] Clear error if container doesn't exist
- [ ] Clear error if SSH connection fails
- [ ] Agent forwarding works if configured
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
