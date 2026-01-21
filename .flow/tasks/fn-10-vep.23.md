# fn-10-vep.23 Create entrypoint hook for dockerd auto-start in sysbox

## Description
Create entrypoint hook to auto-start dockerd when running in a sysbox container.

**Size:** M
**Files:**
- `src/entrypoint.sh` (modify)
- `src/lib/docker-init.sh` (new helper)

## Context

When users run `cai` with sysbox runtime, dockerd should auto-start so agents can use Docker. The entrypoint needs to:
1. Detect if running in sysbox container
2. Start dockerd if in sysbox
3. Wait for dockerd to be ready
4. Continue with normal startup

## Approach

1. Create detection function for sysbox runtime
2. Add dockerd startup to entrypoint (before exec)
3. Use background process with wait loop
4. Don't fail container if dockerd fails (warn only)

## Key files to reference

- Current entrypoint: `agent-sandbox/entrypoint.sh`
- Sysbox detection: Check `/proc/1/root` or similar sysbox indicators
- Startup pattern: `Dockerfile.test` lines 121-141
## Acceptance
- [ ] Sysbox runtime detection works
- [ ] dockerd starts automatically in sysbox containers
- [ ] Container doesn't fail if dockerd fails (warn only)
- [ ] `docker info` works inside container after startup
- [ ] Normal (non-sysbox) containers still work
- [ ] Startup time increase is acceptable (<10s)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
