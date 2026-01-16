# fn-2-kcs.3 PR3: Build script enhancements with BuildKit

## Description
Enhance build.sh with configurable build args and add OCI standard labels to Dockerfile.

## Build Script Changes

### DOTNET_CHANNEL Option
Add `--dotnet-channel` option to build.sh:
```bash
./build.sh --dotnet-channel lts      # Use latest LTS
./build.sh --dotnet-channel 10.0     # Use specific version
```

Default should remain `10.0` for consistency.

### Base Image Configuration
Add build arg for base image:
```bash
./build.sh --base-image docker/sandbox-templates:claude-code
```

### BuildKit Enablement
Set `DOCKER_BUILDKIT=1` by default in build.sh.

## Dockerfile Changes

### OCI Standard Labels
Add to Dockerfile:
```dockerfile
LABEL org.opencontainers.image.source="https://github.com/<repo>"
LABEL org.opencontainers.image.description="Agent Sandbox for AI coding assistants"
LABEL org.opencontainers.image.licenses="MIT"
```

Build args for dynamic labels:
```dockerfile
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${VCS_REF}"
```

Update build.sh to pass these:
```bash
--build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
--build-arg VCS_REF="$(git rev-parse HEAD)"
```

## Files to Modify
- `agent-sandbox/build.sh`
- `agent-sandbox/Dockerfile`
## Acceptance
- [ ] `--dotnet-channel` option added to build.sh
- [ ] Base image configurable via `--base-image` option
- [ ] `DOCKER_BUILDKIT=1` set by default in build.sh
- [ ] OCI standard labels added to Dockerfile
- [ ] Dynamic labels (BUILD_DATE, VCS_REF) passed at build time
- [ ] `./build.sh --help` shows all options
- [ ] `./build.sh` works with defaults
- [ ] `./build.sh --dotnet-channel lts` works
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
