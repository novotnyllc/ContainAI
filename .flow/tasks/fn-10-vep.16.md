# fn-10-vep.16 Simplify Dockerfile.test for system container testing

## Description
Simplify `Dockerfile.test` to leverage the sysbox system container environment. The test container runs INSIDE a sysbox system container, so it doesn't need to install sysbox itself - the host already provides that isolation.

**Size:** M
**Files:** src/Dockerfile.test, src/docker/start-dockerd.sh, src/docker/test-dind.sh

## Why This Works

The test container runs inside a sysbox system container:
- **Host docker-ce** runs the test container with `--runtime=sysbox-runc`
- **Sysbox provides** the isolation, user namespace mapping, DinD capability
- **No --privileged needed** because sysbox handles it
- **Inner Docker** (inside test container) uses sysbox-runc too

## Approach

1. Remove redundant sysbox installation (host provides it)
2. Remove --privileged requirement (sysbox handles isolation)
3. Extract scripts to separate files (no printf heredocs)
4. Configure inner Docker daemon.json with sysbox-runc
5. Entrypoint starts dockerd for DinD testing
6. Include DinD verification tests

## Context

Current Dockerfile.test issues:
- Installs sysbox inside the image (redundant - host sysbox provides isolation)
- Uses printf heredocs for scripts (should use COPY)
- Requires --privileged (unnecessary when running in sysbox)
- Starts sysbox-mgr and sysbox-fs inside (unnecessary)

## Key files to reference

- Current: `agent-sandbox/Dockerfile.test`
- Pattern: Follow `agent-sandbox/Dockerfile` for COPY-based script handling

## Acceptance
- [ ] Sysbox installation removed from Dockerfile.test (not needed)
- [ ] Scripts extracted to separate files
- [ ] --privileged NOT required (sysbox handles this)
- [ ] Inner Docker configured with sysbox-runc as default
- [ ] Entrypoint starts dockerd for DinD
- [ ] `docker build -f Dockerfile.test` succeeds
- [ ] Test container can run nested containers
- [ ] DinD verification tests pass
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
