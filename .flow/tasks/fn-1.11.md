# fn-1.11 Create check-sandbox.sh for Docker Sandbox and ECI detection

## Description
Create a script that runs on container startup to detect and report the container's security environment status.

### Purpose

Provide early feedback to users about their container's security posture:
- Detect whether running in Docker Sandbox (vs plain Docker)
- Check and report ECI (Enhanced Container Isolation) status
- Recommend enabling ECI if not detected

### Detection Methods

**Docker Sandbox Detection**:
- Check for sandbox-specific environment variables
- Check for `/run/.sandbox` marker file (if exists)
- Check cgroup hierarchy for sandbox indicators
- Check for `docker-sandbox` in container labels/metadata

**ECI Detection**:
- Check for user namespace isolation (compare UID inside vs outside)
- Check `/proc/self/uid_map` for namespace mapping
- Check seccomp filter status via `/proc/self/status`
- Look for ECI-specific markers in `/sys/fs/cgroup`

### Script Implementation

```bash
#!/usr/bin/env bash
# check-sandbox.sh - Detect Docker Sandbox and ECI status
set -euo pipefail

info() { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
warn() { echo "⚠️  $*" >&2; }

echo "=== Container Security Environment Check ==="
echo ""

# Docker Sandbox Detection
SANDBOX_DETECTED=false
if [[ -f /run/.sandbox ]] || [[ -n "${DOCKER_SANDBOX:-}" ]]; then
  SANDBOX_DETECTED=true
  success "Running in Docker Sandbox"
else
  # Heuristic: check for sandbox-specific cgroup patterns
  if grep -q "sandbox" /proc/self/cgroup 2>/dev/null; then
    SANDBOX_DETECTED=true
    success "Running in Docker Sandbox (detected via cgroup)"
  else
    warn "NOT running in Docker Sandbox - recommend using 'docker sandbox run'"
  fi
fi

# ECI Detection via user namespace
echo ""
if [[ -f /proc/self/uid_map ]]; then
  # If uid_map shows non-identity mapping, user namespaces are active
  UID_MAP=$(cat /proc/self/uid_map)
  if echo "$UID_MAP" | grep -qv "^\s*0\s*0"; then
    success "ECI enabled (user namespace isolation detected)"
  else
    # Check if we're in a nested namespace
    if [[ $(id -u) -eq 0 ]] && [[ -f /.dockerenv ]]; then
      warn "ECI may not be enabled - recommend enabling Enhanced Container Isolation"
      info "See: Docker Desktop > Settings > Resources > Advanced > ECI"
    else
      info "ECI status: running as non-root user (uid=$(id -u))"
    fi
  fi
else
  warn "Cannot determine ECI status (uid_map not readable)"
fi

# Summary
echo ""
echo "=== Summary ==="
if [[ "$SANDBOX_DETECTED" == "true" ]]; then
  success "Container security: Docker Sandbox mode"
else
  warn "Container security: Standard Docker mode"
  info "For enhanced security, use: docker sandbox run <image>"
fi
```

### Integration Options

1. **Manual invocation**: User can run `./check-sandbox.sh` at any time
2. **ENTRYPOINT wrapper**: Optionally run on container start (non-blocking)
3. **Build verification**: Run during `docker build` to validate base image

### Important Notes

- Script is informational only - does not block container startup
- Heuristics may vary by Docker Desktop version
- ECI detection is best-effort (not all indicators are documented)

## Acceptance
- [ ] `dotnet-wasm/check-sandbox.sh` exists and is executable
- [ ] Script uses `set -euo pipefail` pattern
- [ ] Script detects Docker Sandbox vs plain Docker
- [ ] Script checks and reports ECI status
- [ ] Script provides recommendation if ECI not detected
- [ ] Script output is clear and actionable
- [ ] Script does NOT block container startup (informational only)
- [ ] Script handles missing files gracefully (no errors)
- [ ] README documents the script and its output

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
