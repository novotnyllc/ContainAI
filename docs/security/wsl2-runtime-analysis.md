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

## 4. Proposed Mitigation: Userspace Instrumentation

To bridge this gap before shipping, we are implementing a userspace fallback mechanism.

### 4.1 Architecture: The "Audit Shim"

Instead of relying on the kernel to notify us of syscalls, we will inject a monitoring library into the agent process.

*   **Mechanism**: `LD_PRELOAD` injection of a Rust-based shared library (`libauditshim.so`).
*   **Scope**: Intercepts `execve`, `connect`, `open`, and `openat` in userspace.
*   **Output**: Streams structured JSON events to the secure audit socket (`/run/containai/audit.sock`).

### 4.2 Security Properties

*   **Visibility**: Restores the "Audit Trail" capability. We can see what the agent is doing.
*   **Robustness**: While userspace hooks are theoretically bypassable by a hostile binary (unlike kernel hooks), they provide sufficient visibility for the threat model of a "cooperative but untrusted" AI agent.
*   **Consistency**: This shim will be available on **all** platforms, providing a unified logging format, while Seccomp provides the hard enforcement backstop on supported Linux kernels.

## 5. Roadmap

1.  **Develop `audit-shim`**: Rust `cdylib` implementation.
2.  **Update Launcher**: Detect `EBUSY` on seccomp load, suppress the warning (to avoid user alarm), and inject `LD_PRELOAD`.
3.  **Verify**: Confirm that `execve` events appear in the audit log on WSL2 despite the missing kernel feature.
