# fn-21-5sw.1 Add test job and gate release on test success

## Description
Add test jobs to `.github/workflows/build-sysbox.yml` that validate the built sysbox deb packages work correctly before release. Test both amd64 and arm64 using native runners.

**Size:** M
**Files:** `.github/workflows/build-sysbox.yml`

## Approach

1. **Add `test-amd64` job**
   - Runs on `ubuntu-latest` (currently Ubuntu 24.04)
   - `needs: build` - waits for all matrix jobs to complete
   - Downloads built artifact from `sysbox-ce-amd64`
   - Timeout: 10 minutes

2. **Add `test-arm64` job**
   - Runs on `ubuntu-24.04-arm` (native ARM64 runner, no QEMU)
   - `needs: build` - waits for all matrix jobs to complete
   - Downloads built artifact from `sysbox-ce-arm64`
   - Timeout: 10 minutes

3. **Attempt kernel headers installation** (both jobs, best-effort)
   - Try `linux-headers-$(uname -r)` first
   - Fall back to `linux-headers-azure` (GitHub runners use Azure kernels)
   - If both fail, emit `::warning::` and continue (not fatal)
   - Pattern:
     ```bash
     sudo apt-get update
     sudo apt-get install -y linux-headers-$(uname -r) || \
       sudo apt-get install -y linux-headers-azure || \
       echo "::warning::Kernel headers unavailable, some sysbox features may not work"
     ```

4. **Install built deb**
   - Use dpkg + apt-get -f pattern (matches `src/lib/setup.sh:3421-3424`):
     ```bash
     sudo DEBIAN_FRONTEND=noninteractive dpkg -i ./sysbox-ce*.deb || true
     sudo DEBIAN_FRONTEND=noninteractive apt-get install -f -y
     ```

5. **Verify sysbox services** (with retry loop)
   - Wait up to 30s for services to become active
   - Check `systemctl is-active sysbox-mgr` and `systemctl is-active sysbox-fs`
   - On failure, dump diagnostics:
     - `systemctl status sysbox-mgr sysbox-fs --no-pager`
     - `journalctl -u sysbox-mgr -u sysbox-fs --no-pager -n 50`
   - Show `sysbox-runc --version` for logging
   - Show `docker info | grep -i runtime` to confirm sysbox-runc registered

6. **Run DinD smoke test**
   - Use pinned image: `nestybox/ubuntu-focal-systemd-docker:20240618` (stable)
   - Use unique container name: `test-dind-${{ github.run_id }}`
   - Start with `docker run --runtime=sysbox-runc -d --name=test-dind-${{ github.run_id }}`
   - Poll for inner dockerd readiness (up to 60s)
   - Run `docker exec <container> docker run --rm hello-world`
   - On failure, dump diagnostics:
     - `docker logs <container>`
     - `docker exec <container> systemctl status docker.service --no-pager || true`
     - `docker exec <container> journalctl -u docker.service --no-pager -n 30 || true`
   - Cleanup container (always runs)

7. **Update release job**
   - Change `needs: build` to `needs: [build, test-amd64, test-arm64]`
   - Release only runs if ALL tests pass

## Key Context

- **Native ARM64 runner**: `ubuntu-24.04-arm` is free for public repos (preview since Jan 2025). No QEMU needed for tests.
- **Kernel headers for Azure**: GitHub runners use custom Azure kernels. `linux-headers-$(uname -r)` may fail, use `linux-headers-azure` fallback. This is best-effort, not blocking.
- **DEBIAN_FRONTEND**: Required to avoid apt prompts (pitfall from `.flow/memory/pitfalls.md:174`).
- **Service timing**: sysbox services start asynchronously after deb install; use retry loop to wait for readiness.
- **Diagnostics on failure**: Dump systemctl status and journalctl logs to meet "clear error messages" acceptance criterion.
- **Tests run always**: Tests run on every workflow invocation (tag push or manual dispatch), not just when `create_release == true`. This ensures we catch issues even in build-only runs.

## Acceptance
- [ ] test-amd64 job runs on `ubuntu-latest`, installs deb, verifies services
- [ ] test-arm64 job runs on `ubuntu-24.04-arm` (native), installs deb, verifies services
- [ ] Both test jobs attempt kernel headers with Azure fallback (warning if unavailable)
- [ ] Both test jobs run DinD smoke test (nested hello-world)
- [ ] Release job requires `needs: [build, test-amd64, test-arm64]`
- [ ] Clear error messages if sysbox services fail to start (systemctl status + journalctl)
- [ ] Test output visible in GitHub Actions logs

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
