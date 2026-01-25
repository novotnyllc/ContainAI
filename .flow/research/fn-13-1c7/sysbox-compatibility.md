# Sysbox Compatibility with Devcontainer Patterns

Analysis of which devcontainer patterns are compatible with Sysbox runtime (ContainAI's security foundation) and which require workarounds or break entirely.

## Executive Summary

Sysbox provides strong compatibility with most devcontainer patterns. Its key strength - secure Docker-in-Docker without `--privileged` - directly addresses the most common "dangerous" devcontainer requirement. The primary incompatibilities are:

1. **Full compatibility (no changes needed):** ~78% of patterns
2. **Compatible with Sysbox advantages:** ~12% (DinD patterns work better)
3. **Requires workarounds:** ~7% (user remapping, mount adjustments)
4. **Incompatible/blocked:** ~3% (host socket access, raw privileged)

---

## Sysbox Capability Overview

### What Sysbox Virtualizes

| Capability | Sysbox Behavior | Evidence Type |
|-----------|----------------|---------------|
| **User namespace** | Always enabled; root in container = unprivileged on host | doc-link |
| **Cgroup namespace** | Always enabled | doc-link |
| **/proc virtualization** | Partial virtualization via sysbox-fs FUSE daemon | doc-link |
| **/sys virtualization** | Partial virtualization; `/sys/fs/cgroup` is read-write | doc-link |
| **Mount syscall** | Allowed (unlike regular containers) with restrictions | doc-link |
| **Nested containers** | Fully supported via DinD/KinD | doc-link |
| **Systemd as PID 1** | Fully supported | doc-link |
| **Privileged inner containers** | Allowed but contained within outer namespace | doc-link |

**Source:** [Sysbox User Guide - Security](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md)

### What Sysbox Blocks or Restricts

| Capability | Restriction | Reason | Evidence Type |
|-----------|-------------|--------|---------------|
| **AppArmor profiles** | Ignored | Too restrictive for system containers | doc-link |
| **SELinux** | Not supported | Technical limitation | doc-link |
| **Host device access** | Not supported (--device flag) | Security isolation | doc-link |
| **Read-only mount remount to RW** | Blocked for immutable mounts | Prevent isolation escape | doc-link |
| **Host /var/lib/docker mount** | Blocked | Would expose sibling containers | doc-link |
| **userns-remap on inner Docker** | Not supported | Technical limitation, planned | doc-link |
| **Inner Docker data-root override** | Not supported | Must be /var/lib/docker | doc-link |

**Source:** [Sysbox User Guide - DinD](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/dind.md), [Security](https://github.com/nestybox/sysbox/blob/master/docs/user-guide/security.md)

---

## Compatibility Matrix

### Pattern 1: Docker-in-Docker Feature

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| `docker-in-docker:2` feature | Requires DinD support | Native support without --privileged | COMPATIBLE |
| Inner Docker daemon | Works normally | Works; defaults to runc (not sysbox) | COMPATIBLE |
| Nested container builds | `docker build` inside | Works correctly | COMPATIBLE |
| Multi-arch builds | `docker buildx` | Requires kernel 6.7+ for binfmt_misc | PARTIAL |
| Inner privileged containers | `docker run --privileged` | Allowed but contained in outer userns | COMPATIBLE |

**Evidence Type:** doc-link + inferred from ContainAI fn-10-vep architecture

**Key Finding:** Sysbox's primary design goal is secure DinD. This is ContainAI's strongest compatibility point - 22% of repos use docker-in-docker feature.

**Workaround for multi-arch:** On kernel < 6.7, binfmt_misc is not namespaced. Multi-arch builds require host-level QEMU setup.

---

### Pattern 2: `--privileged` Requests

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| `privileged: true` property | Full host capabilities | Ignored - Sysbox always uses user namespace | BLOCKED/IGNORED |
| `--privileged` in runArgs | Same as above | Same as above | BLOCKED/IGNORED |
| Why privileged is requested | Usually for DinD | Sysbox provides DinD without privileged | MITIGATED |

**Evidence Type:** doc-link

**Actual behavior when privileged is requested:**

Sysbox containers CANNOT be created with `--privileged` flag through Docker. If you try:
```bash
docker run --runtime=sysbox-runc --privileged ...
```
The container will be created but WITHOUT actual privileged access - Sysbox enforces user namespace isolation regardless.

**Important:** The devcontainer `privileged: true` property is handled at container creation time by the devcontainer CLI, which translates it to Docker's `--privileged` flag. When Sysbox is the runtime, this flag is effectively neutered.

**Workaround:** For most use cases (DinD), no workaround needed - Sysbox provides the capability without the flag. For true privileged use cases (kernel module loading, raw device access), Sysbox is not suitable.

---

### Pattern 3: Custom User Configurations

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| `remoteUser: vscode` | Run as non-root user | Works normally | COMPATIBLE |
| `containerUser: root` | Run as container root | Works; root has full caps in container | COMPATIBLE |
| `updateRemoteUserUID: true` | Match host UID | ID-mapped mounts handle this transparently | COMPATIBLE |
| UID 0 in container | Maps to host root | Maps to unprivileged user (e.g., 165536) | COMPATIBLE |

**Evidence Type:** doc-link

**How ID-mapping works (kernel >= 5.12):**

Sysbox uses ID-mapped mounts to ensure host files mounted into containers show correct ownership. Example:
- Host file owned by UID 1000
- Container user namespace maps 0 -> 165536
- ID-mapped mount translates: host UID 1000 appears as UID 1000 inside container

**ContainAI-specific consideration:**
- ContainAI uses `agent` user (UID 1000) with systemd
- Devcontainer's `remoteUser` typically expects `vscode` (UID 1000)
- Compatible by default since UIDs match; username difference is cosmetic

---

### Pattern 4: Volume Mounts to Protected Paths

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| Bind mount to /var/lib/docker | Persist inner images | Supported with restrictions | PARTIAL |
| Named volumes | General persistence | Fully supported | COMPATIBLE |
| Read-only host mounts | Source code access | Fully supported with ID-mapping | COMPATIBLE |
| Mount to /proc, /sys submounts | Override kernel views | Blocked - immutable mounts | BLOCKED |
| Docker socket mount | Host Docker access | Works but defeats isolation | WARN |

**Evidence Type:** doc-link

**Restrictions on /var/lib/docker mount:**
1. Can only mount to ONE container at a time (Docker daemon restriction)
2. Cannot mount host's /var/lib/docker (would expose sibling containers)
3. Sysbox creates implicit mounts for `/var/lib/docker`, `/var/lib/kubelet`, `/var/lib/containerd`

**Docker socket mount behavior:**
- Technically works in Sysbox
- Completely defeats the isolation model
- ContainAI should BLOCK this pattern regardless of Sysbox support

---

### Pattern 5: User Namespace/UID Mapping

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| Container root = host root | Traditional Docker model | NEVER - root maps to unprivileged | DIFFERENT |
| UID range in container | 0-65535 typical | Full range available | COMPATIBLE |
| Write to mounted host files | Needs matching UID | ID-mapped mounts solve this | COMPATIBLE |
| `updateRemoteUserUID` | Sync container UID to host | Unnecessary with ID-mapping | N/A |

**Evidence Type:** doc-link

**Sysbox-CE vs Sysbox-EE:**
- Sysbox-CE: Common UID mapping for all containers (e.g., all map 0 -> 165536)
- Sysbox-EE: Exclusive UID mapping per container (stronger isolation)

**ContainAI uses Sysbox-CE** (open source version), so all containers share the same host UID range.

---

### Pattern 6: Kernel Sysctls

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| `--sysctl` in runArgs | Modify kernel parameters | Most blocked; namespaced ones allowed | PARTIAL |
| Net sysctls (net.*) | Network tuning | Allowed (network namespace) | COMPATIBLE |
| Kernel sysctls (kernel.*) | Kernel behavior | Blocked (not namespaced) | BLOCKED |
| IPC sysctls | Shared memory limits | Allowed (IPC namespace) | COMPATIBLE |

**Evidence Type:** inferred from userns/sysctl interaction

**From usage analysis:** Only 1 repo (cilium/cilium) uses `--sysctl`, for network-related parameters. Network sysctls are namespaced and should work in Sysbox.

---

### Pattern 7: Capabilities (capAdd)

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| `capAdd: [SYS_PTRACE]` | Debugger support | Granted within user namespace | COMPATIBLE |
| `capAdd: [NET_ADMIN]` | Network configuration | Granted within user namespace | COMPATIBLE |
| Any capability | Additional powers | All granted to root by default | COMPATIBLE |
| `--cap-add` in runArgs | Same as capAdd | Same behavior | COMPATIBLE |

**Evidence Type:** doc-link

**Sysbox default behavior:**
- Root process in container gets ALL capabilities
- But capabilities are scoped to container's user namespace
- Cannot affect host resources outside container

**This is a key advantage:** Devcontainers often add capabilities for debugging (SYS_PTRACE) or network testing (NET_ADMIN). Sysbox grants these safely.

---

### Pattern 8: Lifecycle Commands

| Command | Execution Context | Sysbox Impact | Result |
|---------|-------------------|---------------|--------|
| `initializeCommand` | HOST machine | N/A - blocked by ContainAI policy | BLOCKED |
| `onCreateCommand` | Inside container | No impact | COMPATIBLE |
| `postCreateCommand` | Inside container | No impact | COMPATIBLE |
| `postStartCommand` | Inside container | No impact | COMPATIBLE |
| `postAttachCommand` | Inside container | No impact | COMPATIBLE |
| `updateContentCommand` | Inside container | No impact | COMPATIBLE |

**Evidence Type:** inferred (Sysbox doesn't affect container-internal execution)

**Note:** `initializeCommand` is blocked by ContainAI policy, not Sysbox limitation. It runs on host BEFORE container creation.

---

### Pattern 9: overrideCommand

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| `overrideCommand: true` | Replace container entrypoint | Works | COMPATIBLE |
| `overrideCommand: false` | Keep container entrypoint | Works | COMPATIBLE |
| Systemd as entrypoint | PID 1 = /sbin/init | Fully supported | COMPATIBLE |

**Evidence Type:** doc-link

**ContainAI consideration:**
- ContainAI expects systemd as PID 1 for SSH/services
- If devcontainer overrides entrypoint, systemd won't run
- This is a ContainAI model conflict, not Sysbox limitation

---

### Pattern 10: Port Forwarding

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| `forwardPorts: [3000]` | Expose container ports | Works normally | COMPATIBLE |
| `portsAttributes` | Port metadata | Passthrough (not runtime) | COMPATIBLE |
| SSH on port 22 | Remote access | Works; ContainAI maps to 2300-2500 | COMPATIBLE |

**Evidence Type:** inferred (port forwarding is standard Docker, Sysbox doesn't modify)

---

### Pattern 11: Security Options

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| `--security-opt seccomp=...` | Custom seccomp profile | Ignored - Sysbox uses own profile | IGNORED |
| `--security-opt apparmor=...` | Custom AppArmor profile | Ignored - Sysbox skips AppArmor | IGNORED |
| `--security-opt label=disable` | Disable SELinux | N/A - SELinux not supported | N/A |

**Evidence Type:** doc-link

**Sysbox seccomp additions:**
Allows syscalls that regular containers block:
- mount, umount2
- add_key, request_key, keyctl
- pivot_root
- sethostname
- setns, unshare

---

### Pattern 12: Features Installation

| Aspect | Expectation | Sysbox Behavior | Result |
|--------|-------------|-----------------|--------|
| Feature install.sh execution | Runs as root during build | Works normally | COMPATIBLE |
| docker-in-docker feature | Requires DinD capability | Native support | COMPATIBLE |
| docker-outside-of-docker | Mounts host socket | Works but insecure | WARN |
| Other features | Various installations | Generally compatible | COMPATIBLE |

**Evidence Type:** inferred

**Security consideration:** Features run arbitrary code during image build. This is a supply chain risk regardless of runtime. ContainAI should implement feature allowlisting.

---

## Summary Compatibility Table

| Pattern | Usage Frequency | Sysbox Compatibility | ContainAI Action |
|---------|----------------|---------------------|------------------|
| Docker-in-Docker | 22% | EXCELLENT | Native support |
| Basic image + commands | 64% | FULL | Pass through |
| Custom user (remoteUser) | 36% | FULL | Map to agent user |
| Privileged mode | 6% | BLOCKED | Warn/block (DinD works without it) |
| Volume mounts | 18% | GOOD | Filter dangerous mounts |
| runArgs capabilities | 8% | GOOD | Allow (contained by userns) |
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

**Workaround:** None - Sysbox requires inner Docker at `/var/lib/docker`.

**Migration path:** Modify devcontainer to use default Docker data location.

---

### 4. Multi-Architecture Builds

**Symptoms:** Need `docker buildx` for ARM64 on AMD64 host (or vice versa).

**Workaround (kernel < 6.7):** Configure QEMU binfmt on the HOST before launching container.

**Workaround (kernel >= 6.7):** Works natively - Sysbox provides namespaced binfmt_misc.

---

### 5. Non-Root Container User + File Permissions

**Symptoms:** Files mounted from host show as nobody:nogroup inside container.

**Workaround:** Ensure kernel >= 5.12 for ID-mapped mounts, or install shiftfs on Ubuntu/Debian.

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

| Feature | Minimum Kernel | Recommendation |
|---------|---------------|----------------|
| Basic Sysbox | 5.0+ | Required |
| ID-mapped mounts | 5.12+ | Strongly recommended |
| Full ID-mapped mount support | 5.19+ | Preferred |
| Namespaced binfmt_misc | 6.7+ | For multi-arch builds |

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
- [Devcontainer Usage Analysis](.flow/research/fn-13-1c7/usage-analysis.md)
