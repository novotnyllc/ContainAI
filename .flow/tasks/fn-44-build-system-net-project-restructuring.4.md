# fn-44-build-system-net-project-restructuring.4 Enable sysbox in GitHub Actions for E2E tests

## Description
Configure GitHub Actions to run E2E tests with sysbox by running `install.sh` on the runner VM (just like a normal user would). GitHub Actions runners are raw VMs with passwordless sudo, not containers.

**Size:** M
**Files:**
- `.github/workflows/docker.yml` (update test job)
- `install.sh` (may need updates to work in CI context)

## Approach

1. **Run install.sh in CI**: The install script should detect that sysbox is needed and install/configure it. This tests the real installation path that users will follow.

2. **GitHub Actions runner context**:
   - Runners are VMs (ubuntu-latest, ubuntu-22.04), not containers
   - Have passwordless sudo
   - Can install kernel modules and system services
   - sysbox installation will work normally

3. **Test execution flow**:
   ```yaml
   - name: Install ContainAI (includes sysbox)
     run: ./install.sh

   - name: Run E2E tests
     run: ./tests/integration/test-dind.sh
   ```

4. **Architecture matrix**: Use appropriate runners for each arch (ubuntu-22.04 for amd64, ubuntu-24.04-arm for arm64).

## Key context

- GitHub-hosted runners have passwordless sudo
- Runners are fresh VMs, not containers - sysbox kernel module installation works
- Running install.sh validates the real user experience
- `build-sysbox.yml` already handles sysbox package building (can use those artifacts or upstream releases)
## Approach

1. **Install sysbox in workflow**: Use the sysbox deb packages from `build-sysbox.yml` artifacts or install from nestybox releases.

2. **Configure Docker with sysbox runtime**: Add sysbox-runc as a runtime option.

3. **Run E2E tests**: Execute `tests/integration/test-dind.sh` with sysbox runtime.

4. **Use matrix strategy** for architecture (amd64/arm64) following pattern from `build-sysbox.yml:484-597`.

## Key context

- GitHub-hosted runners have passwordless sudo (per user request)
- Sysbox requires kernel module loading (may need specific runner configuration)
- `build-sysbox.yml` already builds sysbox-ce deb packages for ubuntu-22.04 and ubuntu-24.04-arm
- E2E tests use `CONTAINAI_TEST_IMAGE` env var
- Test resource cleanup uses `containai.test=1` label
## Acceptance
- [ ] CI runs install.sh to set up the environment
- [ ] Sysbox installed and configured via install.sh (not manual steps)
- [ ] `tests/integration/test-dind.sh` runs successfully in CI
- [ ] E2E tests run on both amd64 and arm64
- [ ] Test artifacts collected on failure
- [ ] CI logs show sysbox runtime being used
- [ ] install.sh works in CI context (handles non-interactive mode)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
