# fn-10-vep.43 Create base Dockerfile layer (systemd + sshd + dockerd)

## Description
Create the base Dockerfile layer with systemd, sshd, dockerd, and basic tooling.

**Size:** M
**Files:** src/Dockerfile.base (new), src/systemd/ (new directory)

## Approach

1. Base from `ubuntu:24.04` (latest LTS)
2. Install systemd, openssh-server, docker.io
3. Configure systemd as init (`/sbin/init --log-level=err`)
4. Mask unnecessary systemd units (per nestybox/dockerfiles pattern)
5. Create `agent` user with proper permissions
6. Setup `/home/agent/.bashrc.d/` pattern for modular bashrc
7. Install base tools: tmux, jq, yq, bun
8. Configure sshd: PermitRootLogin no, PasswordAuthentication no
9. Set STOPSIGNAL to SIGRTMIN+3

## Key context

- Pattern from practice-scout: nestybox/dockerfiles for systemd in containers
- Mask: systemd-journald-audit.socket, systemd-udev-trigger.service, systemd-firstboot.service
- sshd hardening: key-only auth, no root login
## Acceptance
- [ ] `src/Dockerfile.base` created
- [ ] Base image is `ubuntu:24.04`
- [ ] systemd installed and configured as init
- [ ] openssh-server installed with hardened config
- [ ] docker.io (dockerd + CLI) installed
- [ ] `agent` user created with home directory
- [ ] `/home/agent/.bashrc.d/` directory exists
- [ ] tmux, jq, yq, bun installed
- [ ] STOPSIGNAL is SIGRTMIN+3
- [ ] Image builds successfully with `docker build -f src/Dockerfile.base`
- [ ] Container starts with `docker run --runtime=sysbox-runc -d`
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
