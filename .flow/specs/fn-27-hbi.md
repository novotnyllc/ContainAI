# ContainAI Reliability Pack

## Overview

Five reliability improvements addressing sysbox/docker update safety, volume ownership repair, packaging fixes, SSH execution reliability, and cross-platform update mechanisms.

**Source PRD:** `.flow/specs/prd-reliability.md`

## Scope

1. **Safe Sysbox/Docker Update Flow** - Stop containers before updates, add systemd hooks
2. **Data Volume Repair via cai doctor** - Add `--repair` flag mode for id-mapped mount corruption (Linux/WSL2 only)
3. **Sysbox Packaging fuse3 Dependency** - Fix custom sysbox deb to depend on fuse3
4. **SSH/Shell Reliability** - Fix TTY allocation, ensure interactive shell, reliable detached mode
5. **Cross-Platform Sysbox Updates** - Fix WSL2 early-return, Lima/macOS VM updates

## Quick commands

```bash
# Verify update flow
cai update --dry-run

# Test doctor repair (Linux/WSL2 only)
cai doctor --repair --dry-run

# Test SSH shell reliability
cai shell  # Should always open interactive shell

# Verify sysbox version detection
cai doctor | grep -i sysbox
```

## Approach

### Task 1: Safe Update Flow + Systemd Hooks
- Modify `_cai_update_linux_wsl2()` to check for running containers before sysbox/docker updates or unit template changes
- Add `--stop-containers` and `--dry-run` flags to `cai update`
- **Default behavior when updates needed + containers running**: abort with actionable message (list containers, suggest `--stop-containers`)
- Keep existing `--force` semantics (skip confirmation prompts, NOT skip container stop)
- Add systemd ExecStopPre to containai-docker.service unit to stop containers on service stop/restart
- Use existing `_containai_list_containers_for_context()` and `_containai_stop_all()` from `src/lib/container.sh`
- Key files: `src/lib/update.sh`, `src/lib/docker.sh:442-493`, `src/lib/container.sh`

### Task 2: Cross-Platform Sysbox Update Mechanism
- Fix `_cai_install_sysbox_wsl2()` early-return at `src/lib/setup.sh:896-901`
- Verify update success using full package version (`sysbox-runc --version` output), not just semver (handles same-semver ContainAI rebuilds)
- Ensure `_cai_update_macos()` updates sysbox inside Lima VM (not just VM recreation)
- Add `_cai_lima_sysbox_version()` to query sysbox version inside Lima VM
- Reuse `_cai_sysbox_needs_update()` from `src/lib/setup.sh:555`
- Add Lima sysbox version reporting to `cai doctor` on macOS
- Key files: `src/lib/setup.sh`, `src/lib/update.sh`, `src/lib/doctor.sh`

### Task 3: Data Volume Ownership Repair (Linux/WSL2 only)
- Add `cai doctor --repair [--container <id>] [--all] [--dry-run]` flag mode (not subcommand)
- **Platform scope**: Linux and WSL2 only; on macOS, print "repair not supported on macOS" and exit
- Update arg parsing in `src/containai.sh:_containai_doctor_cmd()` to accept `--repair` flags
- Define "managed volumes" as volumes attached to containers with label `containai.managed=true`
- Detect id-mapped ownership corruption (files owned by nobody:nogroup)
- Auto-detect UID/GID from running container or fallback to 1000:1000
- Constrain repair to `/var/lib/containai-docker/volumes` only
- Key files: `src/containai.sh`, `src/lib/doctor.sh`

### Task 4: SSH/Shell Reliability
- Ensure `cai shell` always allocates TTY (`-tt` flag)
- Fix detached mode to confirm command started before exiting (return PID, verify with kill -0)
- Use `bash -lc` for consistent command parsing (bash available in ContainAI containers)
- Key files: `src/lib/ssh.sh:1727-1738`, `src/lib/ssh.sh:2081-2094`

### Task 5: Sysbox Packaging fuse3 Fix
- Patch sysbox-pkgr control file template to add `Depends: fuse3` before running make
- Update both `scripts/build-sysbox.sh` and `.github/workflows/build-sysbox.yml` to apply patch
- Add CI validation using `dpkg-deb -I <deb>` to verify fuse3 dependency in built package
- Key files: `scripts/build-sysbox.sh`, `.github/workflows/build-sysbox.yml`

### Task 6: Documentation Updates
- Update `docs/setup-guide.md` with update process
- Update `docs/troubleshooting.md` with repair flag mode (note Linux/WSL2 only)
- Update `CHANGELOG.md`

## Acceptance

- [ ] `cai update` warns if containers running and updates needed, aborts with actionable message
- [ ] `cai update --stop-containers` safely stops then updates
- [ ] Systemd stop/restart of containai-docker stops ContainAI containers via ExecStopPre
- [ ] `cai doctor --repair --all` repairs id-mapped volumes for labeled containers (Linux/WSL2)
- [ ] `cai doctor --repair` on macOS prints "not supported" and exits cleanly
- [ ] `cai shell` always opens interactive shell with TTY
- [ ] Sysbox updates work on WSL2, Linux, and macOS/Lima
- [ ] `cai doctor` reports correct sysbox version on macOS (via Lima)
- [ ] Custom sysbox deb depends on fuse3

## References

- PRD: `.flow/specs/prd-reliability.md`
- Current update code: `src/lib/update.sh`
- Doctor module: `src/lib/doctor.sh`
- Doctor command parsing: `src/containai.sh:1338`
- SSH module: `src/lib/ssh.sh`
- Container helpers: `src/lib/container.sh` (`_containai_list_containers_for_context`, `_containai_stop_all`)
- Sysbox install: `src/lib/setup.sh:813-993` (WSL2), `src/lib/setup.sh:3364-3544` (Linux)
- Systemd unit template: `src/lib/docker.sh:442-493`

## Dependencies

- Extends fn-25-81w (Sysbox version checking)
- Extends fn-15-281 (ContainAI-managed dockerd bundle)
- Extends fn-10-vep (Systemd container lifecycle)
