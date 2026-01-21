# fn-10-vep.40 Create docker-containai context with sysbox-runc default

## Description
Create the `docker-containai` context with sysbox-runc as the default runtime.

**Size:** M
**Files:** lib/setup.sh, lib/doctor.sh

## Approach

1. In `_cai_setup_docker_context()`:
   - Create context via `docker context create docker-containai --docker "host=unix:///var/run/docker.sock"`
   - Configure daemon.json for the context with sysbox-runc as default runtime
   - Enable userns mapping in context configuration

2. Follow pattern at `lib/setup.sh:_cai_create_containai_context()` but update for new context name

## Key context

- Docker contexts are stored in `~/.docker/contexts/`
- daemon.json for context-specific config needs to be at different location
- sysbox-runc path: `/usr/bin/sysbox-runc`
## Acceptance
- [ ] `docker-containai` context created via `cai setup`
- [ ] Context uses sysbox-runc as default runtime
- [ ] userns mapping configured in context
- [ ] `docker --context docker-containai info` shows sysbox-runc available
- [ ] Existing contexts not affected
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
