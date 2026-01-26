# fn-27-hbi.3 Data volume ownership repair via cai doctor --repair

## Description
Add data volume ownership repair functionality to `cai doctor` to fix id-mapped mount corruption after sysbox restarts.

**Size:** M
**Files:** `src/lib/doctor.sh`

## Approach

1. **Add repair subcommands** to `_cai_doctor()`:
   - `cai doctor --repair` - repair volumes for current/default container
   - `cai doctor --repair --container <id|name>` - repair specific container
   - `cai doctor --repair --all` - repair all managed volumes
   - `cai doctor --repair --dry-run` - show what would be repaired

2. **Detect id-mapped corruption** - Add `_cai_doctor_check_volume_ownership()`:
   - Check if files under volume are owned by `nobody:nogroup` (65534:65534)
   - Check if `/usr/bin/sudo` is not root-owned (indicates rootfs taint)

3. **UID/GID detection** - Add `_cai_doctor_detect_uid()`:
   - Running container: `docker exec id -u agent` / `id -g agent`
   - Stopped container: attempt detection, fallback 1000:1000 with warning

4. **Safe repair** - Add `_cai_doctor_repair_volume()`:
   - Only operate under `/var/lib/containai-docker/volumes`
   - Use `find ... -xdev` to prevent cross-filesystem traversal
   - Skip symlinks to prevent traversal attacks

## Key context

- Volume path constant at `src/lib/docker.sh:314`: `_CAI_CONTAINAI_DOCKER_DATA="/var/lib/containai-docker"`
- Existing `_cai_doctor_fix()` at line 1004 handles SSH fixes - add repair alongside
- Files showing `nobody:nogroup` indicate broken id-mapping (kernel issue after sysbox restart)
## Acceptance
- [ ] `cai doctor --repair --all` repairs ownership on all managed volumes
- [ ] `cai doctor --repair --container <name>` repairs specific container's volumes
- [ ] `cai doctor --repair --dry-run` shows what would be changed without changing
- [ ] Auto-detects UID/GID from running container
- [ ] Falls back to 1000:1000 with warning for stopped containers
- [ ] Repair constrained to `/var/lib/containai-docker/volumes` only
- [ ] Warns if rootfs tainted (suggests container recreation)
- [ ] No symlink traversal or cross-filesystem operations
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
