# fn-10-vep.66 Verify DinD works in sysbox system containers

## Description
Verify that Docker-in-Docker works correctly in sysbox system containers. This validates that agents can build and run containers inside their isolated environment.

**Size:** M
**Files:** tests/integration/test-dind.sh

## Why DinD Matters

System containers enable agents to:
- Run `docker build` to create images
- Run `docker run` to test containers
- Use docker-compose for multi-container setups
- All without --privileged, thanks to sysbox

## Approach

1. Create a test that:
   - Starts a sysbox system container via containai docker-ce
   - Waits for inner dockerd to start (uses sysbox-runc by default)
   - Runs `docker run hello-world` inside the container
   - Verifies nested container ran successfully

2. Test cases:
   - Basic DinD: `docker run hello-world`
   - Build inside container: `docker build -t test .`
   - Volume mounts in nested container
   - Network connectivity from nested container

3. Error cases:
   - Verify clear error if dockerd fails to start
   - Verify timeout handling

## Key context

- Inner Docker uses sysbox-runc by default (configured in daemon.json)
- Sysbox enables DinD without --privileged
- Inner Docker data lives in container's /var/lib/docker
- Requires sysbox-runc runtime on the containai docker-ce

## Acceptance
- [ ] Test script for DinD verification exists
- [ ] `docker run hello-world` works inside sysbox system container
- [ ] `docker build` works inside sysbox system container
- [ ] Nested container networking works
- [ ] Clear error message if dockerd fails to start
- [ ] Test is part of CI suite
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
