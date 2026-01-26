# fn-23-glf Fix CI build failures (sysbox + docker)

## Overview

Two CI workflows are failing due to architecture and build issues:

1. **build-sysbox.yml** - arm64 packages contain amd64 binaries due to build running on amd64 host
2. **docker.yml** - symlinks.sh fails silently during buildx with exit code 1

## Problem 1: Sysbox architecture mismatch

```
dpkg: error processing archive dist/sysbox-ce_0.6.7+containai.20260126.linux_arm64.deb (--install):
 package architecture (amd64) does not match system (arm64)
```

**Root cause**: The build runs on amd64 runners, so generated artifacts (including Debian arch metadata and Go binaries) are amd64, regardless of the `TARGET_ARCH` environment variable. The sysbox-pkgr toolchain infers architecture from the build host.

**Solution**: Build each architecture on native runners (amd64 on ubuntu-22.04, arm64 on ubuntu-24.04-arm). No QEMU, no cross-compilation needed.

## Problem 2: Docker buildx symlinks.sh failure

```
ERROR: failed to build: failed to solve: process "/bin/bash -o pipefail -c chmod +x /tmp/symlinks.sh && /tmp/symlinks.sh && rm /tmp/symlinks.sh" did not complete successfully: exit code: 1
```

**Root cause**: Silent failure - the script uses `#!/bin/sh` with `set -e` which exits on first error but doesn't show which command failed. The failure is deterministic (likely a link collision or permission issue).

**Solution**:
1. **Primary**: Convert symlinks.sh to bash and add deterministic logging that prints each command before execution and shows context on failure (path, ownership, permissions)
2. **Secondary**: Bust stale GHA cache by changing scope from `full` → `full-v2` (one-time change)
3. Run generators in CI workflow to ensure fresh files

## Quick commands

- `gh workflow run build-sysbox.yml` - trigger sysbox build
- `gh workflow run docker.yml` - trigger docker build
- `gh run list --workflow=build-sysbox.yml` - check sysbox runs
- `gh run list --workflow=docker.yml` - check docker runs

## Acceptance

### Sysbox workflow
- [ ] `build-amd64` job runs on `ubuntu-22.04`, `build-arm64` job runs on `ubuntu-24.04-arm`
- [ ] `TARGET_ARCH` is kept explicit in both jobs (set from `dpkg --print-architecture`)
- [ ] No QEMU setup steps
- [ ] `build-arm64` job includes explicit dependency install step for sysbox-pkgr requirements
- [ ] Both architectures pass CI

### Docker workflow
- [ ] Generators run before building agents layer
- [ ] symlinks.sh uses bash (`#!/usr/bin/env bash`) and logs each command before execution
- [ ] On failure, symlinks.sh shows failing command, `id`, and `ls -ld` of relevant paths
- [ ] Cache scope changed to `full-v2` (one-time bust)
- [ ] Build passes for both amd64 and arm64 platforms
- [ ] CI regenerates and uses generated files (doesn't require them to be up-to-date in git)

## References

- `.github/workflows/build-sysbox.yml`
- `.github/workflows/docker.yml`
- `src/container/Dockerfile.agents`
- `src/scripts/gen-dockerfile-symlinks.sh`
