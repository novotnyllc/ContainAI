# fn-10-vep.43 Create base Dockerfile layer (systemd + sshd + dockerd)

## Description
Create the base Dockerfile layer for a **system container** - Ubuntu 24.04 LTS with systemd, sshd, AND dockerd for DinD support. This is the foundation of ContainAI's VM-like container environment.

**Size:** M
**Files:** src/Dockerfile.base

## What is a System Container?

A system container runs like a lightweight VM:
- **systemd as PID 1** - real init system, service management
- **Multiple services** - sshd, dockerd, custom services
- **DinD without --privileged** - Sysbox enables this safely
- **Automatic isolation** - Sysbox handles user namespace mapping

## Approach

1. Base image: Ubuntu 24.04 LTS
2. Install systemd and configure as PID 1
3. Install and configure sshd:
   - `PermitRootLogin no`
   - `PasswordAuthentication no`
   - `PubkeyAuthentication yes`
4. Install Docker CE + sysbox for DinD:
   - docker-ce, docker-ce-cli, containerd.io
   - sysbox-ce for secure inner container runtime
   - Configure daemon.json with sysbox-runc as default
   - Inner Docker uses /var/lib/docker inside the container
5. Create agent user with proper home directory
6. Add agent user to docker group
7. Set up /home/agent/.bashrc.d/ pattern for modular shell config
8. Install essential tools: tmux, jq, yq, bun
9. Configure SIGRTMIN+3 for graceful shutdown

## Key context

- This is a SYSTEM CONTAINER - runs systemd, multiple services
- Inner Docker also uses sysbox-runc by default for security consistency
- Inner Docker data at /var/lib/docker (inside container, isolated)
- agent user needs docker group membership for DinD access
- Pattern from nestybox/dockerfiles for systemd in containers
- Mask: systemd-journald-audit.socket, systemd-udev-trigger.service, systemd-firstboot.service
- sshd hardening: key-only auth, no root login

## Acceptance
- [ ] Base image is Ubuntu 24.04 LTS
- [ ] systemd as init (PID 1)
- [ ] sshd installed and configured for key-only auth
- [ ] docker-ce + sysbox-ce installed for DinD
- [ ] Inner Docker configured with sysbox-runc as default runtime
- [ ] agent user created with docker group membership
- [ ] /home/agent/.bashrc.d/ pattern set up
- [ ] tmux, jq, yq, bun installed
- [ ] Image builds successfully
- [ ] Image tagged: containai/base
## Done summary
Created src/Dockerfile.base - the foundation layer for ContainAI system containers with Ubuntu 24.04 LTS, systemd as PID 1, hardened sshd (key-only auth), Docker CE with Sysbox for secure DinD, and essential tools (tmux, jq, yq, bun with checksums).
## Evidence
- Commits: 44b8119, 0065c2b, 5378b0b
- Tests: Dockerfile syntax validated by impl-review, All acceptance criteria verified against spec
- PRs: