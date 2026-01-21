# fn-10-vep.22 Add Docker CLI and dockerd to main Dockerfile

## Description
Add Docker CLI and dockerd installation to the main Dockerfile so agents can use Docker inside the container.

**Size:** M
**Files:**
- `src/docker/Dockerfile`

## Context

The main image is based on `docker/sandbox-templates:claude-code`. We need to add:
- Docker CE (daemon)
- Docker CLI
- containerd

## Approach

1. Add Docker repository and GPG key
2. Install docker-ce, docker-ce-cli, containerd.io
3. Configure daemon.json for sysbox compatibility (no NAT)
4. Do NOT start dockerd in Dockerfile (entrypoint handles that)

## Key context

- Base image: `docker/sandbox-templates:claude-code`
- Reference: `Dockerfile.test` lines 46-53 for Docker installation
- No --privileged needed when running in sysbox
## Acceptance
- [ ] Docker CE installed in main image
- [ ] Docker CLI available
- [ ] containerd.io installed
- [ ] daemon.json configured for sysbox (--iptables=false, --ip-masq=false)
- [ ] Image builds successfully
- [ ] Image size increase is reasonable (<500MB)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
