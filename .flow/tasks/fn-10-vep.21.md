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
Extracted printf heredoc hacks from Dockerfile.test into external files: daemon.json config to src/configs/daemon-test.json, startup script to src/scripts/start-dockerd.sh, and test script to src/scripts/test-dind.sh. Updated Dockerfile.test to use COPY statements and updated README documentation to reference the new script paths.
## Evidence
- Commits: a82177da2fa85073bbf0416bd25f75156dc565b8, 51e3a48fe71a232a7d219a8aa3f2cac965117101
- Tests: shellcheck src/scripts/start-dockerd.sh, shellcheck src/scripts/test-dind.sh, jq . src/configs/daemon-test.json
- PRs: