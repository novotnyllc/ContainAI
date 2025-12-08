# WSL2 Runtime Security Analysis

**Status:** Analysis of Pre-Release Limitations
**Date:** December 1, 2025

## 1. Overview

This document details the technical limitations encountered when porting the ContainAI agent runtime to Windows Subsystem for Linux 2 (WSL2). It analyzes the gap between our security requirements and the current WSL2 kernel capabilities, specifically regarding syscall interception.

## 2. Technical Limitations

### 2.1 Missing Kernel Support (`CONFIG_SECCOMP_USER_NOTIFICATION`)

The ContainAI `agent-task-runner` architecture relies on the `seccomp` user notification mechanism (`SCMP_ACT_NOTIFY`) to intercept `execve` and `execveat` syscalls. This allows the supervisor daemon to pause a process, inspect its memory (arguments, environment), and make a policy decision before the kernel executes the binary.

**Finding:** The standard Microsoft Linux kernel provided with WSL2 is compiled without `CONFIG_SECCOMP_USER_NOTIFICATION`.

**Impact:**
- Calls to `seccomp_load` with a notification listener fail immediately.
- On some versions, this returns `EINVAL` (invalid argument).
- On others, it returns `EBUSY` due to conflicts with existing filters.

### 2.2 WSL2 PID 1 Seccomp Filters

In addition to the missing kernel configuration, WSL2's `init` process (PID 1) installs its own restrictive seccomp filters during boot.

**Upstream Issue:** This behavior is tracked in the WSL repository (e.g., [microsoft/WSL#9783](https://github.com/microsoft/WSL/issues/9783) regarding systemd and seccomp interactions). The pre-existing filters can prevent nested container runtimes from installing their own interceptors, resulting in the `EBUSY` error code we observed during testing.

## 3. Security Impact Analysis

The inability to use `SCMP_ACT_NOTIFY` on WSL2 creates a specific gap in our defense-in-depth model:

| Feature | Standard Linux | WSL2 (Current) | Impact |
| :--- | :--- | :--- | :--- |
| **Syscall Interception** | ✅ Active | ❌ Unavailable | We cannot block specific binary executions at the kernel level. |
| **Audit Trail** | ✅ Kernel-verified | ⚠️ Missing | We lose the guarantee that *every* exec is logged by the supervisor. |
| **Static Sandboxing** | ✅ Active | ✅ Active | `seccomp-containai-agent.json` still blocks dangerous syscalls (`ptrace`, `mount`). |
| **Network Isolation** | ✅ Active | ✅ Active | Squid proxy enforcement remains effective. |

**Conclusion:** While the container remains isolated from the host, we lack the granular observability required to audit agent behavior fully.

## 4. Proposed Mitigation: Defense-in-Depth

To bridge this gap, we employ a multi-layered strategy that combines userspace instrumentation with platform-native controls available on WSL2.

### 4.1 Userspace Instrumentation (Audit Shim)

*   **Mechanism**: Global injection of a Rust-based shared library (`libauditshim.so`) via `/etc/ld.so.preload`.
*   **Scope**: Intercepts `execve`, `connect`, `open`, and `openat` in userspace.
*   **Function**: Streams structured JSON events to the secure audit socket (`/run/containai/audit.sock`) and can synchronously block actions based on daemon policy.
*   **Limitation**: As a userspace control, it can be bypassed by **static binaries** (which do not use the dynamic linker). However, unlike environment-variable based injection, it cannot be bypassed by unsetting `LD_PRELOAD`.

### 4.2 AppArmor & Mount Restrictions (The Shield)

To mitigate the risk of the agent running malicious code:
*   **NoExec Mounts**: Writable system directories (`/tmp`, `/dev/shm`) are mounted with the `noexec` flag.
*   **AppArmor**: We utilize WSL2's support for AppArmor to enforce file access control. This is the primary security boundary on WSL2. It prevents any process (shimmed or custom) from modifying protected system files or reading secrets directly.

### 4.3 Security Properties Summary

| Feature | Linux (Seccomp) | WSL2 (AppArmor Only) |
| :--- | :--- | :--- |
| **Interception** | Kernel-level (Unavoidable) | None (Audit-only via `LD_PRELOAD`) |
| **New Binaries** | Blocked by Seccomp (syscalls) | Allowed in `/workspace` (Gap), Blocked in `/tmp` |
| **File Protection** | AppArmor + Read-Only Root | AppArmor + Read-Only Root |
| **Robustness** | High | Medium (Relies entirely on AppArmor containment) |

**Conclusion**: On WSL2, we accept a "Containment" strategy rather than "Interception". We cannot prevent the execution of malicious binaries, but we restrict their access to the system and network.

## 5. Roadmap

1.  **Develop `audit-shim`**: Rust `cdylib` implementation.
2.  **Update Launcher**: Detect `EBUSY` on seccomp load, suppress the warning (to avoid user alarm), and inject `LD_PRELOAD`.
3.  **Verify**: Confirm that `execve` events appear in the audit log on WSL2 despite the missing kernel feature.
