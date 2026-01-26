# fn-21-5sw.1 Add test job and gate release on test success

## Description
Add test jobs to `.github/workflows/build-sysbox.yml` that validate the built sysbox deb packages work correctly before release. Test both amd64 and arm64 using native runners.

**Size:** M
**Files:** `.github/workflows/build-sysbox.yml`

## Approach

1. **Add `test-amd64` job**
   - Runs on `ubuntu-latest`
   - Downloads built artifact from `sysbox-ce-amd64`

2. **Add `test-arm64` job**
   - Runs on `ubuntu-24.04-arm` (native ARM64 runner, no QEMU)
   - Downloads built artifact from `sysbox-ce-arm64`

3. **Install kernel headers** (both jobs)
   - Try `linux-headers-$(uname -r)` first
   - Fall back to `linux-headers-azure` (GitHub runners use Azure kernels)
   - Pattern:
     ```bash
     sudo apt-get update
     sudo apt-get install -y linux-headers-$(uname -r) || \
       sudo apt-get install -y linux-headers-azure || \
       echo "::warning::Kernel headers unavailable, some sysbox features may not work"
     ```

4. **Install built deb**
   - Follow pattern from `src/lib/setup.sh:3421-3424`:
     ```bash
     sudo DEBIAN_FRONTEND=noninteractive apt-get install ./sysbox-ce*.deb -y || \
       sudo apt-get install -f -y
     ```

5. **Verify sysbox services**
   - Check `systemctl is-active sysbox-mgr` and `systemctl is-active sysbox-fs`
   - Show `sysbox-runc --version` for logging
   - Show `docker info | grep -i runtime` to confirm sysbox-runc registered

6. **Run DinD smoke test**
   - Pull `nestybox/ubuntu-focal-systemd-docker:latest`
   - Start with `docker run --runtime=sysbox-runc -d --name=test-dind`
   - Poll for inner dockerd readiness (up to 60s)
   - Run `docker exec test-dind docker run --rm hello-world`
   - Cleanup container

7. **Update release job**
   - Change `needs: build` to `needs: [build, test-amd64, test-arm64]`

## Key Context

- **Native ARM64 runner**: `ubuntu-24.04-arm` is free for public repos (preview since Jan 2025). No QEMU needed.
- **Kernel headers for Azure**: GitHub runners use custom Azure kernels. `linux-headers-$(uname -r)` may fail, use `linux-headers-azure` fallback.
- **DEBIAN_FRONTEND**: Required to avoid apt prompts (pitfall from `.flow/memory/pitfalls.md:174`).
- **Service timing**: sysbox services start immediately after deb install; no explicit restart needed.
## Approach

1. **Add `test-amd64` job** after build job completes
   - Runs on `ubuntu-22.04` (same as build)
   - Downloads built artifact from `sysbox-ce-amd64`
   - Follow pattern from existing workflow's artifact upload/download

2. **Verify runner prerequisites**
   - Check kernel version >= 5.12 (GitHub runners have 6.x, should pass)
   - Check systemd is PID 1 (`cat /proc/1/comm` should be `systemd`)
   - Fail fast with clear error if requirements not met

3. **Install built deb**
   - Follow pattern from `src/lib/setup.sh:3421-3424`:
     ```bash
     sudo apt-get update
     sudo apt-get install -y jq
     sudo DEBIAN_FRONTEND=noninteractive apt-get install ./sysbox-ce*.deb -y || \
       sudo apt-get install -f -y
     ```

4. **Verify sysbox services**
   - Check `systemctl is-active sysbox-mgr` and `systemctl is-active sysbox-fs`
   - Show `sysbox-runc --version` for logging
   - Show `docker info | grep -i runtime` to confirm sysbox-runc is registered

5. **Run DinD smoke test**
   - Pull `nestybox/ubuntu-focal-systemd-docker:latest`
   - Start with `docker run --runtime=sysbox-runc -d --name=test-dind`
   - Poll for inner dockerd readiness (up to 60s)
   - Run `docker exec test-dind docker run --rm hello-world`
   - Cleanup container

6. **Update release job**
   - Change `needs: build` to `needs: [build, test-amd64]`
   - Release only happens if tests pass

## Key Context

- **Kernel headers NOT needed**: Sysbox uses existing kernel features, not kernel modules. Do not add `linux-headers-*` installation.
- **ARM64 skip**: Only test amd64. QEMU emulation doesn't support sysbox kernel features. arm64 build still happens, just no functional test.
- **Service timing**: sysbox services start immediately after deb install; no explicit restart needed.
- **DEBIAN_FRONTEND**: Required to avoid apt prompts (pitfall from `.flow/memory/pitfalls.md:174`).
## Acceptance
- [ ] test-amd64 job runs on `ubuntu-latest`, installs deb, verifies services
- [ ] test-arm64 job runs on `ubuntu-24.04-arm` (native), installs deb, verifies services
- [ ] Both test jobs install kernel headers with Azure fallback
- [ ] Both test jobs run DinD smoke test (nested hello-world)
- [ ] Release job requires `needs: [build, test-amd64, test-arm64]`
- [ ] Clear error messages if sysbox services fail to start
- [ ] Test output visible in GitHub Actions logs
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
