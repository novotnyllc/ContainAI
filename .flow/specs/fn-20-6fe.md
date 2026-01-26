# Investigate runc 1.3.3 / Sysbox Incompatibility and Produce PRDs

## Problem

Docker run fails inside sysbox containers with error:
```
OCI runtime create failed: runc create failed: unable to start container process:
error during container init: open sysctl net.ipv4.ip_unprivileged_port_start file:
unsafe procfs detected: openat2 /proc/./sys/net/ipv4/ip_unprivileged_port_start:
invalid cross-device link
```

## Root Cause (Confirmed via Research)

runc 1.3.3 added security checks using `openat2()` with `RESOLVE_NO_XDEV` flag to detect "fake procfs". This conflicts with sysbox-fs which bind-mounts FUSE-backed files over `/proc/sys/*` paths.

**Key insight**: The fix exists in sysbox master but is **host-side** (sysbox-fs, sysbox-runc). ContainAI can only control the **image-side** (containerd.io package version).

## Scope

This epic is **investigation and PRD creation only** - NO implementation.

**Deliverables:**
1. Technical analysis document (`.flow/specs/fn-20-6fe-technical-analysis.md`)
2. PRD-A: Temporary workaround specification (`.flow/specs/prd-runc-downgrade-workaround.md`)
3. PRD-B: Proper fix options specification (`.flow/specs/prd-sysbox-dind-fix.md`)

**Out of scope for this epic:**
- Implementation changes (Dockerfiles, runtime packages, tests)
- Only docs/spec files are produced

**Allowed in Task 1 investigation:**
- OS-level artifact inspection (apt package downloads, .deb extraction)
- Upstream repo cloning for code archaeology
- No ContainAI image builds or DinD tests

## Ownership Boundary (Critical)

**By Deployment Mode:**

| Component | ContainAI-managed isolated daemon | Docker Desktop / external engine (support TBD) |
|-----------|-----------------------------------|------------------------------------------------|
| Host dockerd | `containai-docker` context managed by ContainAI (`src/lib/docker.sh`, `src/lib/setup.sh`) | Docker Inc default context |
| sysbox-fs, sysbox-runc | Host operator installs, ContainAI setup configures | Docker Inc (bundled in DD) |
| containerd.io, runc packages | ContainAI image (can pin) | ContainAI image (can pin) |
| Dockerfile.base/test | ContainAI repo (can modify) | ContainAI repo (can modify) |
| Inner Docker config | ContainAI image (can configure) | ContainAI image (can configure) |

**Context selection model** (from code analysis - Task 1 to verify):
- **Inside container**: Uses `default` context (`src/lib/doctor.sh:168-185`)
- **On host**: Prefers config override → `containai-docker` → legacy (`src/lib/doctor.sh:160-224`)
- **Native Linux**: May use default socket in some paths (`src/lib/doctor.sh:340-343`) - Task 1 to clarify

**Key insight**: ContainAI's intended architecture uses `containai-docker` isolated daemon + context. Docker Desktop ECI/"docker sandbox" support status is **TBD** - Task 1 produces this decision based on code evidence.

**ECI Support Status Decision Flow**:
1. **Task 1** produces "ECI Support Status (as-of repo commit)" section with code evidence
2. Decision question: Is Docker Desktop a **documented and exercised** engine for `cai`? (not just "could work if user sets override")
3. **Tasks 2/3** consume this decision as input - if unsupported, treat ECI as "external ecosystem context only"
4. Evidence to gather: `src/containai.sh:356-371` (sandbox removed), `src/lib/eci.sh` (missing), `src/lib/docker.sh:229-303` (`_cai_docker_desktop_version` - check if called), `src/lib/container.sh:1164-1186` (host flags rejected), `SECURITY.md`/`src/README.md` docs drift

## Key Findings from Research

### The Fix in Sysbox Master (Hypothesis - to be verified in Task 1)

Sysbox has implemented a fix using **seccomp syscall interception** (exact mechanism to be verified from code):

1. Trap all `openat2()` syscalls from processes inside sysbox containers
2. Check if the path is under a sysbox-fs mount (`/proc/sys/*`, etc.)
3. If yes, strip problematic flags (exact flag set to be quoted from sysbox-fs/sysbox-runc code - do NOT assume specific flags without evidence)
4. Open the file via nsenter and inject the fd using `SECCOMP_IOCTL_NOTIF_ADDFD`

**This is a host-side fix** - operators must upgrade sysbox; ContainAI cannot ship this.

### ContainAI-Controllable Workaround

Pin containerd.io to a version bundling runc < 1.3.3. This is image-side and can be shipped by ContainAI, but has security trade-offs (CVE rollback).

## Quick Commands (for investigation)

```bash
# Clone repos at immutable refs
WORKDIR=$(mktemp -d)
git clone --depth 1 --branch v1.3.3 https://github.com/opencontainers/runc.git "$WORKDIR/runc"
git clone https://github.com/nestybox/sysbox-fs.git "$WORKDIR/sysbox-fs"
git clone https://github.com/nestybox/sysbox-runc.git "$WORKDIR/sysbox-runc"

# Find the runc check
grep -r "RESOLVE_NO_XDEV" "$WORKDIR/runc/"

# Find the sysbox fix
grep -r "openat2" "$WORKDIR/sysbox-fs/seccomp/"
```

## Acceptance

- [ ] Technical analysis document produced with immutable commit refs
- [ ] **PRD-A produced**: Temporary runc downgrade workaround with formal risk acceptance
- [ ] **PRD-B produced**: Proper fix options with ownership boundary clarity
- [ ] No implementation performed in this epic

## References

- [sysbox#973](https://github.com/nestybox/sysbox/issues/973) - Docker 28.5.2 breaks DinD on Sysbox
- [sysbox#972](https://github.com/nestybox/sysbox/issues/972) - Original bug report (closed)
- [runc#4968](https://github.com/opencontainers/runc/issues/4968) - AppArmor/LXC related issues
- [runc v1.3.3](https://github.com/opencontainers/runc/releases/tag/v1.3.3) - Release with security patches
