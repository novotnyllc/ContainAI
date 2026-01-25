# Sysbox Compatibility with Devcontainer Patterns

Analysis of which devcontainer patterns are compatible with Sysbox runtime (ContainAI's security foundation) and which require workarounds or break entirely.

## Executive Summary

Sysbox provides strong compatibility with most devcontainer patterns. Its key strength - secure Docker-in-Docker without `--privileged` - directly addresses the most common "dangerous" devcontainer requirement.

**Qualitative compatibility assessment:**
- **Full compatibility:** Most patterns work unchanged (image, commands, users, ports)
- **Enhanced compatibility:** DinD patterns work better than with regular Docker
- **Conditional compatibility:** Some patterns require kernel version or configuration
- **Incompatible:** Host socket access, raw privileged mode, custom Docker data-root

**Methodology note:** Pattern usage frequencies are derived from [usage-analysis.md](usage-analysis.md) which analyzed 50 real-world devcontainer configurations from major repositories.

---

## Sysbox Capability Overview

### What Sysbox Virtualizes

| Capability | Sysbox Behavior | Evidence |
|-----------|----------------|----------|
| **User namespace** | Always enabled; root in container maps to unprivileged user on host (e.g., 165536) | [doc-link: security.md#user-namespace](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#user-namespace) |
| **Cgroup namespace** | Always enabled for isolation | [doc-link: security.md#cgroup-namespace](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#cgroup-namespace) |
| **/proc virtualization** | Partial virtualization via sysbox-fs FUSE daemon | [doc-link: security.md#procfs-virtualization](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#procfs-virtualization) |
| **/sys virtualization** | Partial virtualization; `/sys/fs/cgroup` is read-write | [doc-link: security.md#sysfs-virtualization](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#sysfs-virtualization) |
| **Mount syscall** | Allowed with immutability restrictions on initial mounts | [doc-link: security.md#initial-mount-immutability](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#initial-mount-immutability--v030-) |
| **Nested containers** | Fully supported via DinD/KinD | [doc-link: dind.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md) |
| **Systemd as PID 1** | Fully supported | [doc-link: systemd.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/systemd.md) |
| **Privileged inner containers** | Allowed but contained within outer user namespace | [doc-link: dind.md#inner-docker-privileged-containers](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#inner-docker-privileged-containers) |

### What Sysbox Blocks or Restricts

| Capability | Restriction | Reason | Evidence |
|-----------|-------------|--------|----------|
| **AppArmor profiles** | Ignored (not enforced) | Docker's default profile too restrictive for system containers | [doc-link: security.md#apparmor](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#apparmor) |
| **SELinux** | Not supported | Technical limitation | [doc-link: security.md#selinux](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#selinux) |
| **Host device access** | Not supported (--device flag) | Security isolation | [doc-link: security.md#devices](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#devices) |
| **Read-only mount remount to RW** | Blocked for immutable mounts | Prevent isolation escape | [doc-link: security.md#initial-mount-immutability](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#initial-mount-immutability--v030-) |
| **Mounting host's /var/lib/docker** | Blocked | Would expose sibling containers | [doc-link: dind.md#persistence-of-inner-docker-images](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#persistence-of-inner-docker-images) |
| **userns-remap on inner Docker** | Not supported | Technical limitation, planned for future | [doc-link: dind.md#inner-docker-userns-remap](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#inner-docker-userns-remap) |
| **Inner Docker data-root override** | Not supported | Must use /var/lib/docker | [doc-link: dind.md#inner-docker-data-root](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#inner-docker-data-root) |

---

## Compatibility Matrix

Each pattern includes per-row evidence classification:
- **doc-link**: Explicitly stated in Sysbox documentation (with citation)
- **inferred**: Reasonable expectation based on related documented behavior
- **empirical-test**: Would require testing to confirm (not performed for this research)

### Pattern 1: Docker-in-Docker Feature

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| `docker-in-docker:2` feature | Requires DinD support | Native support without --privileged | COMPATIBLE | [doc-link: dind.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md) |
| Inner Docker daemon | Works normally | Works; inner Docker uses runc by default | COMPATIBLE | [doc-link: dind.md#running-docker-inside-the-container](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#running-docker-inside-the-container) |
| Nested container builds | `docker build` inside | Works correctly | COMPATIBLE | [doc-link: dind.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md) |
| Multi-arch builds | `docker buildx` | Requires kernel 6.7+ for namespaced binfmt_misc | PARTIAL | [doc-link: dind.md#inner-docker-multi-arch-builds](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#inner-docker-multi-arch-builds--v067-) |
| Inner privileged containers | `docker run --privileged` | Allowed but contained in outer userns | COMPATIBLE | [doc-link: dind.md#inner-docker-privileged-containers](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#inner-docker-privileged-containers) |

**Key Finding:** Sysbox's primary design goal is secure DinD. This is ContainAI's strongest compatibility point - 22% of analyzed repos use docker-in-docker feature (see [usage-analysis.md](usage-analysis.md)).

**Workaround for multi-arch:** On kernel < 6.7, binfmt_misc is not namespaced. Multi-arch builds require host-level QEMU setup before launching the Sysbox container.

---

### Pattern 2: `--privileged` Requests

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| `privileged: true` property | Full host capabilities | Container created but userns isolation still enforced | MITIGATED | inferred from [security.md#linux-namespaces](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#linux-namespaces) |
| `--privileged` in runArgs | Same as above | Same as above | MITIGATED | inferred |
| Why privileged is requested | Usually for DinD | Sysbox provides DinD without privileged | N/A | [doc-link: dind.md intro](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#intro) |

**Behavior clarification:**

When `docker run --runtime=sysbox-runc --privileged` is used, the container is created successfully, but the `--privileged` flag does not grant host-level capabilities. Sysbox always enforces user namespace isolation regardless of this flag. This is inferred from Sysbox's documented behavior that it "always uses all Linux namespaces" including user namespace ([security.md#linux-namespaces](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#linux-namespaces)).

**Note:** The devcontainer `privileged: true` property is translated to Docker's `--privileged` flag by the devcontainer CLI. When Sysbox is the runtime, the practical effect is that DinD works (which is usually why privileged is requested) but without actual host privilege escalation.

**Workaround:** For most use cases (DinD), no workaround needed. For true privileged use cases (kernel module loading, raw device access), Sysbox is not suitable - use a VM instead.

---

### Pattern 3: Custom User Configurations

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| `remoteUser: vscode` | Run as non-root user | Works normally | COMPATIBLE | inferred (standard container behavior) |
| `containerUser: root` | Run as container root | Works; root has default Docker capabilities within userns | COMPATIBLE | [doc-link: security.md#process-capabilities](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#process-capabilities) |
| `updateRemoteUserUID: true` | Match host UID | ID-mapped mounts handle this (kernel >= 5.12) or shiftfs (Ubuntu) | CONDITIONAL | [doc-link: design.md#id-mapped-mounts](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/design.md#id-mapped-mounts--v050-) |
| UID 0 in container | Maps to host root | Maps to unprivileged user (e.g., 165536) | COMPATIBLE | [doc-link: security.md#user-namespace-id-mapping](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#user-namespace-id-mapping) |

**How ID-mapping works:**

Sysbox uses ID-mapped mounts (kernel >= 5.12) or shiftfs (Ubuntu/Debian) to ensure host files mounted into containers show correct ownership. Per [design.md#id-mapped-mounts](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/design.md#id-mapped-mounts--v050-):
- Host file owned by UID 1000 appears as UID 1000 inside container
- Without ID-mapping or shiftfs, files show as `nobody:nogroup`

**Kernel requirements:**
- Kernel < 5.12: Requires shiftfs module
- Kernel 5.12-5.18: ID-mapped mounts work, shiftfs recommended for edge cases
- Kernel >= 5.19: Full ID-mapped mount support, shiftfs not required

**ContainAI-specific consideration:**
- ContainAI uses `agent` user (UID 1000) with systemd
- Devcontainer's `remoteUser` typically expects `vscode` (UID 1000)
- Compatible by default since UIDs match; username difference is cosmetic

---

### Pattern 4: Volume Mounts

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| Named volume at /var/lib/docker | Persist inner images | Supported; one container at a time | COMPATIBLE | [doc-link: dind.md#persistence-of-inner-docker-images](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#persistence-of-inner-docker-images) |
| Host bind mount at /var/lib/docker | Same path from host | Blocked if it's the host's Docker data | BLOCKED | [doc-link: dind.md#persistence-of-inner-docker-images](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#persistence-of-inner-docker-images) (caveat 2) |
| Named volumes (general) | Persistence | Fully supported | COMPATIBLE | [doc-link: storage.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/storage.md) |
| Read-only host bind mounts | Source code access | Supported with ID-mapping (kernel >= 5.12) | CONDITIONAL | [doc-link: storage.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/storage.md) |
| Mount to /proc, /sys submounts | Override kernel views | Blocked - immutable mounts | BLOCKED | [doc-link: security.md#initial-mount-immutability](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#initial-mount-immutability--v030-) |
| Docker socket mount | Host Docker access | Technically works but defeats isolation | WARN | inferred (standard Docker bind mount) |

**Clarification on /var/lib/docker mounts:**

Per [dind.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#persistence-of-inner-docker-images):
1. You CAN mount a named volume or a host directory TO the container's `/var/lib/docker` for persistence
2. You CANNOT mount the HOST's `/var/lib/docker` (this would expose sibling containers)
3. A given volume/directory can only be mounted to ONE container's `/var/lib/docker` at a time

**Docker socket mount:**
- Technically works in Sysbox (it's a standard bind mount)
- Completely defeats ContainAI's isolation model
- ContainAI should BLOCK this pattern regardless of Sysbox support

---

### Pattern 5: User Namespace/UID Mapping

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| Container root = host root | Traditional Docker model | Never - root always maps to unprivileged | DIFFERENT | [doc-link: security.md#user-namespace](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#user-namespace) |
| UID range in container | 0-65535 typical | Full range available (64K UIDs per container) | COMPATIBLE | [doc-link: security.md#exclusive-userns-id-mapping-allocation](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#exclusive-userns-id-mapping-allocation) |
| Write to mounted host files | Needs matching UID | ID-mapped mounts solve this (kernel >= 5.12) | CONDITIONAL | [doc-link: design.md#id-mapped-mounts](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/design.md#id-mapped-mounts--v050-) |
| `updateRemoteUserUID` | Sync container UID to host | Unnecessary with ID-mapping | N/A | inferred |

**Sysbox-CE vs Sysbox-EE:**

Per [security.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#common-vs-exclusive-userns-id-mappings):
- Sysbox-CE (Community Edition): Common UID mapping for all containers (e.g., all map 0 -> 165536)
- Sysbox-EE (Enterprise Edition): Exclusive UID mapping per container (stronger isolation)

**ContainAI uses Sysbox-CE** (open source version), so all containers share the same host UID range.

---

### Pattern 6: Kernel Sysctls

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| `--sysctl` in runArgs | Modify kernel parameters | Depends on namespace scope | PARTIAL | inferred from Linux namespace semantics |
| Net sysctls (net.*) | Network tuning | Allowed (network namespace is isolated) | COMPATIBLE | inferred |
| Kernel sysctls (kernel.*) | Kernel behavior | Blocked (not namespaced by Linux) | BLOCKED | inferred |
| IPC sysctls | Shared memory limits | Allowed (IPC namespace is isolated) | COMPATIBLE | inferred |

**Note:** Sysctl behavior is inferred from standard Linux namespace semantics. Sysbox does not modify sysctl handling beyond what user namespace provides. Network sysctls (net.*) are per-network-namespace, so they work. Kernel-wide sysctls (kernel.*) are not namespaced by Linux and would fail.

**From usage analysis:** Only 1 repo (cilium/cilium) uses `--sysctl`, for network-related parameters (`net.ipv4.*`). These should work in Sysbox.

---

### Pattern 7: Capabilities (capAdd)

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| `capAdd: [SYS_PTRACE]` | Debugger support | Granted within user namespace | COMPATIBLE | [doc-link: security.md#process-capabilities](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#process-capabilities) |
| `capAdd: [NET_ADMIN]` | Network configuration | Granted within user namespace | COMPATIBLE | [doc-link: security.md#process-capabilities](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#process-capabilities) |
| Default capabilities | Docker's default set | By default, Sysbox grants all capabilities to root process | ENHANCED | [doc-link: security.md#process-capabilities](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#process-capabilities) |
| `--cap-add` in runArgs | Same as capAdd | Same behavior | COMPATIBLE | inferred |

**Sysbox capability behavior:**

Per [security.md#process-capabilities](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#process-capabilities):

> By default, a system container's init process configured with user-ID 0 (root) always starts with all capabilities enabled.

This differs from regular Docker containers which have a restricted default capability set. However:
- All capabilities are scoped to the container's user namespace
- They cannot affect host resources outside the container
- This behavior can be changed with `SYSBOX_HONOR_CAPS=TRUE` environment variable

**This is a key advantage:** Devcontainers often add capabilities for debugging (SYS_PTRACE) or network testing (NET_ADMIN). With Sysbox, these are granted by default to root processes, safely contained by the user namespace.

---

### Pattern 8: Lifecycle Commands

| Command | Execution Context | Sysbox Impact | Result | Evidence |
|---------|-------------------|---------------|--------|----------|
| `initializeCommand` | HOST machine | N/A - blocked by ContainAI policy | BLOCKED | N/A (policy decision) |
| `onCreateCommand` | Inside container | No impact | COMPATIBLE | inferred |
| `postCreateCommand` | Inside container | No impact | COMPATIBLE | inferred |
| `postStartCommand` | Inside container | No impact | COMPATIBLE | inferred |
| `postAttachCommand` | Inside container | No impact | COMPATIBLE | inferred |
| `updateContentCommand` | Inside container | No impact | COMPATIBLE | inferred |

**Note:** `initializeCommand` is blocked by ContainAI policy, not Sysbox limitation. It runs on the host BEFORE container creation, which is a security risk for sandboxed environments.

All other lifecycle commands run inside the container and are unaffected by Sysbox - they execute normally within the container's environment.

---

### Pattern 9: overrideCommand

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| `overrideCommand: true` | Replace container entrypoint | Works | COMPATIBLE | inferred |
| `overrideCommand: false` | Keep container entrypoint | Works | COMPATIBLE | inferred |
| Systemd as entrypoint | PID 1 = /sbin/init | Fully supported by Sysbox | COMPATIBLE | [doc-link: systemd.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/systemd.md) |

**ContainAI consideration:**
- ContainAI expects systemd as PID 1 for SSH/services
- If devcontainer overrides entrypoint, systemd won't run
- This is a ContainAI model conflict, not a Sysbox limitation

---

### Pattern 10: Port Forwarding

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| `forwardPorts: [3000]` | Expose container ports | Works normally | COMPATIBLE | inferred (standard Docker) |
| `portsAttributes` | Port metadata | Passthrough (IDE feature, not runtime) | COMPATIBLE | inferred |
| SSH on port 22 | Remote access | Works; ContainAI maps to 2300-2500 | COMPATIBLE | inferred |

**Note:** Port forwarding is standard Docker functionality. Sysbox does not modify port handling.

---

### Pattern 11: Security Options

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| `--security-opt seccomp=...` | Custom seccomp profile | Not honored - Sysbox uses its own profile | IGNORED | [doc-link: security.md#system-calls](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#system-calls) |
| `--security-opt apparmor=...` | Custom AppArmor profile | Not honored - Sysbox ignores AppArmor | IGNORED | [doc-link: security.md#apparmor](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#apparmor) |
| `--security-opt label=disable` | Disable SELinux | N/A - SELinux not supported | N/A | [doc-link: security.md#selinux](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#selinux) |

**Sysbox seccomp profile:**

Per [security.md#system-calls](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md#system-calls), Sysbox allows 300+ syscalls including ones Docker blocks:
- mount, umount2
- add_key, request_key, keyctl
- pivot_root
- sethostname
- setns, unshare

Custom seccomp profiles are not supported - Sysbox's profile is required for system container functionality.

---

### Pattern 12: Features Installation

| Aspect | Expectation | Sysbox Behavior | Result | Evidence |
|--------|-------------|-----------------|--------|----------|
| Feature install.sh execution | Runs as root during build | Works normally | COMPATIBLE | inferred |
| docker-in-docker feature | Requires DinD capability | Native support | COMPATIBLE | [doc-link: dind.md](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md) |
| docker-outside-of-docker | Mounts host socket | Works but insecure | WARN | inferred |
| Other features | Various installations | Generally compatible | COMPATIBLE | inferred |

**Security consideration:** Features run arbitrary code during image build. This is a supply chain risk regardless of runtime. ContainAI should implement feature allowlisting.

---

## Summary Compatibility Table

Usage frequencies from [usage-analysis.md](usage-analysis.md):

| Pattern | Usage Frequency | Sysbox Compatibility | ContainAI Action |
|---------|----------------|---------------------|------------------|
| Docker-in-Docker | 22% | EXCELLENT | Native support |
| Basic image + commands | 64% | FULL | Pass through |
| Custom user (remoteUser) | 36% | FULL | Map to agent user |
| Privileged mode | 14% | MITIGATED | Warn (DinD works without it) |
| Volume mounts | 18% | GOOD | Filter host /var/lib/docker |
| runArgs capabilities | 8% | ENHANCED | Allow (contained by userns) |
| Lifecycle commands | 64% | FULL | Block initializeCommand only |
| Features | 68% | GOOD | Allowlist recommended |
| Docker socket mount | ~6% | WORKS | Block (defeats isolation) |
| Kernel sysctls | 2% | PARTIAL | Allow net.*, block kernel.* |

---

## Workarounds for Incompatible Patterns

### 1. True Privileged Mode Requirement

**Symptoms:** Application needs raw host device access, kernel module loading, or host namespace access.

**Workaround:** None within Sysbox. These use cases are fundamentally incompatible with ContainAI's security model.

**Alternative:** Run in VM instead of container, or use outside of ContainAI.

---

### 2. Docker Socket Access

**Symptoms:** Devcontainer mounts `/var/run/docker.sock` for host Docker access.

**Workaround:** Use Sysbox's native DinD instead. The inner Docker daemon is isolated but fully functional.

**Migration path:**
1. Remove docker.sock mount
2. Add `docker-in-docker` feature OR
3. Rely on ContainAI's pre-installed Docker in system container

---

### 3. Custom /var/lib/docker Location

**Symptoms:** Devcontainer configures inner Docker to use non-standard data-root.

**Workaround:** None - Sysbox requires inner Docker at `/var/lib/docker` per [dind.md#inner-docker-data-root](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#inner-docker-data-root).

**Migration path:** Modify devcontainer to use default Docker data location.

---

### 4. Multi-Architecture Builds

**Symptoms:** Need `docker buildx` for ARM64 on AMD64 host (or vice versa).

**Workaround (kernel < 6.7):** Configure QEMU binfmt on the HOST before launching container.

**Workaround (kernel >= 6.7):** Works natively - Sysbox provides namespaced binfmt_misc per [dind.md#inner-docker-multi-arch-builds](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#inner-docker-multi-arch-builds--v067-).

---

### 5. Non-Root Container User + File Permissions

**Symptoms:** Files mounted from host show as nobody:nogroup inside container.

**Workaround:** Ensure kernel >= 5.12 for ID-mapped mounts, or install shiftfs on Ubuntu/Debian per [design.md#shiftfs-module](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/design.md#shiftfs-module).

**Verification:**
```bash
# Inside container
mount | grep idmapped   # Should show idmapped mounts
```

---

### 6. Systemd Entrypoint Override

**Symptoms:** Devcontainer sets `overrideCommand: true` which prevents systemd from running.

**Workaround:** This is a ContainAI model conflict. Options:
1. Modify devcontainer to keep systemd as entrypoint
2. Run devcontainer inside the Sysbox system container (nested)
3. Skip devcontainer and use base ContainAI image

---

## Kernel Version Requirements

Per Sysbox documentation:

| Feature | Minimum Kernel | Evidence |
|---------|---------------|----------|
| Basic Sysbox | Linux 5.0+ | inferred (from supported distros in install docs) |
| ID-mapped mounts | 5.12+ | [doc-link: design.md#id-mapped-mounts](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/design.md#id-mapped-mounts--v050-) |
| Full ID-mapped mount support | 5.19+ | [doc-link: design.md#shiftfs-module](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/design.md#shiftfs-module) ("as of kernel 5.19+, ID-mapped mounts provide an almost full replacement for shiftfs") |
| Namespaced binfmt_misc | 6.7+ | [doc-link: dind.md#inner-docker-multi-arch-builds](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md#inner-docker-multi-arch-builds--v067-) |

**ContainAI deployment note:** Target kernel 5.19+ for best compatibility with devcontainer patterns.

---

## References

- [Sysbox User Guide - Concepts](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/concepts.md)
- [Sysbox User Guide - Design](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/design.md)
- [Sysbox User Guide - Docker-in-Docker](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md)
- [Sysbox User Guide - Security](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md)
- [Sysbox User Guide - Systemd](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/systemd.md)
- [Sysbox User Guide - Storage](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/storage.md)
- [Sysbox User Guide - Configuration](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/configuration.md)
- [ContainAI fn-10-vep Epic Spec](.flow/specs/fn-10-vep.md)
- [Devcontainer Usage Analysis](usage-analysis.md)
