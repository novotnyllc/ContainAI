# fn-10-vep.21 Clean up Dockerfiles: remove printf heredoc hacks

## Description
Clean up Dockerfile and Dockerfile.test to remove printf/heredoc hacks. Use proper COPY statements and external files following Docker best practices.

**Size:** M
**Files:**
- `src/docker/Dockerfile` (after restructure)
- `src/docker/Dockerfile.test`
- `src/docker/scripts/start-dockerd.sh` (new)
- `src/docker/scripts/test-dind.sh` (new)
- `src/docker/configs/daemon.json` (new)

## Context

Current Dockerfile.test uses printf heredocs for:
- Lines 79-148: Startup script (`start-test-docker.sh`)
- Lines 152-183: Test helper script (`test-docker-sysbox.sh`)
- Lines 66-74: daemon.json configuration

This is fragile and hard to maintain.

## Approach

1. Extract daemon.json to `src/docker/configs/daemon.json`
2. Extract startup script to `src/docker/scripts/start-dockerd.sh`
3. Extract test script to `src/docker/scripts/test-dind.sh`
4. Replace printf statements with COPY
5. Update any paths in the scripts

## Key files to reference

- Current: `agent-sandbox/Dockerfile.test:66-183`
- Pattern: `agent-sandbox/Dockerfile` uses COPY for entrypoint.sh
## Acceptance
- [ ] No printf heredoc hacks in Dockerfiles
- [ ] Scripts extracted to separate files
- [ ] COPY statements used for all embedded content
- [ ] daemon.json in configs/ directory
- [ ] Startup scripts in scripts/ directory
- [ ] Dockerfile.test builds successfully
- [ ] All tests still pass
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
