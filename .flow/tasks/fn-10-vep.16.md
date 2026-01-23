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
- [ ] Sysbox services NOT started in Dockerfile.test (sysbox-mgr/sysbox-fs removed from entrypoint)
- [ ] Sysbox binary installed for inner Docker to use sysbox-runc as default runtime
- [ ] Scripts extracted to separate files
- [ ] --privileged NOT required (sysbox handles this)
- [ ] Inner Docker configured with sysbox-runc as default
- [ ] Entrypoint starts dockerd for DinD (no sysbox services)
- [ ] `docker build -f Dockerfile.test` succeeds
- [ ] Test container can run nested containers
- [ ] DinD verification tests pass

**Note:** Original acceptance said "Sysbox installation removed" but this conflicts with
"Inner Docker configured with sysbox-runc as default" (requires the binary). Resolution:
install sysbox for the binary, but do NOT start sysbox services. See decisions.md.
## Done summary
Simplified Dockerfile.test for sysbox system container environment: removed sysbox service startup from entrypoint, kept sysbox binary for inner Docker sysbox-runc support, removed --privileged requirement, updated documentation to reflect new runtime model.
## Evidence
- Commits: ce767b2, 0c29694, 440becc, 8b04c55, ddf4302, 89ea266
- Tests: shellcheck -x src/scripts/start-dockerd.sh src/scripts/test-dind.sh
- PRs:
