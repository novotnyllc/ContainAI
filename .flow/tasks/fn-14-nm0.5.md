# fn-14-nm0.5 Update cai doctor for isolated Docker

## Description
Update `cai doctor` to check the isolated ContainAI Docker instance instead of (or in addition to) system Docker.

**Size:** M
**Files:** `src/lib/doctor.sh`

## Current State

`cai doctor` (`doctor.sh:274-293`) checks Docker but may be checking system Docker paths. Need to verify it checks the isolated instance.

## Approach

1. Check that `containai-docker.service` is running (not `docker.service`)
2. Verify socket exists at `$_CAI_CONTAINAI_DOCKER_SOCKET`
3. Verify context `$_CAI_CONTAINAI_DOCKER_CONTEXT` exists and points to correct socket
4. Test Docker connectivity via isolated socket
5. Verify Sysbox runtime available in isolated daemon

**Pattern to follow:** Existing doctor checks in `doctor.sh`, extend for isolated Docker

**Reuse:**
- `_cai_ok`, `_cai_warn`, `_cai_error` logging functions
- Existing Docker check structure
## Acceptance
- [ ] `cai doctor` checks `containai-docker.service` status
- [ ] `cai doctor` verifies socket at `$_CAI_CONTAINAI_DOCKER_SOCKET`
- [ ] `cai doctor` verifies context `$_CAI_CONTAINAI_DOCKER_CONTEXT`
- [ ] `cai doctor` tests Docker API via isolated socket
- [ ] `cai doctor` verifies sysbox-runc runtime in isolated daemon
- [ ] Clear error messages when isolation is misconfigured
## Done summary
## Summary

Added explicit `containai-docker.service` systemd status check to `cai doctor` command on Linux/WSL2 platforms.

### Changes

1. **New helper functions in `docker.sh`:**
   - `_cai_containai_docker_service_active()` - Checks if systemd service is active
   - `_cai_containai_docker_service_exists()` - Checks if systemd unit is installed

2. **Updated `_cai_doctor()` text output:**
   - Shows service status as first item in ContainAI Docker section on Linux/WSL2
   - Displays [OK] active, [ERROR] inactive/failed, [NOT INSTALLED], or [SKIP] for non-systemd

3. **Updated `_cai_doctor_json()` JSON output:**
   - Added `service_name`, `service_exists`, `service_active`, `service_state` fields
   - Fields only included on Linux/WSL2 (not macOS)

### Verification

All acceptance criteria met:
- ✅ Checks `containai-docker.service` status
- ✅ Verifies socket at `$_CAI_CONTAINAI_DOCKER_SOCKET`
- ✅ Verifies context `$_CAI_CONTAINAI_DOCKER_CONTEXT`
- ✅ Tests Docker API via isolated socket
- ✅ Verifies sysbox-runc runtime in isolated daemon
- ✅ Clear error messages when isolation is misconfigured
## Evidence
- Commits:
- Tests: {'type': 'manual', 'description': 'cai doctor shows service status', 'result': 'pass'}, {'type': 'lint', 'description': 'shellcheck -x src/lib/docker.sh src/lib/doctor.sh', 'result': 'pass'}, {'type': 'manual', 'description': 'cai doctor --json outputs valid JSON with service fields', 'result': 'pass'}
- PRs:
