# fn-20-6fe.1 Create GitHub Actions workflow for sysbox deb build

## Description

Create a build script and GitHub Actions workflow to build sysbox-ce deb packages from master (which contains the runc 1.3.3 fix). The workflow should build for both amd64 and arm64 architectures and publish to GitHub releases.

**Size:** M
**Files:**
- `scripts/build-sysbox.sh` (new file - build script)
- `.github/workflows/build-sysbox.yml` (new file - GitHub Actions workflow)

## Approach

1. **Create build script** (`scripts/build-sysbox.sh`):
   - Clone sysbox repo with all submodules
   - Use sysbox's existing packaging infrastructure (`sysbox-pkgr/`)
   - Build generic deb package using containerized build
   - Generate SHA256 checksums
   - Output versioned deb file: `sysbox-ce_<version>+containai.<date>.linux_<arch>.deb`

2. **Create GitHub Actions workflow**:
   - Trigger: manual dispatch + tag push
   - Matrix build for amd64 and arm64
   - Uses self-hosted runners or QEMU for cross-arch builds
   - Upload artifacts to GitHub releases
   - Include SHA256 checksums in release notes

3. **Build environment requirements** (from sysbox-pkgr analysis):
   - Docker (privileged mode for build)
   - Ubuntu Jammy baseline (RELEASE_BASELINE_IMAGE)
   - Go 1.22+ (provided by build container)
   - Kernel headers for build host

4. **Version scheme**:
   - Base: upstream version from sysbox `VERSION` file
   - Suffix: `+containai.YYYYMMDD` to indicate custom build
   - Example: `sysbox-ce_0.6.7+containai.20260126.linux_amd64.deb`

## Key context

- The fix for runc 1.3.3 is in sysbox-fs master (commit `1302a6f` and follow-ups)
- sysbox v0.6.7 (released 2025-05-09) does NOT have this fix
- sysbox-pkgr uses Docker-based builds with `dpkg-buildpackage`
- Build must work in GitHub Actions environment

## Acceptance

- [ ] `scripts/build-sysbox.sh` exists and can build sysbox deb locally
- [ ] `.github/workflows/build-sysbox.yml` exists and is valid
- [ ] Workflow builds for both amd64 and arm64
- [ ] Built debs include the openat2 fix (verifiable by checking sysbox-fs version)
- [ ] SHA256 checksums generated for each artifact
- [ ] Workflow can be manually triggered
- [ ] Documentation in script header explains usage

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
