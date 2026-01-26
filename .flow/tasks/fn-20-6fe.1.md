# fn-20-6fe.1 Diagnose and fix current container runtime

## Description
Diagnose the current container's containerd.io/runc version and apply the fix to make `docker run` work immediately. Capture exact version strings for use in Dockerfile pinning.

**Size:** S
**Files:** None (runtime investigation and apt commands)

## Approach

1. Verify sysbox runtime:
   - Check for sysbox-fs mounts: `mount | grep sysbox`
   - Check container runtime from host: `docker inspect --format '{{.HostConfig.Runtime}}' <container>`
   - If inside container without host access, check `/proc/self/uid_map` for user namespace (non-trivial mapping indicates sysbox)

2. Check current versions:
   ```bash
   apt-cache policy containerd.io
   runc --version
   docker info | grep -E 'containerd|runc'
   ```

3. Find compatible containerd.io version:
   ```bash
   apt-cache madison containerd.io | head -20
   ```
   Look for 1.7.x versions that predate the runc 1.3.3 security patches.

4. Downgrade containerd.io with proper flags:
   ```bash
   sudo systemctl stop docker containerd
   sudo apt-get install -y --allow-downgrades containerd.io=<exact-version>
   sudo systemctl start containerd docker
   ```

5. Verify fix:
   ```bash
   runc --version  # Should show < 1.3.3
   docker run --rm alpine:latest echo "success"
   ```

6. Document exact version string for Dockerfile update.

## Key context

- The container is built from `src/container/Dockerfile.base` and runs with sysbox-runc
- dockerd is managed by systemd (containai-init.service runs before docker.service)
- The exact apt package version for Ubuntu Noble includes a suffix like `~ubuntu.24.04~noble`
- Both containerd and docker services need restart after downgrade
- Document the exact version string AND the runc version it bundles for Task 2

## Acceptance
- [ ] Sysbox runtime confirmed (via mount check or uid_map inspection)
- [ ] Current containerd.io version documented
- [ ] Current runc version documented (shows >= 1.3.3 causing the issue)
- [ ] Compatible containerd.io version identified from apt-cache madison
- [ ] containerd.io downgraded with `--allow-downgrades`
- [ ] Both containerd and docker services restarted
- [ ] Post-downgrade runc version confirmed < 1.3.3
- [ ] `docker run --rm alpine:latest echo hello` succeeds
- [ ] Exact apt package version string documented for Dockerfile update
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
