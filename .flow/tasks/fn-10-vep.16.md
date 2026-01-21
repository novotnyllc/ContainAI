# fn-10-vep.16 Simplify Dockerfile.test (remove sysbox install)

## Description
Simplify `agent-sandbox/Dockerfile.test` based on the insight that tests will run inside an already-sysbox container. Remove sysbox installation and --privileged requirement.

**Size:** M
**Files:** 
- `agent-sandbox/Dockerfile.test` (rewrite)
- `agent-sandbox/docker/start-dockerd.sh` (new, extracted script)
- `agent-sandbox/docker/test-dind.sh` (new, extracted test script)

## Context

Current Dockerfile.test:
- Installs sysbox inside the image (unnecessary - parent already has sysbox)
- Uses printf heredocs for scripts (should use COPY)
- Requires --privileged (unnecessary in sysbox)
- Starts sysbox-mgr and sysbox-fs (unnecessary)

## Approach

1. Remove sysbox installation (lines 55-60)
2. Remove sysbox service startup from entrypoint
3. Extract scripts to separate files (no more printf heredocs)
4. Update README to remove --privileged requirement
5. Test that `docker build -f Dockerfile.test` works inside sysbox container

## Key files to reference

- Current: `agent-sandbox/Dockerfile.test` - lines 55-60 (sysbox install), 79-149 (startup script), 152-183 (test script)
- Pattern: Follow `agent-sandbox/Dockerfile` for COPY-based script handling
## Acceptance
- [ ] Sysbox installation removed from Dockerfile.test
- [ ] Scripts extracted to separate files (no printf heredocs)
- [ ] --privileged NOT required to run the test container
- [ ] Entrypoint just starts dockerd (no sysbox services)
- [ ] `docker build -f Dockerfile.test` succeeds
- [ ] Test container can run nested containers
- [ ] README.md updated to reflect simpler usage
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
