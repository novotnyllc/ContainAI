# fn-5-urz.5 ECI detection (uid_map + runtime check)

## Description
## Overview

Implement ECI (Enhanced Container Isolation) detection per Docker documentation methods.

## Functions to Implement

### _cai_eci_available()
```bash
# Check if Docker Business with ECI is available (not necessarily enabled)
# This requires checking Docker subscription tier
# May not be directly detectable - fall through to enabled check
```

### _cai_eci_enabled()
Two validation methods per Docker docs:

**Method 1: uid_map check**
```bash
docker run --rm alpine cat /proc/self/uid_map
# ECI active: "0 100000 65536" (root mapped to unprivileged)
# ECI inactive: "0 0 4294967295" (root is root)
```

**Method 2: runtime check**
```bash
# Start ephemeral container, inspect runtime
CID=$(docker run -d --rm alpine sleep 10)
docker inspect --format '{{.HostConfig.Runtime}}' "$CID"
# ECI active: "sysbox-runc"
# ECI inactive: "runc"
docker stop "$CID"
```

### _cai_eci_status()
```bash
# Returns: "enabled", "available_not_enabled", "not_available"
# Combines above checks into single status
```

## Edge Cases

- ECI enabled but container uses userns manually (false positive)
- ECI available but not enabled - provide enablement instructions
- Docker Business but ECI not enabled by admin

## Reuse

- `aliases.sh:91-126` - `_asb_check_isolation()` has uid_map check
- Refactor to use both methods for higher confidence

## References

- ECI docs: https://docs.docker.com/enterprise/security/hardened-desktop/enhanced-container-isolation/enable-eci/
## Acceptance
- [ ] uid_map check correctly parses isolation status
- [ ] Runtime check verifies sysbox-runc vs runc
- [ ] Both methods must agree for "enabled" status
- [ ] Ephemeral containers are cleaned up (no leak)
- [ ] Timeout handling if Docker hangs
- [ ] Clear status messages: "ECI enabled", "ECI available but not enabled", "ECI not available"
## Done summary
Implemented ECI (Enhanced Container Isolation) detection with dual validation methods (uid_map check and runtime check) that must agree for enabled status. Includes comprehensive error handling, timeout protection, and actionable status messages.
## Evidence
- Commits: 7274575, f84ddf9, a0a9914, 42601ae
- Tests: Manual testing via docker run commands
- PRs:
