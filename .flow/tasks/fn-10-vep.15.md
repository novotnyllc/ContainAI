# fn-10-vep.15 Start dockerd and verify DinD works in sysbox

## Description
Verify that dockerd can start and run inside our current sysbox container without --privileged.

**Size:** S
**Files:** None (verification only)

## Context

We're already running in an ECI/sysbox container. The user confirmed:
- Sysbox containers can run dockerd natively
- No --privileged flag needed
- dockerd just isn't started yet

## Approach

1. Start dockerd with sysbox-compatible flags:
   ```bash
   sudo dockerd --iptables=false --ip-masq=false &
   ```

2. Wait for dockerd to be ready:
   ```bash
   timeout 30 bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'
   ```

3. Verify basic operations:
   - `docker info` shows daemon running
   - `docker run --rm alpine echo "test"` works
   - `docker build` works

4. Document what flags are needed/optional

## Key context

- Storage driver: Let dockerd auto-select (vfs may be required in some nested scenarios)
- Network: `--iptables=false --ip-masq=false` because NAT may not work in nested container
- Socket: Standard `/var/run/docker.sock` is fine (not running inside Dockerfile.test)
## Acceptance
- [ ] dockerd starts without --privileged flag
- [ ] `docker info` shows daemon running
- [ ] `docker run --rm alpine echo "nested works"` succeeds
- [ ] `docker build -t test - <<< "FROM alpine"` succeeds
- [ ] Document required/optional flags for sysbox DinD
## Done summary
**BLOCKED**: DinD does not work in this sysbox container due to missing capabilities.

### Findings:
1. **dockerd starts successfully** with flags: `--iptables=false --ip-masq=false --bridge=none --storage-driver=fuse-overlayfs`
2. **docker info works** - daemon is running
3. **docker run fails** - `unshare: operation not permitted`

### Root cause:
- Container is running under sysbox (confirmed via sysboxfs fuse mounts)
- Container lacks `CAP_SYS_ADMIN` capability (confirmed via `/proc/1/status`)
- Available capabilities: `cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_net_raw,cap_sys_chroot,cap_mknod,cap_audit_write,cap_setfcap`
- `unshare` syscall is blocked, preventing namespace creation required for containers

### Required for DinD to work:
- Container needs `CAP_SYS_ADMIN` capability OR
- Seccomp profile must allow `unshare` syscall OR
- Host kernel must allow unprivileged user namespaces

### Commands verified to work:
```bash
# Install docker-ce (only CLI was pre-installed)
sudo apt-get install -y docker-ce containerd.io fuse-overlayfs

# Start dockerd
sudo dockerd --iptables=false --ip-masq=false --bridge=none --storage-driver=fuse-overlayfs &

# Verify daemon running
docker info  # Works
```

### Commands that fail:
```bash
docker run --rm alpine echo "test"
# Error: unshare: operation not permitted

sudo unshare --user --map-root-user echo "test"
# Error: unshare failed: Operation not permitted
```

Blocked:
# Block Reason: fn-10-vep.15

## Summary
DinD does not work in this sysbox container due to missing kernel capabilities.

## Details
- The container is running under sysbox (confirmed via sysboxfs fuse mounts)
- dockerd starts successfully with flags: `--iptables=false --ip-masq=false --bridge=none --storage-driver=fuse-overlayfs`
- `docker info` works, showing daemon is running
- **docker run fails** with `unshare: operation not permitted`

## Root Cause
The container lacks `CAP_SYS_ADMIN` capability and/or has seccomp restrictions blocking the `unshare` syscall. This prevents creating new namespaces required for nested containers.

## Resolution Required
The sysbox container must be started with:
- `CAP_SYS_ADMIN` capability, OR
- Modified seccomp profile allowing `unshare`, OR
- Host kernel configured to allow unprivileged user namespaces

This is a container orchestration/deployment configuration issue that cannot be fixed from within the container.
## Evidence
- Commits: None (verification only task)
- Tests: N/A
- PRs: N/A

## Blocker
This task is blocked on container configuration. The sysbox container must be started with additional capabilities for DinD to work. This is outside the scope of what can be fixed from within the container.
