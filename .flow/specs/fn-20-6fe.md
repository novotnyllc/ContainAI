# Fix Docker-in-Docker runc 1.3.3 Incompatibility via Custom Sysbox Build

## Problem

Docker run fails inside sysbox containers with error:
```
OCI runtime create failed: runc create failed: unable to start container process:
error during container init: open sysctl net.ipv4.ip_unprivileged_port_start file:
unsafe procfs detected: openat2 /proc/./sys/net/ipv4/ip_unprivileged_port_start:
invalid cross-device link
```

## Root Cause

runc 1.3.3 added security checks using `openat2()` with `RESOLVE_NO_XDEV` flag to detect "fake procfs". This conflicts with sysbox-fs which bind-mounts FUSE-backed files over `/proc/sys/*` paths.

## Fix Status (Verified)

**The fix exists in sysbox master but is NOT in any released version.**

| Component | Version | Status |
|-----------|---------|--------|
| sysbox v0.6.7 (released) | 2025-05-09 | Does NOT have the fix |
| sysbox-fs master | 2025-11-29 | Contains the openat2 fix |

**Fix commits in sysbox-fs:**
- `1302a6f` (2025-11-18): "Trap openat2 system call to allow access to sysbox-fs mounts under /proc and /sys"
- `2882cce` through `b70bd38`: Follow-up improvements and hardening

The fix uses seccomp syscall interception to trap `openat2()` calls, detect paths under sysbox-fs mounts, strip problematic flags (`RESOLVE_NO_XDEV`, `RESOLVE_NO_MAGICLINKS`, `RESOLVE_NO_SYMLINKS`, `RESOLVE_BENEATH`), and inject the file descriptor back into the process.

## Ownership Clarification

**ContainAI owns both host and container sides:**
- Setup scripts (`src/lib/setup.sh`) install sysbox on the host
- The `_cai_install_sysbox_wsl2()` and `_cai_install_sysbox_linux()` functions download and install sysbox from GitHub releases
- ContainAI can build and deploy custom sysbox packages

**Current sysbox installation pattern:**
```bash
# From src/lib/setup.sh - downloads from nestybox releases
release_url="https://api.github.com/repos/nestybox/sysbox/releases/latest"
download_url=$(... | jq -r ".assets[] | select(.name | test(\"sysbox-ce.*${arch}.deb\")) | .browser_download_url")
```

## Approach: Build Custom Sysbox Package

Since ContainAI owns the host-side setup, the solution is to:

1. **Build sysbox from master** (which contains the fix)
2. **Publish custom deb package** to ContainAI's GitHub releases or package repository
3. **Update setup scripts** to use the custom package instead of upstream releases

This is preferred over the runc downgrade workaround because:
- It's the proper fix, not a workaround
- No security trade-offs from downgrading runc
- ContainAI has full control over the deployment

## Deliverables

1. **GitHub Actions workflow** (`scripts/build-sysbox.sh` + `.github/workflows/build-sysbox.yml`)
   - Builds sysbox-ce deb packages for amd64 and arm64
   - Uses sysbox's existing packaging infrastructure (`sysbox-pkgr`)
   - Publishes to GitHub releases with SHA256 checksums

2. **Setup script updates** (`src/lib/setup.sh`)
   - Add option to install from ContainAI's custom build
   - Fall back to upstream releases if custom build unavailable
   - Version pinning mechanism

3. **Documentation**
   - Build process documentation
   - Version tracking/update procedure

## Sysbox Build Process (Reference)

Based on analysis of `sysbox-pkgr/`:

```bash
# Clone sysbox with submodules
git clone --recursive https://github.com/nestybox/sysbox.git

# Build deb package (uses Docker)
cd sysbox-pkgr
make sysbox-ce-deb generic  # Builds generic deb for release

# Output: sysbox-ce_<version>.linux_<arch>.deb
```

Key build requirements:
- Docker (builds use containerized build environment)
- Ubuntu Jammy baseline for release builds
- Go 1.22+ toolchain (provided by build container)

## Acceptance

- [ ] GitHub Actions workflow builds sysbox deb for amd64 and arm64
- [ ] Built packages published to GitHub releases with SHA256 checksums
- [ ] Setup scripts updated to prefer ContainAI's custom sysbox build
- [ ] DinD works in sysbox containers with runc 1.3.3+
- [ ] Integration test validates the fix

## References

- [sysbox#973](https://github.com/nestybox/sysbox/issues/973) - Docker 28.5.2 breaks DinD on Sysbox
- [sysbox#972](https://github.com/nestybox/sysbox/issues/972) - Original bug report
- [runc v1.3.3](https://github.com/opencontainers/runc/releases/tag/v1.3.3) - Release with security patches
- sysbox-fs fix commit: `1302a6f` (2025-11-18)
