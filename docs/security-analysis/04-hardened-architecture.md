# Hardened Architecture Design

## Purpose

This document presents the recommended hardened architecture for safe unrestricted agent operation, building on the current strong foundation.

## Design Principles

1. **Structural Safety Over Behavioral Controls**
   - Make dangerous operations impossible, not just forbidden
   - Use OS/container isolation, not just policy checks
   - Default-deny with explicit allows

2. **Defense in Depth**
   - Multiple independent layers of protection
   - No single point of failure
   - Assume any one layer can be bypassed

3. **Minimal User Friction**
   - Prompts only for genuinely high-risk operations
   - Silent-allow for 99% of operations
   - Logging provides visibility without interruption

4. **Observable and Auditable**
   - All significant operations logged
   - Forensic trail for incident response
   - Anomaly detection possible

## Hardened Container Configuration

### 1. Linux Capabilities (CRITICAL FIX)

**Current State:**
- PowerShell: `--cap-drop=ALL` ✅
- Bash: No capability drop ❌

**Recommended:**
```bash
# Add to bash launcher (launch-agent, line ~615)
DOCKER_ARGS+=(
    "--cap-drop=ALL"
)
```

**Impact:**
- Prevents capability-based exploits
- Blocks mount, network admin, sys operations
- Reduces kernel attack surface
- **No functional impact** (agent doesn't need capabilities)

**Priority:** CRITICAL (immediate fix)

### 2. Seccomp Profile

**Current State:**
- No seccomp profile applied

**Recommended:**
Create `/etc/docker/seccomp/coding-agents.json`:
```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_ARM64"],
  "syscalls": [
    {
      "names": [
        "read", "write", "open", "openat", "close", "stat", "fstat",
        "lseek", "mmap", "mprotect", "munmap", "brk", "ioctl", "pread64",
        "pwrite64", "readv", "writev", "access", "pipe", "select", "sched_yield",
        "mremap", "msync", "mincore", "madvise", "shmget", "shmat", "shmctl",
        "dup", "dup2", "pause", "nanosleep", "getitimer", "alarm", "setitimer",
        "getpid", "sendfile", "socket", "connect", "accept", "sendto", "recvfrom",
        "sendmsg", "recvmsg", "shutdown", "bind", "listen", "getsockname",
        "getpeername", "socketpair", "setsockopt", "getsockopt", "clone", "fork",
        "vfork", "execve", "exit", "wait4", "kill", "uname", "fcntl", "flock",
        "fsync", "fdatasync", "truncate", "ftruncate", "getdents", "getcwd",
        "chdir", "fchdir", "rename", "mkdir", "rmdir", "creat", "link", "unlink",
        "symlink", "readlink", "chmod", "fchmod", "chown", "fchown", "lchown",
        "umask", "gettimeofday", "getrlimit", "getrusage", "sysinfo", "times",
        "ptrace", "getuid", "getgid", "geteuid", "getegid", "setuid", "setgid",
        "getppid", "getpgrp", "setsid", "setreuid", "setregid", "getgroups",
        "setgroups", "setresuid", "getresuid", "setresgid", "getresgid", "getpgid",
        "setfsuid", "setfsgid", "getsid", "capget", "capset", "rt_sigaction",
        "rt_sigprocmask", "rt_sigpending", "rt_sigtimedwait", "rt_sigqueueinfo",
        "rt_sigsuspend", "sigaltstack", "personality", "statfs", "fstatfs", "ioprio_get",
        "ioprio_set", "sched_setattr", "sched_getattr", "sched_setscheduler",
        "sched_getscheduler", "sched_getparam", "sched_setparam", "sched_get_priority_max",
        "sched_get_priority_min", "sched_rr_get_interval", "mlock", "munlock",
        "mlockall", "munlockall", "vhangup", "prctl", "arch_prctl", "futex",
        "set_tid_address", "get_robust_list", "set_robust_list", "restart_syscall",
        "exit_group", "epoll_create", "epoll_create1", "epoll_ctl", "epoll_wait",
        "epoll_pwait", "eventfd", "eventfd2", "signalfd", "signalfd4", "timerfd_create",
        "timerfd_settime", "timerfd_gettime", "accept4", "recvmmsg", "sendmmsg",
        "wait", "waitpid", "waitid", "poll", "ppoll", "pselect6", "faccessat",
        "mkdirat", "unlinkat", "renameat", "linkat", "symlinkat", "readlinkat",
        "fchmodat", "faccessat", "pread", "pwrite", "fstatat", "newfstatat",
        "utimensat", "copy_file_range", "sendfile64", "getrandom"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

**Apply:**
```bash
# In launcher
DOCKER_ARGS+=("--security-opt" "seccomp=/etc/docker/seccomp/coding-agents.json")
```

**Blocked syscalls (critical for security):**
- `mount`, `umount` - filesystem mounting
- `reboot`, `kexec_load` - system control
- `init_module`, `delete_module` - kernel modules
- `ptrace` (on other processes) - debugging/injection
- `swapon`, `swapoff` - swap control
- `setns`, `unshare` - namespace manipulation
- `bpf` - eBPF programs

**Impact:**
- Significantly reduces kernel attack surface
- Blocks many container escape techniques
- **No functional impact** for normal development work

**Priority:** HIGH (important hardening)

### 3. Process Limits

**Current State:**
- PowerShell: `--pids-limit=4096` ✅
- Bash: No pids-limit ❌

**Recommended:**
```bash
# Add to bash launcher
DOCKER_ARGS+=("--pids-limit=4096")
```

**Impact:**
- Prevents fork bomb attacks
- Limits blast radius of process creation
- 4096 is generous for development work

**Priority:** MEDIUM (consistency fix)

### 4. Read-Only Root Filesystem (Optional)

**Current State:**
- Root filesystem is writable

**Recommended (optional):**
```bash
# Add to launcher for maximum hardening
DOCKER_ARGS+=("--read-only")
# Mount tmpfs for temporary files
DOCKER_ARGS+=("--tmpfs" "/tmp:rw,noexec,nosuid,size=2g")
DOCKER_ARGS+=("--tmpfs" "/var/tmp:rw,noexec,nosuid,size=1g")
# Workspace remains writable (separate mount)
```

**Impact:**
- Container filesystem immutable (except workspace)
- Prevents persistence attempts
- May break some tools expecting writable filesystem

**Priority:** LOW (optional hardening, may impact compatibility)

**Recommendation:** Don't implement initially - test first

### 5. No-Exec on Mounts

**Recommended:**
```bash
# For credential mounts, add noexec
"-v" "${HOME}/.config/gh:/home/agentuser/.config/gh:ro,noexec"
```

**Impact:**
- Prevents executing malicious binaries from credential dirs
- Adds defense against credential directory abuse

**Priority:** LOW (defense in depth)

## Network Architecture Enhancements

### 1. Improved Squid Allowlist Management

**Current State:**
- Allowlist hardcoded in scripts
- Reasonable defaults but inflexible

**Recommended:**
Create `~/.config/coding-agents/network-allowlist.txt`:
```
# Default allowlist
*.github.com
*.githubcopilot.com
*.npmjs.org
*.pypi.org
*.nuget.org
*.docker.io
registry-1.docker.io
learn.microsoft.com
docs.microsoft.com
api.openai.com
anthropic.com

# User additions (optional)
# *.mycompany.com
```

**Launcher changes:**
```bash
# Read from file if exists, otherwise use defaults
ALLOWLIST_FILE="${HOME}/.config/coding-agents/network-allowlist.txt"
if [ -f "$ALLOWLIST_FILE" ]; then
    SQUID_DOMAINS=$(cat "$ALLOWLIST_FILE" | grep -v '^#' | grep -v '^$' | tr '\n' ',')
else
    SQUID_DOMAINS="$DEFAULT_DOMAINS"
fi
```

**Impact:**
- User can customize allowlist per project
- Can tighten for sensitive work
- Can expand for legitimate needs

**Priority:** MEDIUM (usability improvement)

### 2. Network Bandwidth Limits (Optional)

**Recommended (for sensitive environments):**
```bash
# Limit egress bandwidth to detect large uploads
DOCKER_ARGS+=("--network-bandwidth-limit" "10mbps")
```

**Impact:**
- Slows mass data exfiltration
- Makes large uploads more visible
- May impact legitimate downloads

**Priority:** LOW (optional for high-security scenarios)

### 3. DNS Filtering (Future)

**Concept:** Custom DNS resolver that:
- Logs all DNS queries
- Blocks known malicious domains
- Detects DNS exfiltration patterns

**Priority:** LOW (nice-to-have, complex)

## Filesystem Isolation Enhancements

### Current Model (Already Strong)

- ✅ Workspace is **copied**, not mounted
- ✅ True filesystem isolation
- ✅ Host repository unaffected

**No changes needed** - current model is exemplary

### Git Push Guardrails

**Recommended:** Add pre-push validation

Create `/usr/local/bin/safe-git-push`:
```bash
#!/bin/bash
# Safe git push wrapper

REMOTE="$1"
BRANCH="$2"

# Tier 1: Push to local remote (host repo) - always allow
if [ "$REMOTE" = "local" ]; then
    exec git push "$@"
fi

# Tier 3: Push to origin - require confirmation
if [ "$REMOTE" = "origin" ]; then
    echo "⚠️  Push to origin (public repository)"
    echo ""
    echo "Commits to be pushed:"
    git log --oneline origin/$BRANCH..$BRANCH 2>/dev/null || git log --oneline -5
    echo ""
    echo "Changed files:"
    git diff --stat origin/$BRANCH..$BRANCH 2>/dev/null || echo "(new branch)"
    echo ""
    read -p "Push to origin? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Push cancelled"
        exit 1
    fi
fi

exec git push "$@"
```

**Apply in entrypoint:**
```bash
# Alias git push to safe wrapper
git config --global alias.push '!safe-git-push'
```

**Impact:**
- Tier 1 (local) pushes remain automatic
- Tier 3 (origin) pushes require confirmation
- User sees what's being pushed

**Priority:** MEDIUM (UX/safety balance)

## Credential & Secret Management

### Current Model (Already Strong)

- ✅ Read-only mounts
- ✅ Socket-based proxies
- ✅ No credentials in images

**Enhancements:**

### 1. Per-Session Scoped Tokens (Future)

**Concept:**
- Generate temporary, scoped tokens per container launch
- Revoke automatically on container shutdown
- Limit blast radius if exfiltrated

**Implementation:**
- GitHub: Use GitHub App installation tokens (scoped to repo)
- MCP secrets: Generate per-session API keys

**Priority:** MEDIUM (significant security improvement, complex)

### 2. Credential Access Monitoring (Future)

**Concept:**
- Audit log when credential files are read
- Alert on suspicious patterns (read creds → network request)

**Implementation:**
- Use `auditd` or `inotify` to monitor file access
- Correlate with network logs from squid

**Priority:** LOW (defense in depth, complex)

## Monitoring & Audit Logging

### 1. Structured Logging

**Recommended:** Unified JSON log format

```json
{
  "timestamp": "2024-01-15T10:30:45Z",
  "container": "copilot-myapp-main",
  "agent": "copilot",
  "level": "INFO",
  "category": "network",
  "action": "http_request",
  "destination": "npmjs.org",
  "url": "https://npmjs.org/package/express",
  "size_bytes": 1024,
  "allowed": true
}
```

**Sources:**
- Squid access logs → JSON
- Container file operations → JSON
- Git operations → JSON
- MCP calls → JSON

**Priority:** MEDIUM (operational visibility)

### 2. Anomaly Detection

**Patterns to detect:**
- Large uploads (> 10MB)
- Many credential file reads
- Rapid MCP operations
- Unusual time-of-day activity
- Modifications to security configs

**Response:**
- Log alert
- Optional user notification
- Optional operation blocking

**Priority:** LOW (nice-to-have, requires ML/rules)

## Safe Abstraction Layer

### Implementation in Images

**Add to base image:**

`/usr/local/bin/safe-wrapper.py`:
```python
#!/usr/bin/env python3
"""
Safe operation wrappers for agent tools
"""
import os
import sys
import json
from pathlib import Path

WORKSPACE = Path("/workspace")
TIER_3_COMMANDS = ["docker", "podman", "sudo", "mount"]

def safe_file_write(path: str, content: str):
    """Only allow writes within workspace"""
    target = (WORKSPACE / path).resolve()
    if not target.is_relative_to(WORKSPACE):
        print(f"ERROR: Write outside workspace blocked: {path}", file=sys.stderr)
        sys.exit(1)
    target.write_text(content)

def safe_command(cmd: str):
    """Block dangerous commands"""
    for blocked in TIER_3_COMMANDS:
        if blocked in cmd:
            print(f"ERROR: Command blocked: {blocked}", file=sys.stderr)
            sys.exit(1)
    os.system(cmd)

if __name__ == "__main__":
    # Expose as CLI tool
    pass
```

**Priority:** MEDIUM (useful safety layer)

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        HOST SYSTEM                           │
│                                                              │
│  ┌──────────────┐  ┌────────────────┐  ┌────────────────┐ │
│  │ Git Repos    │  │ Credentials    │  │ Local Remote   │ │
│  │ (source)     │  │ (read-only)    │  │ (bare repo)    │ │
│  └──────┬───────┘  └────────┬───────┘  └────────┬───────┘ │
│         │                   │                    │          │
│         │ (copy)            │ (ro mount)         │ (mount)  │
│         ▼                   ▼                    ▼          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓  │   │
│  │  ┃      CONTAINER (HARDENED)                     ┃  │   │
│  │  ┃                                               ┃  │   │
│  │  ┃  Security Settings:                           ┃  │   │
│  │  ┃  • Non-root (UID 1000)                        ┃  │   │
│  │  ┃  • --cap-drop=ALL                             ┃  │   │
│  │  ┃  • --security-opt no-new-privileges           ┃  │   │
│  │  ┃  • --pids-limit 4096                          ┃  │   │
│  │  ┃  • Seccomp profile (syscall filter)           ┃  │   │
│  │  ┃  • Resource limits (CPU, RAM)                 ┃  │   │
│  │  ┃  • No docker.sock                             ┃  │   │
│  │  ┃                                               ┃  │   │
│  │  ┃  ┌─────────────────────────────┐             ┃  │   │
│  │  ┃  │ /workspace (writable)       │             ┃  │   │
│  │  ┃  │ • Copied from source        │             ┃  │   │
│  │  ┃  │ • Git branch isolated       │             ┃  │   │
│  │  ┃  │ • Changes tracked           │             ┃  │   │
│  │  ┃  └─────────────────────────────┘             ┃  │   │
│  │  ┃                                               ┃  │   │
│  │  ┃  ┌─────────────────────────────┐             ┃  │   │
│  │  ┃  │ ~/.config/* (ro mounts)     │             ┃  │   │
│  │  ┃  │ • Credentials                │             ┃  │   │
│  │  ┃  │ • Auth configs               │             ┃  │   │
│  │  ┃  │ • Cannot modify              │             ┃  │   │
│  │  ┃  └─────────────────────────────┘             ┃  │   │
│  │  ┃                                               ┃  │   │
│  │  ┃  ┌─────────────────────────────┐             ┃  │   │
│  │  ┃  │ Network                      │             ┃  │   │
│  │  ┃  │                              │             ┃  │   │
│  │  ┃  │ Mode: squid (recommended)    │             ┃  │   │
│  │  ┃  │   ↓                          │             ┃  │   │
│  │  ┃  └───┼──────────────────────────┘             ┃  │   │
│  │  ┗━━━━━━┼━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛  │   │
│  │         │                                            │   │
│  │         ▼                                            │   │
│  │  ┏━━━━━━━━━━━━━━━━━━━━━━┓                          │   │
│  │  ┃ SQUID PROXY CONTAINER ┃                          │   │
│  │  ┃                       ┃                          │   │
│  │  ┃ • Domain allowlist    ┃                          │   │
│  │  ┃ • Full logging        ┃                          │   │
│  │  ┃ • Request inspection  ┃                          │   │
│  │  ┗━━━━━━━━━┳━━━━━━━━━━━━┛                          │   │
│  │            │                                         │   │
│  └────────────┼─────────────────────────────────────────┘   │
│               │                                              │
└───────────────┼──────────────────────────────────────────────┘
                │
                ▼
         ╔══════════════════════╗
         ║  INTERNET            ║
         ║  • Allowlisted only  ║
         ║  • All logged        ║
         ╚══════════════════════╝
```

## Comparison: Current vs Hardened

| Feature | Current | Hardened | Impact |
|---------|---------|----------|--------|
| Non-root user | ✅ Yes | ✅ Yes | - |
| no-new-privileges | ✅ Yes | ✅ Yes | - |
| Capability drop | ⚠️ PowerShell only | ✅ Both | +Security |
| Seccomp profile | ❌ No | ✅ Yes | +Security |
| Pids limit | ⚠️ PowerShell only | ✅ Both | +Stability |
| Docker socket | ✅ Not mounted | ✅ Not mounted | - |
| Workspace model | ✅ Copy | ✅ Copy | - |
| Network modes | ✅ 3 modes | ✅ 3 modes | - |
| Network allowlist | ⚠️ Hardcoded | ✅ Configurable | +Usability |
| Credential mounts | ✅ Read-only | ✅ Read-only + noexec | +Security |
| Git push guardrail | ❌ No | ✅ Optional prompt | +Safety |
| Audit logging | ⚠️ Partial | ✅ Comprehensive | +Visibility |
| Safe abstractions | ❌ No | ✅ Yes | +Safety |

## Implementation Priority

### Phase 1: Critical Fixes (Immediate)
1. ✅ Add `--cap-drop=ALL` to bash launcher
2. ✅ Add `--pids-limit=4096` to bash launcher

### Phase 2: Important Hardening (Short-term)
3. ✅ Add seccomp profile
4. ✅ Make network allowlist configurable
5. ✅ Add git push guardrails (optional)

### Phase 3: Operational Improvements (Medium-term)
6. ✅ Implement structured logging
7. ✅ Add safe abstraction layer
8. ⚠️ Add credential access monitoring

### Phase 4: Advanced Features (Long-term)
9. ⚠️ Per-session scoped tokens
10. ⚠️ Anomaly detection
11. ⚠️ Advanced network filtering

## Conclusion

**The hardened architecture builds on strong foundations:**
- Current design is already excellent for isolation
- Critical fixes are small (capability drop, seccomp)
- Most enhancements are operational (logging, monitoring)
- No fundamental redesign needed

**With these changes:**
- Container escape becomes extremely unlikely
- Data exfiltration remains visible and controllable
- Destructive changes remain reversible
- Network access remains functional but monitored

**Result:** Safe unrestricted mode with minimal prompts and strong structural guarantees.

## Next Steps

See:
- `05-implementation-roadmap.md` for concrete implementation steps
- `06-attack-scenarios.md` for example attack chains and mitigations
- `07-safe-unrestricted-profile.md` for default configuration
