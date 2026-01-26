# fn-27-hbi.2 Cross-platform sysbox update mechanism (WSL2, Linux, Lima)

## Description
Fix sysbox update mechanism to work correctly on WSL2, native Linux, and Lima/macOS. Currently WSL2 has an early-return bug preventing upgrades. Also add Lima sysbox version reporting to cai doctor.

**Size:** M
**Files:** `src/lib/setup.sh`, `src/lib/update.sh`, `src/lib/doctor.sh`

## Approach

1. **Fix WSL2 early-return** - Remove early return at `src/lib/setup.sh:896-901` in `_cai_install_sysbox_wsl2()`:
   - Currently returns if sysbox exists, preventing upgrades
   - Add version checking using `_cai_sysbox_needs_update()` from line 555
   - Only skip if installed version >= bundled version

2. **Verify update success correctly** - Use full `sysbox-runc --version` output, not just semver:
   - ContainAI builds may have same semver as upstream but different build markers
   - Compare raw version string or check for ContainAI-specific marker in version output
   - Don't fail spuriously when upgrading from upstream to ContainAI build with same semver

3. **Ensure Linux update path checks versions** - Verify `_cai_install_sysbox_linux()` at line 3364 uses version comparison:
   - Reuse `_cai_sysbox_installed_version()` and `_cai_sysbox_bundled_version()`

4. **Fix Lima/macOS sysbox update** - Modify `_cai_update_macos()` at `src/lib/update.sh:1102-1217`:
   - Add `_cai_lima_sysbox_version()` to query sysbox version inside Lima VM via `limactl shell`
   - Compare Lima VM's sysbox version against bundled version
   - Add explicit sysbox update inside Lima VM when needed (copy .deb, install via dpkg)
   - Don't require full VM recreation for sysbox-only updates

5. **Add Lima sysbox version to doctor** - Modify `src/lib/doctor.sh`:
   - On macOS, use `limactl shell <vm> sysbox-runc --version` to get VM's sysbox version
   - Display this in doctor output alongside other version info

## Key context

- Version comparison must use `sort -V` for semver (see pitfalls.md)
- `_cai_sysbox_needs_update()` already exists at `src/lib/setup.sh:555` - reuse it
- Lima VM runs its own sysbox instance - update must happen inside VM
- Current doctor.sh skips sysbox version on macOS - needs explicit Lima probe
- ContainAI sysbox builds may have `+containai` suffix or different build metadata

## Acceptance
- [ ] `cai update` upgrades sysbox on WSL2 when newer bundled version exists
- [ ] `cai update` upgrades sysbox on native Linux when newer bundled version exists
- [ ] `cai update` on macOS updates sysbox inside Lima VM when needed
- [ ] `cai doctor` reports correct sysbox version on all platforms (including macOS via Lima)
- [ ] No early-return when sysbox exists but is outdated
- [ ] Version comparison uses semver logic (sort -V), not string equality
- [ ] Update verification handles same-semver ContainAI rebuilds correctly (use full version string)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
