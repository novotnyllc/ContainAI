# Implementation Roadmap

## Purpose

This document provides concrete, actionable steps to implement the hardened architecture recommendations.

## Phase 1: Critical Fixes (Immediate - Day 1)

### 1.1: Add Capability Drop to Bash Launcher

**Priority:** CRITICAL  
**Effort:** 5 minutes  
**Risk:** None (improves security, no functional impact)

**File:** `scripts/launchers/launch-agent`

**Change:**
```bash
# Around line 615, after existing security opts
DOCKER_ARGS+=(
    "-w" "/workspace"
    "--network" "$NETWORK_MODE"
    "--security-opt" "no-new-privileges:true"
    "--cap-drop=ALL"  # ← ADD THIS LINE
    "--cpus=$CPU"
    "--memory=$MEMORY"
)
```

**Testing:**
```bash
# Launch container and verify capabilities are dropped
./launch-agent copilot
docker exec copilot-test-main capsh --print | grep "Current:"
# Should show: Current: =

# Test that normal operations still work
docker exec copilot-test-main git status
docker exec copilot-test-main npm install express
docker exec copilot-test-main dotnet build
```

**Validation:** All normal operations work, capabilities list is empty

---

### 1.2: Add Process Limits to Bash Launcher

**Priority:** MEDIUM  
**Effort:** 5 minutes  
**Risk:** None (prevents fork bombs)

**File:** `scripts/launchers/launch-agent`

**Change:**
```bash
# Same location, add pids-limit
DOCKER_ARGS+=(
    "-w" "/workspace"
    "--network" "$NETWORK_MODE"
    "--security-opt" "no-new-privileges:true"
    "--cap-drop=ALL"
    "--pids-limit=4096"  # ← ADD THIS LINE
    "--cpus=$CPU"
    "--memory=$MEMORY"
)
```

**Testing:**
```bash
# Test fork bomb protection
docker exec copilot-test-main bash -c ':(){ :|:& };:'
# Should fail with "Resource temporarily unavailable" before consuming resources
```

**Validation:** Fork bomb is blocked, normal usage unaffected

---

### 1.3: Update Documentation

**Priority:** HIGH  
**Effort:** 30 minutes  
**Risk:** None

**Files to update:**
- `SECURITY.md` - Document new hardening measures
- `docs/architecture.md` - Update security section
- `README.md` - Mention enhanced security

**Changes:**
- Add section "Container Hardening" explaining new security options
- Document that all Linux capabilities are dropped
- Explain pids-limit protection
- Note that these changes improve security without reducing functionality

---

## Phase 2: Important Hardening (Week 1)

### 2.1: Create and Apply Seccomp Profile

**Priority:** HIGH  
**Effort:** 2 hours  
**Risk:** Low (may need testing with various tools)

**Step 1: Create profile**

**File:** `docker/seccomp/default.json`

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_ARM64"
  ],
  "syscalls": [
    {
      "names": [
        "accept", "accept4", "access", "alarm", "arch_prctl", "bind", "brk",
        "capget", "chdir", "chmod", "chown", "clock_getres", "clock_gettime",
        "clock_nanosleep", "clone", "clone3", "close", "connect", "copy_file_range",
        "creat", "dup", "dup2", "dup3", "epoll_create", "epoll_create1",
        "epoll_ctl", "epoll_pwait", "epoll_wait", "eventfd", "eventfd2",
        "execve", "execveat", "exit", "exit_group", "faccessat", "fadvise64",
        "fallocate", "fanotify_mark", "fchdir", "fchmod", "fchmodat", "fchown",
        "fchownat", "fcntl", "fdatasync", "fgetxattr", "flistxattr", "flock",
        "fork", "fremovexattr", "fsetxattr", "fstat", "fstatat64", "fstatfs",
        "fsync", "ftruncate", "futex", "getcwd", "getdents", "getdents64",
        "getegid", "geteuid", "getgid", "getgroups", "getitimer", "getpeername",
        "getpgid", "getpgrp", "getpid", "getppid", "getpriority", "getrandom",
        "getresgid", "getresuid", "getrlimit", "getrusage", "getsid", "getsockname",
        "getsockopt", "gettid", "gettimeofday", "getuid", "getxattr", "inotify_add_watch",
        "inotify_init", "inotify_init1", "inotify_rm_watch", "io_cancel", "io_destroy",
        "io_getevents", "io_setup", "io_submit", "ioctl", "ioprio_get", "ioprio_set",
        "kill", "lchown", "lgetxattr", "link", "linkat", "listen", "listxattr",
        "llistxattr", "lremovexattr", "lseek", "lsetxattr", "lstat", "madvise",
        "memfd_create", "mincore", "mkdir", "mkdirat", "mknod", "mknodat", "mlock",
        "mlock2", "mlockall", "mmap", "mprotect", "mq_getsetattr", "mq_notify",
        "mq_open", "mq_timedreceive", "mq_timedsend", "mq_unlink", "mremap",
        "msgctl", "msgget", "msgrcv", "msgsnd", "msync", "munlock", "munlockall",
        "munmap", "name_to_handle_at", "nanosleep", "newfstatat", "open", "openat",
        "pause", "pipe", "pipe2", "poll", "ppoll", "prctl", "pread64", "preadv",
        "preadv2", "prlimit64", "pselect6", "pwrite64", "pwritev", "pwritev2",
        "read", "readahead", "readlink", "readlinkat", "readv", "recv", "recvfrom",
        "recvmmsg", "recvmsg", "remap_file_pages", "removexattr", "rename", "renameat",
        "renameat2", "restart_syscall", "rmdir", "rt_sigaction", "rt_sigpending",
        "rt_sigprocmask", "rt_sigqueueinfo", "rt_sigreturn", "rt_sigsuspend",
        "rt_sigtimedwait", "rt_tgsigqueueinfo", "sched_getaffinity", "sched_getattr",
        "sched_getparam", "sched_get_priority_max", "sched_get_priority_min",
        "sched_getscheduler", "sched_rr_get_interval", "sched_setaffinity",
        "sched_setattr", "sched_setparam", "sched_setscheduler", "sched_yield",
        "seccomp", "select", "semctl", "semget", "semop", "semtimedop", "send",
        "sendfile", "sendfile64", "sendmmsg", "sendmsg", "sendto", "set_robust_list",
        "set_tid_address", "setfsgid", "setfsuid", "setgid", "setgroups", "setitimer",
        "setpgid", "setpriority", "setregid", "setresgid", "setresuid", "setreuid",
        "setrlimit", "setsid", "setsockopt", "setuid", "setxattr", "shmat", "shmctl",
        "shmdt", "shmget", "shutdown", "sigaltstack", "signalfd", "signalfd4",
        "socket", "socketpair", "splice", "stat", "statfs", "statx", "symlink",
        "symlinkat", "sync", "sync_file_range", "syncfs", "sysinfo", "tee", "tgkill",
        "time", "timer_create", "timer_delete", "timer_getoverrun", "timer_gettime",
        "timer_settime", "timerfd_create", "timerfd_gettime", "timerfd_settime",
        "times", "tkill", "truncate", "umask", "uname", "unlink", "unlinkat",
        "utime", "utimensat", "utimes", "vfork", "vmsplice", "wait4", "waitid",
        "write", "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

**Step 2: Apply in launcher**

**File:** `scripts/launchers/launch-agent`

```bash
# Determine seccomp profile path
SECCOMP_PROFILE="$REPO_ROOT/docker/seccomp/default.json"

# Add to docker args if file exists
if [ -f "$SECCOMP_PROFILE" ]; then
    DOCKER_ARGS+=("--security-opt" "seccomp=$SECCOMP_PROFILE")
fi
```

**Step 3: Test**

```bash
# Test normal operations
./launch-agent copilot
docker exec copilot-test-main npm install express  # Should work
docker exec copilot-test-main dotnet build         # Should work
docker exec copilot-test-main git commit -m "test" # Should work

# Test blocked operations
docker exec copilot-test-main mount /dev/sda1 /mnt # Should fail
docker exec copilot-test-main reboot               # Should fail
```

**Rollback plan:** Remove seccomp line if issues found

---

### 2.2: Make Network Allowlist Configurable

**Priority:** MEDIUM  
**Effort:** 1 hour  
**Risk:** Low

**File:** `scripts/utils/common-functions.sh`

**Current:**
```bash
DEFAULT_SQUID_DOMAINS="*.github.com,*.githubcopilot.com,..."
```

**New:**
```bash
get_network_allowlist() {
    local allowlist_file="${HOME}/.config/coding-agents/network-allowlist.txt"
    
    if [ -f "$allowlist_file" ]; then
        # Read from file, remove comments and empty lines
        cat "$allowlist_file" | grep -v '^#' | grep -v '^$' | tr '\n' ','
    else
        # Return defaults
        echo "$DEFAULT_SQUID_DOMAINS"
    fi
}
```

**Usage in launcher:**
```bash
SQUID_ALLOWED_DOMAINS=$(get_network_allowlist)
```

**Create default file:**

**File:** `~/.config/coding-agents/network-allowlist.txt.example`

```
# Network Allowlist for Squid Proxy Mode
# Lines starting with # are comments
# One domain pattern per line (wildcards supported)

# GitHub
*.github.com
*.githubusercontent.com

# Package Managers
*.npmjs.org
*.pypi.org
*.nuget.org

# Container Registries
*.docker.io
registry-1.docker.io

# Documentation
learn.microsoft.com
docs.microsoft.com

# Add custom domains below:
# *.mycompany.com
```

**Documentation:** Add to `docs/network-proxy.md`

---

## Phase 3: Operational Improvements (Week 2-4)

### 3.1: Add Git Push Guardrails

**Priority:** MEDIUM  
**Effort:** 2 hours  
**Risk:** Low (user experience change)

**File:** `docker/base/Dockerfile`

```dockerfile
# Add safe-git-push wrapper
COPY --chown=root:root scripts/runtime/safe-git-push.sh /usr/local/bin/safe-git-push
RUN chmod +x /usr/local/bin/safe-git-push
```

**File:** `scripts/runtime/safe-git-push.sh`

```bash
#!/bin/bash
# Safe git push wrapper with user confirmation for origin

set -euo pipefail

REMOTE="${1:-origin}"
shift

# Tier 1: Local remote - always allow (fast sync to host)
if [ "$REMOTE" = "local" ]; then
    exec git push "$@" "local"
fi

# Tier 3: Origin remote - require confirmation
if [ "$REMOTE" = "origin" ]; then
    echo ""
    echo "⚠️  Git Push to Origin (Public Repository)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Show what will be pushed
    CURRENT_BRANCH=$(git branch --show-current)
    echo "Branch: $CURRENT_BRANCH"
    echo ""
    echo "Commits to be pushed:"
    git log --oneline "origin/$CURRENT_BRANCH..$CURRENT_BRANCH" 2>/dev/null || git log --oneline -5
    echo ""
    echo "Files changed:"
    git diff --stat "origin/$CURRENT_BRANCH..$CURRENT_BRANCH" 2>/dev/null || echo "(new branch)"
    echo ""
    
    # Confirmation prompt
    read -p "Push to origin? [y/N] " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Push cancelled"
        exit 1
    fi
    
    echo "✅ Pushing to origin..."
fi

# Execute actual push
exec git push "$@" "$REMOTE"
```

**Apply in entrypoint:**

**File:** `scripts/runtime/entrypoint.sh`

```bash
# Configure git to use safe push wrapper
if [ -f /usr/local/bin/safe-git-push ]; then
    git config --global alias.push '!/usr/local/bin/safe-git-push'
fi
```

**Testing:**
```bash
# Test local push (should be automatic)
git push local copilot/test

# Test origin push (should prompt)
git push origin copilot/test
# Should show commits and ask for confirmation
```

---

### 3.2: Implement Structured Logging

**Priority:** MEDIUM  
**Effort:** 4 hours  
**Risk:** None (additive)

**File:** `scripts/runtime/logger.sh`

```bash
#!/bin/bash
# Structured logging for agent operations

LOG_DIR="/tmp/agent-logs"
mkdir -p "$LOG_DIR"

log_event() {
    local level="$1"
    local category="$2"
    local action="$3"
    shift 3
    local details="$@"
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local container=${CONTAINER_NAME:-unknown}
    local agent=${AGENT_NAME:-unknown}
    
    local json=$(jq -n \
        --arg ts "$timestamp" \
        --arg cont "$container" \
        --arg ag "$agent" \
        --arg lvl "$level" \
        --arg cat "$category" \
        --arg act "$action" \
        --arg det "$details" \
        '{
            timestamp: $ts,
            container: $cont,
            agent: $ag,
            level: $lvl,
            category: $cat,
            action: $act,
            details: $det
        }')
    
    echo "$json" | tee -a "$LOG_DIR/events.jsonl"
}

# Export for use in other scripts
export -f log_event
```

**Usage:**
```bash
# In entrypoint or other scripts
source /usr/local/bin/logger.sh

# Log events
log_event "INFO" "filesystem" "file_write" "path=/workspace/file.txt"
log_event "INFO" "network" "http_request" "url=https://npmjs.org"
log_event "INFO" "git" "commit" "message=feat: Add feature"
log_event "WARN" "credential" "file_read" "path=~/.config/gh/hosts.yml"
```

**Integration points:**
- Wrapper scripts (safe-git-push, etc.)
- Entrypoint actions
- MCP server calls (future)

---

### 3.3: Add Safe Abstraction Layer

**Priority:** MEDIUM  
**Effort:** 6 hours  
**Risk:** Low (additive, optional use)

**File:** `docker/base/Dockerfile`

```dockerfile
# Add safe wrappers
COPY --chown=root:root scripts/runtime/safe-wrappers.py /usr/local/bin/safe-wrappers
RUN chmod +x /usr/local/bin/safe-wrappers && \
    pip3 install --no-cache-dir pyyaml
```

**File:** `scripts/runtime/safe-wrappers.py`

```python
#!/usr/bin/env python3
"""
Safe operation wrappers for agent tools
Provides workspace-scoped file operations and command filtering
"""

import os
import sys
import subprocess
from pathlib import Path

WORKSPACE = Path(os.getenv("WORKSPACE_DIR", "/workspace"))
BLOCKED_COMMANDS = ["docker", "podman", "sudo", "mount", "umount"]

class SecurityError(Exception):
    pass

def safe_file_write(path: str, content: str) -> None:
    """Write file only within workspace"""
    try:
        target = (WORKSPACE / path).resolve()
        if not str(target).startswith(str(WORKSPACE)):
            raise SecurityError(f"Write outside workspace blocked: {path}")
        
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        print(f"✅ File written: {path}")
        
    except SecurityError as e:
        print(f"❌ {e}", file=sys.stderr)
        sys.exit(1)

def safe_command(command: str) -> int:
    """Execute command with safety checks"""
    for blocked in BLOCKED_COMMANDS:
        if blocked in command.lower():
            print(f"❌ Blocked command: {blocked}", file=sys.stderr)
            sys.exit(1)
    
    return subprocess.call(command, shell=True)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: safe-wrappers <operation> [args...]")
        sys.exit(1)
    
    operation = sys.argv[1]
    
    if operation == "write":
        if len(sys.argv) != 4:
            print("Usage: safe-wrappers write <path> <content>")
            sys.exit(1)
        safe_file_write(sys.argv[2], sys.argv[3])
    
    elif operation == "exec":
        if len(sys.argv) != 3:
            print("Usage: safe-wrappers exec <command>")
            sys.exit(1)
        sys.exit(safe_command(sys.argv[2]))
    
    else:
        print(f"Unknown operation: {operation}")
        sys.exit(1)
```

**Testing:**
```bash
# Test safe writes
safe-wrappers write "test.txt" "hello"     # Should work
safe-wrappers write "/etc/passwd" "hello"  # Should block

# Test safe commands
safe-wrappers exec "echo hello"    # Should work
safe-wrappers exec "docker ps"     # Should block
```

---

## Phase 4: Advanced Features (Month 2-3)

### 4.1: Per-Session Scoped Tokens (Future)

**Priority:** LOW (complex, significant improvement)  
**Effort:** 2 weeks  
**Risk:** Medium (requires GitHub App, token management)

**Concept:**
- Create GitHub App for token generation
- Generate installation tokens per container launch
- Revoke on container shutdown

**Research needed:** GitHub App permissions, token scope

---

### 4.2: Anomaly Detection (Future)

**Priority:** LOW  
**Effort:** 3 weeks  
**Risk:** Low (additive)

**Concept:**
- Analyze structured logs for patterns
- Detect: large uploads, credential abuse, rapid operations
- Alert or block suspicious behavior

**Technologies:** Python + rule engine or ML

---

## Testing Strategy

### Unit Tests

For each component:
```bash
# Test safe-git-push
test_local_push_auto_allows() {
    result=$(echo "n" | git push local test 2>&1)
    assert_success
}

test_origin_push_prompts() {
    result=$(echo "n" | git push origin test 2>&1)
    assert_contains "Push to origin?"
}
```

### Integration Tests

Full launcher tests:
```bash
# Test with all security features
./launch-agent copilot --network-proxy squid
assert_container_running "copilot-test-main"
assert_no_capabilities
assert_seccomp_applied
assert_network_proxied
```

### Security Tests

Verify hardening:
```bash
# Test capability drop
docker exec test-container capsh --print | grep "Current:"
# Expected: Current: =

# Test seccomp
docker exec test-container mount /dev/sda1 /mnt
# Expected: Operation not permitted

# Test read-only credentials
docker exec test-container sh -c 'echo "evil" > ~/.config/gh/hosts.yml'
# Expected: Read-only file system
```

---

## Rollout Plan

### Week 1: Critical Fixes
- Day 1: Implement capability drop + pids-limit
- Day 2: Test thoroughly
- Day 3: Update documentation
- Day 4: Code review
- Day 5: Merge and release

### Week 2: Seccomp + Allowlist
- Day 1-2: Create and test seccomp profile
- Day 3: Implement configurable allowlist
- Day 4: Documentation
- Day 5: Code review and merge

### Week 3-4: Operational Improvements
- Week 3: Git push guardrails + structured logging
- Week 4: Safe abstraction layer
- Testing and documentation throughout

### Month 2-3: Advanced Features
- Research and prototype per-session tokens
- Design anomaly detection system
- Gradual rollout with feature flags

---

## Success Metrics

### Security Metrics
- ✅ All containers run with zero capabilities
- ✅ Seccomp profile applied to 100% of containers
- ✅ No container escape vulnerabilities
- ✅ All network traffic logged (squid mode)

### Usability Metrics
- ✅ 99% of operations require no prompts (Tier 1)
- ✅ < 1% operations prompt (Tier 3)
- ✅ No functional regressions reported
- ✅ User satisfaction maintained or improved

### Operational Metrics
- ✅ Complete audit trail available
- ✅ Incidents can be investigated via logs
- ✅ Anomaly detection identifies suspicious behavior

---

## Rollback Procedures

If issues arise:

### Capability Drop Issues
```bash
# Temporary: remove from launcher
# sed -i '/--cap-drop=ALL/d' scripts/launchers/launch-agent
```

### Seccomp Issues
```bash
# Temporary: remove from launcher
# sed -i '/seccomp=/d' scripts/launchers/launch-agent
```

### Git Push Guardrails Issues
```bash
# Disable in entrypoint
# git config --global --unset alias.push
```

---

## Documentation Updates

Update these files:
- `README.md` - Mention enhanced security
- `SECURITY.md` - Document all hardening measures
- `docs/architecture.md` - Update security section
- `docs/network-proxy.md` - Document allowlist configuration
- `CONTRIBUTING.md` - Add security testing guidelines

---

## Conclusion

This roadmap provides a phased approach to implementing the hardened architecture:

**Phase 1 (Week 1):** Critical security fixes with minimal risk
**Phase 2 (Week 2):** Important hardening that requires testing
**Phase 3 (Weeks 3-4):** Operational improvements for visibility
**Phase 4 (Months 2-3):** Advanced features for maximum security

Each phase is independently valuable and can be deployed without waiting for subsequent phases.

**Next:** See `06-attack-scenarios.md` for example attack chains and how these mitigations prevent them.
