# fn-10-vep.22 Add Docker CE to main Dockerfile for DinD

## Description
Add Docker CE (full installation) to the main Dockerfile so agents can use Docker inside the system container (DinD). Inner Docker defaults to sysbox-runc for consistent security.

**Size:** M
**Files:** src/Dockerfile

## Approach

1. Install Docker CE:
   - docker-ce (daemon)
   - docker-ce-cli
   - containerd.io
   - sysbox-ce (for inner Docker runtime)

2. Configure daemon.json for DinD with sysbox:
   - Default runtime: sysbox-runc (consistent with host)
   - Standard /var/lib/docker data path (inside container)
   - Sysbox enables DinD without --privileged

3. Do NOT start dockerd in Dockerfile - systemd handles that (fn-10-vep.46)

## Key context

- This is Docker INSIDE the sysbox system container (inner Docker)
- Inner Docker also uses sysbox-runc by default for security consistency
- dockerd is started by systemd (fn-10-vep.46)
- agent user needs docker group membership
- Sysbox handles all the complexity of enabling secure DinD

## Acceptance
- [ ] Docker CE (docker-ce, docker-ce-cli, containerd.io) installed
- [ ] sysbox-ce installed inside the container
- [ ] daemon.json configured with sysbox-runc as default runtime
- [ ] Image builds successfully
- [ ] Image size increase is reasonable
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
