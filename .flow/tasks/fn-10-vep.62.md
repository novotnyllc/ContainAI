# fn-10-vep.62 Update docs/architecture.md with system container architecture

## Description
Update docs/architecture.md to explain the **system container** architecture - how sysbox enables VM-like containers with systemd, services, and DinD.

**Size:** M
**Files:** docs/architecture.md

## Key Concepts to Document

1. **What is a System Container?**
   - VM-like container that runs systemd as PID 1
   - Can run multiple services (sshd, dockerd, custom apps)
   - DinD without --privileged, thanks to sysbox

2. **Why Sysbox?**
   - Automatic user namespace mapping (no manual config)
   - Procfs/sysfs virtualization
   - Secure DinD capability
   - Stronger isolation than regular containers

3. **Architecture Layers**
   - Host: containai docker-ce with sysbox-runc
   - System Container: systemd, sshd, dockerd
   - Inner containers: built/run by agents

## Approach

1. System overview:
   - What is a system container
   - Sysbox runtime and what it provides
   - SSH-based access model

2. Diagrams (mermaid):
   - Container lifecycle (start, SSH connect, stop)
   - SSH connection flow
   - systemd service dependencies
   - Inner Docker (DinD) architecture

3. Security model:
   - Sysbox provides automatic userns mapping
   - Procfs/sysfs virtualization
   - cgroup limits for resource control

4. Component details:
   - cai CLI structure
   - SSH infrastructure
   - Container configuration

## Key context

- Use mermaid for all diagrams (renders on GitHub)
- Emphasize that sysbox handles isolation automatically
- No legacy references (no ECI, no docker exec)
## Acceptance
- [ ] Architecture overview updated
- [ ] SSH flow diagram (mermaid)
- [ ] systemd lifecycle diagram
- [ ] Container architecture diagram
- [ ] Component documentation
- [ ] NO legacy references (no ECI, no docker exec mentions)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
