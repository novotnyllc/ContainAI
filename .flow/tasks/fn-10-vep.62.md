# fn-10-vep.62 Update docs/architecture.md with SSH and systemd diagrams

## Description
Update docs/architecture.md with SSH and systemd diagrams.

**Size:** M
**Files:** docs/architecture.md

## Approach

1. Update container lifecycle diagram:
   - Show systemd as PID 1
   - Show sshd and dockerd services
   - Show containai-init oneshot

2. Add SSH flow diagram:
   - Setup: key generation, config.d injection
   - Connection: port allocation, pub key injection, known_hosts
   - Runtime: cai shell/run → SSH

3. Update data flow diagram:
   - Host → Container via SSH
   - Workspace mount
   - Data volume mount

4. Add security model section:
   - sysbox isolation
   - userns mapping
   - cgroup limits

## Key context

- Use mermaid for all diagrams (renders on GitHub)
- Keep existing useful content, update outdated sections
## Acceptance
- [ ] Container lifecycle diagram updated (systemd + services)
- [ ] SSH flow diagram added (setup, connection, runtime)
- [ ] Data flow diagram updated
- [ ] Security model section added
- [ ] All diagrams render correctly on GitHub (mermaid)
- [ ] Table of contents updated
- [ ] Links from README work correctly
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
