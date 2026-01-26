# Add CI Testing to build-sysbox.yml

## Overview

Enhance the `build-sysbox.yml` GitHub Actions workflow to include comprehensive testing before releasing sysbox deb packages. Currently the workflow builds packages but does not verify they work.

**Problem**: Built sysbox packages are released without functional verification, risking broken releases.

**Solution**: Add test jobs for both amd64 and arm64 that install the built deb, verify sysbox services start, and run a Docker-in-Docker nested container test.

## Scope

**In scope:**
- Add test jobs for both architectures using native runners
  - amd64: `ubuntu-latest`
  - arm64: `ubuntu-24.04-arm` (native ARM64 runner)
- Install kernel headers (`linux-headers-$(uname -r)` or `linux-headers-azure` fallback)
- Verify sysbox services (sysbox-mgr, sysbox-fs) start correctly
- Run DinD test: start sysbox container, run nested hello-world
- Gate release job on test success

**Out of scope:**
- Running sysbox's full bats test suite (too slow, requires privileged containers)
- Self-hosted runners

## Approach

1. **Use native runners for both architectures**
   - amd64: `ubuntu-latest` (currently ubuntu-24.04)
   - arm64: `ubuntu-24.04-arm` (native ARM64, no QEMU needed)

2. **Install kernel headers**
   - Try `linux-headers-$(uname -r)` first
   - Fall back to `linux-headers-azure` if exact version unavailable (GitHub Azure kernels)
   - This enables sysbox's kernel header mounting feature for containers

3. **Add test jobs** - Separate from build, downloads artifact, tests on matching architecture

4. **Gate release** - Add `needs: [build, test-amd64, test-arm64]` to release job

### Job Structure
```
build (matrix: amd64, arm64)
  ├── test-amd64 (needs: build, runs on ubuntu-latest)
  └── test-arm64 (needs: build, runs on ubuntu-24.04-arm)
        └── release (needs: [build, test-amd64, test-arm64])
```

### Key Implementation Points

- **Kernel headers**: Install for sysbox's kernel-header-in-container feature
  ```bash
  sudo apt-get install -y linux-headers-$(uname -r) || \
    sudo apt-get install -y linux-headers-azure
  ```
- **Deb installation**: Use `sudo apt-get install ./sysbox-ce*.deb -y` with `-f` fallback
- **Service verification**: Check `systemctl is-active sysbox-mgr sysbox-fs`
- **DinD test**: Use `nestybox/ubuntu-focal-systemd-docker` image with `--runtime=sysbox-runc`
- **Nested container**: `docker exec <container> docker run hello-world`

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Kernel headers unavailable on GitHub runners | Medium | Medium | Fallback to `linux-headers-azure` metapackage |
| ARM64 runner queue times (preview) | Medium | Low | Document in workflow, acceptable for release gates |
| DinD test times out | Low | Medium | Set 5-minute timeout, poll for dockerd readiness |
| Tests add significant CI time | Medium | Low | Smoke test only (not full bats suite), expect ~3-5 min per arch |

## Acceptance Criteria

- [ ] Test job for amd64 installs deb, verifies services, runs DinD test
- [ ] Test job for arm64 installs deb, verifies services, runs DinD test (native runner)
- [ ] Kernel headers installed (with fallback for Azure kernels)
- [ ] Release job only runs if both test jobs pass
- [ ] Clear error messages if sysbox services fail to start
- [ ] Test logs visible in GitHub Actions output

## Quick Commands

```bash
# Run the workflow manually
gh workflow run build-sysbox.yml

# Check workflow runs
gh run list --workflow=build-sysbox.yml

# View test job logs
gh run view <run-id> --log --job=<test-job-id>

# Local simulation of test steps
docker run --runtime=sysbox-runc -d --name=test-dind nestybox/ubuntu-focal-systemd-docker:latest
sleep 30
docker exec test-dind docker run hello-world
docker rm -f test-dind
```

## References

- Current workflow: `.github/workflows/build-sysbox.yml`
- Existing DinD test pattern: `tests/integration/test-dind-runc133.sh:107-113`
- Sysbox installation pattern: `src/lib/setup.sh:3421-3424`
- Sysbox test kernel headers: `sysbox/tests/helpers/installer.bash:105`
- GitHub ARM64 runners: github.blog/changelog/2025-01-16-linux-arm64-hosted-runners
- GitHub runner kernel info: github.com/actions/runner-images (ubuntu uses Azure kernel)
- nestybox/sysbox#973: runc 1.3.3+ compatibility (why we build custom sysbox)
