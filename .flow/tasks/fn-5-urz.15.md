# fn-5-urz.15 cai setup - Linux native Sysbox installation

## Description
## Overview

Implement `cai setup` for native Linux (non-WSL) environments. This is the simplest path since Sysbox has full support on native Linux.

## Command

```bash
cai setup [--force] [--dry-run] [--verbose]
```

## What It Does

1. **Detect native Linux environment**
   ```bash
   if [[ "$(uname -s)" == "Linux" ]] && ! grep -qi "microsoft" /proc/version 2>/dev/null; then
       platform="linux"
   fi
   ```

2. **Detect distribution**
   ```bash
   if [[ -f /etc/os-release ]]; then
       . /etc/os-release
       distro="${ID:-unknown}"
   fi
   ```

3. **Install Sysbox package**
   - Ubuntu/Debian: Download and install `.deb` package
   - Fedora: Build from source or use alternative
   - Other: Show instructions

4. **Configure Docker daemon**
   ```json
   // /etc/docker/daemon.json
   {
     "runtimes": {
       "sysbox-runc": {
         "path": "/usr/bin/sysbox-runc"
       }
     }
   }
   ```
   Note: Do NOT set as default runtime to preserve compatibility.

5. **Create Docker context**
   ```bash
   # For systems where Docker Desktop is also installed
   docker context create containai-secure \
     --docker "host=unix:///var/run/docker.sock"
   ```

6. **Verify installation**
   ```bash
   docker --context containai-secure run --rm --runtime=sysbox-runc alpine echo "Sysbox works!"
   ```

## Supported Distributions

| Distribution | Package | Min Kernel | Notes |
|--------------|---------|------------|-------|
| Ubuntu 24.04 | .deb | 6.8+ | Full support |
| Ubuntu 22.04 | .deb | 5.15+ | Full support |
| Debian 12 | .deb | 6.1+ | Full support |
| Fedora 38+ | Build | 6.0+ | Build from source |

## Docker Desktop Coexistence

On systems where Docker Desktop is also installed:
- Detect if Docker Desktop is running
- Create separate `containai-secure` context
- Never modify Docker Desktop configuration
- Warn user about potential conflicts

```bash
# Check if Docker Desktop is running
if pgrep -x "docker-desktop" >/dev/null || docker context ls | grep -q "desktop-linux"; then
    echo "[WARN] Docker Desktop detected. Creating separate context."
fi
```

## Depends On

<!-- Updated by plan-sync: fn-5-urz.1 Sysbox context confirmed, sandbox context UNKNOWN (blocked) -->
- Task 1 spike (fn-5-urz.1) findings:
  - **Sysbox context: CONFIRMED** - Native Linux Sysbox installation can proceed
  - **Sandbox context: UNKNOWN** - Blocked pending Docker Desktop 4.50+ testing
- NOTE: Spike document recommends NOT proceeding until Docker Desktop testing completes

## References

- Sysbox install: https://github.com/nestybox/sysbox/blob/master/docs/user-guide/install-package.md
- Sysbox distro compat: https://github.com/nestybox/sysbox/blob/master/docs/distro-compat.md
## Acceptance
- [ ] Detects native Linux (not WSL) correctly
- [ ] Detects distribution (Ubuntu, Debian, Fedora)
- [ ] Downloads correct Sysbox package for distribution
- [ ] Installs Sysbox package successfully
- [ ] Configures daemon.json with sysbox-runc runtime
- [ ] Does NOT set sysbox-runc as default runtime
- [ ] Creates `containai-secure` Docker context
- [ ] Verifies Sysbox works with test container
- [ ] Detects Docker Desktop if present and warns
- [ ] Does NOT modify Docker Desktop configuration
- [ ] `--dry-run` shows what would be done without changes
- [ ] Handles unsupported distributions gracefully with clear message
## Done summary
Implemented native Linux Sysbox installation in `cai setup` with distro detection (Ubuntu/Debian auto-install), Docker preflight checks, daemon.json configuration, and verification via test container. Updated doctor.sh and test-secure-engine.sh to expect correct socket path for native Linux.
## Evidence
- Commits: fff5aeb86d3a36e88dfcb3e955d5c31fe589ed42, 56184c9, 5195cf9, e8135a8
- Tests: shellcheck -s bash agent-sandbox/lib/setup.sh, cai setup --help
- PRs: