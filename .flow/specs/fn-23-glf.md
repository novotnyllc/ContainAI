# fn-23-glf Fix CI build failures (sysbox + docker)

## Overview

Two CI workflows are failing due to architecture and build issues:

1. **build-sysbox.yml** - arm64 packages contain amd64 binaries (QEMU cross-compilation doesn't work for Go)
2. **docker.yml** - symlinks.sh fails silently during buildx with exit code 1

## Problem 1: Sysbox architecture mismatch

```
dpkg: error processing archive dist/sysbox-ce_0.6.7+containai.20260126.linux_arm64.deb (--install):
 package architecture (amd64) does not match system (arm64)
```

**Root cause**: QEMU emulation on amd64 hosts doesn't cross-compile Go binaries correctly. Go detects the host architecture, producing amd64 binaries even with `TARGET_ARCH=arm64`.

**Solution**: Build each architecture on native runners. No QEMU, no cross-compilation.

## Problem 2: Docker buildx symlinks.sh failure

```
ERROR: failed to build: failed to solve: process "/bin/bash -o pipefail -c chmod +x /tmp/symlinks.sh && /tmp/symlinks.sh && rm /tmp/symlinks.sh" did not complete successfully: exit code: 1
```

**Root cause**: Silent failure - `set -e` exits without showing which command failed. Likely GHA cache staleness or permission issues with `/mnt/agent-data`.

**Solution**: Add error reporting to symlinks.sh, run generators in CI workflow, bust stale cache.

## Quick commands

- `gh workflow run build-sysbox.yml` - trigger sysbox build
- `gh workflow run docker.yml` - trigger docker build
- `gh run list --workflow=build-sysbox.yml` - check sysbox runs
- `gh run list --workflow=docker.yml` - check docker runs

## Acceptance

### Sysbox workflow
- [ ] amd64 builds on ubuntu-22.04, tests on ubuntu-latest
- [ ] arm64 builds on ubuntu-24.04-arm, tests on ubuntu-24.04-arm
- [ ] No QEMU setup steps
- [ ] Both architectures pass CI

### Docker workflow
- [ ] Generators run before building agents layer
- [ ] symlinks.sh includes error context on failure
- [ ] Build passes for both amd64 and arm64 platforms

## References

- `.github/workflows/build-sysbox.yml`
- `.github/workflows/docker.yml`
- `src/container/Dockerfile.agents`
- `src/scripts/gen-dockerfile-symlinks.sh`
