# fn-27-hbi.3 Data volume ownership repair via cai doctor --repair

## Description
Add data volume ownership repair functionality to `cai doctor` to fix id-mapped mount corruption after sysbox restarts. Linux/WSL2 only.

**Size:** M
**Files:** `src/containai.sh`, `src/lib/doctor.sh`

## Approach

1. **Platform check** - Repair is Linux/WSL2 only:
   - On macOS: print "Volume repair is not supported on macOS (volumes are inside Lima VM)" and exit 0
   - This keeps the command clean without complex Lima execution paths

2. **Update arg parsing** in `src/containai.sh:_containai_doctor_cmd()` (line 1338):
   - Add `--repair` flag to enable repair mode
   - Add `--container <id|name>` option for specific container
   - Add `--all` flag to repair all managed volumes
   - Add `--dry-run` flag for preview mode
   - Update help text in `_containai_doctor_help()` at line 484

3. **Add repair functions** to `src/lib/doctor.sh`:
   - `_cai_doctor_repair()` - main entry point for repair mode
   - `_cai_doctor_check_volume_ownership()` - detect nobody:nogroup (65534:65534) ownership
   - `_cai_doctor_detect_uid()` - get UID/GID from container or fallback 1000:1000
   - `_cai_doctor_repair_volume()` - perform safe chown

4. **Define "managed volumes"**:
   - Query containers with label `containai.managed=true` via `docker --context containai-docker ps -a --filter label=containai.managed=true`
   - Inspect mounts to get volume names
   - Only repair volumes attached to labeled containers

5. **Safe repair implementation**:
   - Only operate under `/var/lib/containai-docker/volumes`
   - Use `find ... -xdev` to prevent cross-filesystem traversal
   - Use `-not -type l` to skip symlinks (prevent traversal attacks)
   - TOCTOU mitigation: use `chown -h` and validate path prefix

## Key context

- Volume path constant at `src/lib/docker.sh:314`: `_CAI_CONTAINAI_DOCKER_DATA="/var/lib/containai-docker"`
- Existing `_cai_doctor_fix()` at line 1004 handles SSH fixes - add repair alongside
- Files showing `nobody:nogroup` indicate broken id-mapping (kernel issue after sysbox restart)
- Label constant: `_CONTAINAI_LABEL` at `src/lib/container.sh:59`

## Acceptance
- [ ] `cai doctor --repair` on macOS prints "not supported" message and exits cleanly (exit 0)
- [ ] `cai doctor --repair --all` repairs ownership on volumes for labeled containers (Linux/WSL2)
- [ ] `cai doctor --repair --container <name>` repairs specific container's volumes
- [ ] `cai doctor --repair --dry-run` shows what would be changed without changing
- [ ] Auto-detects UID/GID from running container
- [ ] Falls back to 1000:1000 with warning for stopped containers
- [ ] Repair constrained to `/var/lib/containai-docker/volumes` only
- [ ] Warns if rootfs tainted (suggests container recreation)
- [ ] No symlink traversal or cross-filesystem operations
- [ ] Arg parsing updated in src/containai.sh with proper help text

## Done summary
Added `cai doctor --repair` for fixing volume ownership corruption after sysbox restarts. Linux/WSL2 only - macOS prints "not supported" and exits cleanly. Supports `--all` or `--container <name>` with optional `--dry-run`. Auto-detects UID/GID from running containers, constrained to `/var/lib/containai-docker/volumes`, warns if rootfs is tainted.
## Evidence
- Commits: c80710f, 91948c7, 4f689b0
- Tests: shellcheck -x src/containai.sh src/lib/doctor.sh, bash -n src/containai.sh, bash -n src/lib/doctor.sh, source src/containai.sh && _containai_doctor_help, source src/containai.sh && _containai_doctor_cmd --repair --all
- PRs:
