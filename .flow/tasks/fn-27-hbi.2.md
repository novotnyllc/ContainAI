# fn-27-hbi.2 Cross-platform sysbox update mechanism (WSL2, Linux, Lima)

## Description
Fix sysbox update mechanism to work correctly on WSL2, native Linux, and Lima/macOS. Currently WSL2 has an early-return bug preventing upgrades.

**Size:** M
**Files:** `src/lib/setup.sh`, `src/lib/update.sh`

## Approach

1. **Fix WSL2 early-return** - Remove early return at `src/lib/setup.sh:896-901` in `_cai_install_sysbox_wsl2()`:
   - Currently returns if sysbox exists, preventing upgrades
   - Add version checking using `_cai_sysbox_needs_update()` from line 555
   - Only skip if installed version >= bundled version

2. **Ensure Linux update path checks versions** - Verify `_cai_install_sysbox_linux()` at line 3364 uses version comparison:
   - Reuse `_cai_sysbox_installed_version()` and `_cai_sysbox_bundled_version()`

3. **Fix Lima/macOS sysbox update** - Modify `_cai_update_macos()` at `src/lib/update.sh:1102-1217`:
   - Add explicit sysbox update inside Lima VM when needed
   - Don't require full VM recreation for sysbox-only updates
   - Check VM's sysbox version, not host

## Key context

- Version comparison must use `sort -V` for semver (see pitfalls.md)
- `_cai_sysbox_needs_update()` already exists at `src/lib/setup.sh:555` - reuse it
- Lima VM runs its own sysbox instance - update must happen inside VM
## Acceptance
- [ ] `cai update` upgrades sysbox on WSL2 when newer bundled version exists
- [ ] `cai update` upgrades sysbox on native Linux when newer bundled version exists
- [ ] `cai update` on macOS updates sysbox inside Lima VM when needed
- [ ] `cai doctor` reports correct sysbox version on all platforms
- [ ] No early-return when sysbox exists but is outdated
- [ ] Version comparison uses semver logic (sort -V), not string equality
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
