# fn-5-urz.4 Docker Desktop + Sandboxes availability detection

## Description
## Overview

Implement detection functions for Docker Desktop version and Sandboxes feature availability.

## Functions to Implement

### _cai_docker_desktop_version()
```bash
# Returns Docker Desktop version or empty if not Docker Desktop
docker version --format '{{.Server.Platform.Name}}'  # "Docker Desktop X.Y.Z"
# Parse version number, return semver-compatible string
```

### _cai_sandbox_available()
```bash
# Check if docker sandbox plugin exists
docker sandbox version >/dev/null 2>&1
# Returns: 0 if available, 1 if not
```

### _cai_sandbox_feature_enabled()
```bash
# Check if sandboxes feature is enabled (not just installed)
# Handle "beta features disabled by admin" case
docker sandbox ls >/dev/null 2>&1
# Parse error output for admin policy messaging
```

## Error Cases

1. **Docker not running**: Clear message "Docker Desktop is not running"
2. **Version < 4.50**: "Docker Desktop 4.50+ required (found: X.Y.Z)"
3. **Sandbox plugin missing**: "docker sandbox command not found - enable experimental features"
4. **Admin policy blocks**: "Sandboxes disabled by administrator policy"

## Reuse

- `aliases.sh:129-228` - `_asb_check_sandbox()` has similar logic
- Extract and refactor, don't duplicate

## References

- Docker troubleshooting: https://docs.docker.com/ai/sandboxes/troubleshooting/
- Settings Management: https://docs.docker.com/desktop/settings-and-maintenance/settings/
## Acceptance
- [ ] `_cai_docker_desktop_version` returns semver string (e.g., "4.50.1")
- [ ] Returns empty/error for non-Docker-Desktop docker (e.g., colima)
- [ ] `_cai_sandbox_available` returns 0/1 correctly
- [ ] `_cai_sandbox_feature_enabled` detects admin policy blocks
- [ ] Error messages are actionable with remediation steps
- [ ] Works when Docker is not running (doesn't hang)
## Done summary
Implemented Docker Desktop and Sandboxes availability detection with timeout-protected checks, actionable error messages, and admin policy block detection. Functions: _cai_docker_desktop_version (returns semver), _cai_sandbox_available (checks plugin), _cai_sandbox_feature_enabled (comprehensive check with error messaging).
## Evidence
- Commits: 3c96078, 52e9132, 161b9a8, 10605b8, ccfc0cf
- Tests: bash -c 'source agent-sandbox/containai.sh && _cai_docker_desktop_version', bash -c 'source agent-sandbox/containai.sh && _cai_sandbox_available', bash -c 'source agent-sandbox/containai.sh && _containai_check_docker', bash -c 'source agent-sandbox/containai.sh && _containai_check_isolation'
- PRs:
