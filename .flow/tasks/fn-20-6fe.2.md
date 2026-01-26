# fn-20-6fe.2 Update setup scripts to use ContainAI sysbox build

## Description

Update the ContainAI setup scripts to prefer installing sysbox from ContainAI's custom build (which includes the runc 1.3.3 fix) instead of upstream nestybox releases. Include fallback to upstream if custom build is unavailable.

**Size:** S
**Files:**
- `src/lib/setup.sh` (modify - sysbox installation functions)

## Approach

1. **Add ContainAI sysbox release detection**:
   - Check ContainAI GitHub releases for custom sysbox builds
   - Parse release assets for architecture-appropriate deb
   - Fall back to upstream nestybox releases if not found

2. **Update `_cai_install_sysbox_wsl2()` and `_cai_install_sysbox_linux()`**:
   - Add new download URL priority:
     1. `CAI_SYSBOX_URL` environment variable (explicit override)
     2. ContainAI releases (custom build with fix)
     3. Upstream nestybox releases (fallback)
   - Log which source is being used

3. **Version preference logic**:
   - ContainAI builds use version suffix `+containai.YYYYMMDD`
   - Prefer ContainAI build over same-version upstream
   - Allow `CAI_SYSBOX_VERSION` to pin specific version

4. **Verification**:
   - After install, verify sysbox-fs includes openat2 handler
   - Could grep sysbox-fs binary for "openat2" string or check version

## Key context

- Current installation uses: `https://api.github.com/repos/nestybox/sysbox/releases/latest`
- `_cai_install_sysbox_wsl2()` at `src/lib/setup.sh:466`
- `_cai_install_sysbox_linux()` at `src/lib/setup.sh:3028`
- Both functions already support `CAI_SYSBOX_VERSION` override
- Build produces: `sysbox-ce_<version>+containai.<date>.linux_<arch>.deb`

## Acceptance

- [ ] Setup scripts check ContainAI releases first
- [ ] Fallback to upstream releases works
- [ ] `CAI_SYSBOX_URL` override works
- [ ] Installation logs indicate source used
- [ ] Existing `CAI_SYSBOX_VERSION` override still works
- [ ] Both WSL2 and Linux paths updated

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
