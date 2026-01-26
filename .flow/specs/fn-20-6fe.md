# Fix Docker-in-Docker runc 1.3.3 Incompatibility

## Problem

Docker run fails inside sysbox containers with error:
```
OCI runtime create failed: runc create failed: unable to start container process:
error during container init: open sysctl net.ipv4.ip_unprivileged_port_start file:
unsafe procfs detected: openat2 /proc/./sys/net/ipv4/ip_unprivileged_port_start:
invalid cross-device link
```

## Root Cause

runc 1.3.3 security patches (CVE-2025-31133, CVE-2025-52565, CVE-2025-52881) detect Sysbox's procfs bind mounts as "fake procfs" and intentionally reject them. Per runc maintainer:

> "The error you are getting is different and would be caused by a bind mount being placed on top of `/proc/...` and is thus an expected error."

This is tracked as [sysbox issue #973](https://github.com/nestybox/sysbox/issues/973).

## Scope

- Diagnose and fix current container by pinning containerd.io to exact working version
- Update Dockerfile.base and Dockerfile.test with version pin
- Verify fix with integration tests using correct image
- Document as known limitation with security trade-off notes

## Approach

Pin `containerd.io` apt package to an **exact version** proven to bundle runc < 1.3.3. The specific version will be determined in Task 1 by:
1. Checking available containerd.io versions: `apt-cache madison containerd.io`
2. Downgrading and verifying runc version: `runc --version`
3. Confirming DinD works with that exact version

**Security trade-off**: This workaround temporarily reverts protections from CVE-2025-31133, CVE-2025-52565, CVE-2025-52881 within the container. These CVEs relate to container escape vectors that are already mitigated by Sysbox's user namespace isolation. The workaround is scoped to inner Docker only and will be removed when Sysbox releases a compatibility fix (track: sysbox#973).

**Key files:**
- `src/container/Dockerfile.base:151-172` - docker-ce/containerd.io installation
- `src/container/Dockerfile.test:51-82` - test container installation
- `tests/integration/test-dind.sh` - DinD integration test

## Quick commands

```bash
# Verify containerd.io and runc versions inside container
apt-cache policy containerd.io
runc --version
docker info | grep -E 'containerd|runc'

# Test DinD works
docker run --rm alpine:latest echo "DinD works"

# Run integration test with local image
CONTAINAI_TEST_IMAGE=containai/base:latest ./tests/integration/test-dind.sh
```

## Acceptance

- [ ] `docker run --rm alpine:latest echo hello` succeeds inside sysbox container
- [ ] `tests/integration/test-dind.sh` passes with `CONTAINAI_TEST_IMAGE=containai/base:latest`
- [ ] containerd.io pinned to exact version (with runc < 1.3.3) in Dockerfile.base
- [ ] containerd.io pinned to exact version in Dockerfile.test
- [ ] Known limitation documented in pitfalls.md with security trade-off notes
- [ ] Pitfall entry includes removal criteria (Sysbox compatibility release)

## References

- [sysbox#973](https://github.com/nestybox/sysbox/issues/973) - Docker 28.5.2 breaks DinD on Sysbox
- [runc#4968](https://github.com/opencontainers/runc/issues/4968) - CVE-2025-52881 fd reopening issue
- [containerd#12484](https://github.com/containerd/containerd/issues/12484) - workaround discussion
