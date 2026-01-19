# fn-5-urz.10 WSL Secure Engine provisioning

## Description
## Overview

Implement `cai setup` for WSL2 environments with seccomp compatibility detection and `--force` bypass for warnings.

**KEY CHANGE FROM ORIGINAL**: Sysbox WSL2 issue #32 was CLOSED as completed (June 2025). WSL2 support exists but has caveats around seccomp filters on WSL 1.1.0+.

## Command

```bash
cai setup [--force] [--dry-run] [--verbose]
```

## What It Does

1. **Detect WSL2 environment**
   ```bash
   if grep -qi "microsoft-standard" /proc/version 2>/dev/null; then
       platform="wsl2"
   fi
   ```

2. **Test seccomp compatibility** (WSL 1.1.0+ has seccomp on PID 1)
   ```bash
   _cai_test_wsl2_seccomp() {
       # WSL 1.1.0+ attaches seccomp filter to PID 1
       # This causes EBUSY when Sysbox tries to add seccomp-notify
       # Test by attempting to create a minimal seccomp container
       local result
       result=$(docker run --rm --security-opt seccomp=unconfined alpine echo ok 2>&1)
       # If this works but sysbox fails, seccomp conflict exists
   }
   ```

3. **If seccomp test fails and no `--force`:**
   - Show **big warning** (see below)
   - Exit with code 1 (not 0)
   - User must run with `--force` to proceed

4. **If `--force` or seccomp passes:**
   - Install Sysbox package
   - Configure `/etc/docker/daemon.json` with `sysbox-runc` runtime
   - Create `containai-secure` Docker context
   - Verify installation

## Big Warning Message

```
╔══════════════════════════════════════════════════════════════════╗
║                         ⚠️  WARNING                              ║
╠══════════════════════════════════════════════════════════════════╣
║ Sysbox on WSL2 may not work due to seccomp filter conflicts.    ║
║                                                                  ║
║ Your WSL version (1.1.0+) has a seccomp filter on PID 1 that    ║
║ conflicts with Sysbox's seccomp-notify mechanism.               ║
║                                                                  ║
║ Docker Sandbox will still work (this is the hard requirement).  ║
║ Sysbox provides additional isolation but is optional.           ║
║                                                                  ║
║ Options:                                                         ║
║   1. Proceed anyway: cai setup --force                          ║
║   2. Downgrade WSL:  wsl --update --web-download --version 1.0.3║
║   3. Skip Sysbox:    Use Docker Sandbox without Sysbox          ║
╚══════════════════════════════════════════════════════════════════╝
```

## Docker Desktop Protection

**CRITICAL: NEVER interfere with Docker Desktop**

- Create `containai-secure` context pointing to separate socket
- NEVER modify the `default` or `desktop-linux` contexts
- NEVER touch Docker Desktop's daemon.json
- All Sysbox operations use explicit `--context containai-secure`

## WSL-Specific Configuration

```json
// /etc/docker/daemon.json (WSL distro, NOT Docker Desktop)
{
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  }
}
```

Note: Do NOT set `default-runtime` to Sysbox - keep runc as default.

## Context Creation

```bash
docker context create containai-secure \
  --docker "host=unix:///var/run/docker-containai.sock"
```

## Depends On

<!-- Updated by plan-sync: fn-5-urz.1 Sysbox context confirmed, sandbox context UNKNOWN (blocked) -->
- Task 1 spike (fn-5-urz.1) findings:
  - **Sysbox context: CONFIRMED** - Proceeds with Sysbox setup
  - **Sandbox context: UNKNOWN** - Blocked pending Docker Desktop 4.50+ testing
- NOTE: Spike document recommends NOT proceeding until Docker Desktop testing completes

## References

- Sysbox WSL2 issue #32 (CLOSED - completed June 2025)
- WSL seccomp issue: https://github.com/microsoft/WSL/issues/9548
- Docker userns-remap: https://docs.docker.com/engine/security/userns-remap/
## Overview

Implement `containai install secure-engine` for WSL environments.

**CRITICAL BLOCKER**: Sysbox does NOT officially support WSL2. This task must determine a viable path:
1. Use unofficial Sysbox on WSL2 (community workarounds exist)
2. Use alternative isolation (gVisor, userns-remap only)
3. Document as unsupported, recommend Docker Business + ECI

## Command

```bash
containai install secure-engine
```

## What It Does (if viable)

1. Detect WSL distro and version
2. Install Docker Engine (separate from Docker Desktop integration)
3. Install Sysbox runtime (if supported) OR alternative
4. Configure daemon.json:
   - `default-runtime: "sysbox-runc"` (or alternative)
   - `userns-remap: "default"`
   - Optional seccomp profile
5. Create Docker context `containai-secure`
6. Verify installation

## WSL-Specific Configuration

```json
// /etc/docker/daemon.json in Secure Engine distro
{
  "default-runtime": "sysbox-runc",
  "userns-remap": "default",
  "runtimes": {
    "sysbox-runc": {
      "path": "/usr/bin/sysbox-runc"
    }
  }
}
```

## Context Creation

```bash
docker context create containai-secure \
  --docker "host=unix:///path/to/secure/docker.sock"
```

## Depends On

<!-- Updated by plan-sync: fn-5-urz.1 Sysbox context confirmed, sandbox context UNKNOWN (blocked) -->
- Task 1 spike (fn-5-urz.1) findings:
  - **Sysbox context: CONFIRMED** - Proceeds with Sysbox setup
  - **Sandbox context: UNKNOWN** - Blocked pending Docker Desktop 4.50+ testing
- Research on Sysbox WSL2 viability (GitHub issue #32)

## References

- Sysbox WSL2 issue: https://github.com/nestybox/sysbox/issues/32
- Docker userns-remap: https://docs.docker.com/engine/security/userns-remap/
## Acceptance
- [ ] Detects WSL2 environment correctly via `/proc/version`
- [ ] Tests seccomp compatibility before Sysbox installation
- [ ] Shows big warning if seccomp test fails
- [ ] Requires `--force` flag to proceed when seccomp test fails
- [ ] `--force` proceeds with Sysbox installation despite warning
- [ ] Without `--force`, exits with message about Docker Sandbox still working
- [ ] Installs Sysbox package correctly
- [ ] Configures daemon.json with sysbox-runc runtime (NOT as default)
- [ ] Creates `containai-secure` Docker context
- [ ] Does NOT modify Docker Desktop or default context
- [ ] Does NOT set sysbox-runc as default runtime
- [ ] Provides clear output during installation
- [ ] `--dry-run` shows what would be done without changes
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
