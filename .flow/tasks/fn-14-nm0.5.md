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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
