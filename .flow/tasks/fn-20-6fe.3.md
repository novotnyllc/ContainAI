# fn-20-6fe.3 Add integration test for DinD with runc 1.3.3+

## Description

Add an integration test that validates Docker-in-Docker works correctly with runc 1.3.3+ when using the ContainAI sysbox build. This ensures the openat2 fix is functioning correctly.

**Size:** S
**Files:**
- `tests/integration/test-dind-runc133.sh` (new file - integration test)

## Approach

1. **Test setup**:
   - Verify sysbox is installed with ContainAI build (check version suffix or openat2 in binary)
   - Verify inner runc version is >= 1.3.3

2. **Test cases**:
   - Start container with sysbox-runc runtime
   - Run `docker run hello-world` inside the container
   - Run `docker build` inside the container (buildx/buildkit)
   - Verify no "unsafe procfs detected" errors

3. **Verification**:
   - Check that container starts successfully
   - Check that inner Docker operations complete
   - Check stdout/stderr for error patterns

4. **Test structure** (follow existing pattern from `tests/integration/`):
   - Source common test utilities
   - Define test functions
   - Report pass/fail with clear messages

## Key context

- Existing integration tests in `tests/integration/test-secure-engine.sh`, `tests/integration/test-dind.sh`
- Error to avoid: "unsafe procfs detected: openat2 /proc/./sys/net/ipv4/ip_unprivileged_port_start: invalid cross-device link"
- Test should use `--runtime=sysbox-runc` explicitly

## Acceptance

- [ ] Test script exists at `tests/integration/test-dind-runc133.sh`
- [ ] Test validates runc version >= 1.3.3
- [ ] Test runs `docker run` inside sysbox container successfully
- [ ] Test runs `docker build` inside sysbox container successfully
- [ ] Test fails with clear message if openat2 error occurs
- [ ] Test follows existing integration test patterns

## Done summary
Added integration test test-dind-runc133.sh that validates Docker-in-Docker works correctly with runc 1.3.3+ when using the ContainAI sysbox build with openat2 fix. The test verifies sysbox build markers, enforces runc >= 1.3.3, and checks that docker run/build operations succeed without "unsafe procfs detected" errors.
## Evidence
- Commits: 835a91ad9ac8ea5bc6cc7a1c29c42a83bd68b67a, b454d5fadee097077cb0a1ea957c697ad2e924a6
- Tests: shellcheck -x tests/integration/test-dind-runc133.sh
- PRs:
