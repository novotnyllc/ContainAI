# fn-5-urz.12 Secure Engine runtime validation + integration tests

## Description
## Overview

Implement runtime validation for Secure Engine and comprehensive integration tests.

## Validation Functions

### _cai_secure_engine_validate()
```bash
# Verify Secure Engine is correctly configured
# 1. Context exists
docker context inspect containai-secure

# 2. Engine is reachable
docker --context containai-secure info

# 3. Runtime is sysbox-runc (or configured alternative)
docker --context containai-secure info --format '{{.DefaultRuntime}}'

# 4. User namespace is enabled
docker --context containai-secure run --rm alpine cat /proc/self/uid_map
# Should show mapped UIDs, not "0 0 4294967295"

# 5. Test container starts successfully
docker --context containai-secure run --rm hello-world
```

## Integration Tests

Create `test-secure-engine.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

section "Test 1: Context exists"
docker context inspect containai-secure || fail "Context not found"
pass "Context exists"

section "Test 2: Engine reachable"
docker --context containai-secure info || fail "Engine not reachable"
pass "Engine reachable"

section "Test 3: Runtime is sysbox-runc"
runtime=$(docker --context containai-secure info --format '{{.DefaultRuntime}}')
[[ "$runtime" == "sysbox-runc" ]] || fail "Expected sysbox-runc, got $runtime"
pass "Runtime correct"

section "Test 4: User namespace enabled"
uid_map=$(docker --context containai-secure run --rm alpine cat /proc/self/uid_map)
[[ "$uid_map" != *"0 0 4294967295"* ]] || fail "User namespace not enabled"
pass "User namespace enabled"

section "Test 5: Sandbox runs on Secure Engine"
# Updated by plan-sync: fn-5-urz.1 confirmed Sysbox context works, sandbox context UNKNOWN
# Sysbox context is confirmed working. Sandbox context pending Docker Desktop 4.50+ testing.
docker --context containai-secure sandbox run --help || warn "Sandbox context support pending Docker Desktop testing (see fn-5-urz.1)"
```

## Platform-Specific Tests

- WSL: Verify socket path, distro isolation
- macOS: Verify Lima VM status, socket path

## Reuse

- `test-sync-integration.sh` - test pattern with `section()`, `pass()`, `fail()`
## Acceptance
- [ ] `_cai_secure_engine_validate()` checks all 5 validation points
- [ ] Returns clear pass/fail status for each check
- [ ] `test-secure-engine.sh` runs all integration tests
- [ ] Tests work on WSL (if Secure Engine supported)
- [ ] Tests work on macOS with Lima
- [ ] Tests are idempotent (can run multiple times)
- [ ] Failed tests provide actionable remediation
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
