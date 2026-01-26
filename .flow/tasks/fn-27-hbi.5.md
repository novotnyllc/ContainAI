# fn-27-hbi.5 Sysbox packaging fuse3 dependency fix

## Description
Fix custom sysbox deb package to depend on fuse3 instead of fuse (fuse2). Currently sysbox-fs expects fusermount3 but package only depends on fuse.

**Size:** S
**Files:** `scripts/build-sysbox.sh`, `.github/workflows/build-sysbox.yml`

## Approach

1. **Identify control file path** - The sysbox-pkgr builds deb packages using templates:
   - Control file is at `sysbox-pkgr/deb/templates/sysbox-ce/DEBIAN/control` (or similar path in cloned repo)
   - Need to patch this before running `make -C deb generic`

2. **Update local build script** - Modify `scripts/build-sysbox.sh` in `build_sysbox_deb()` function (line 296):
   - After setting up sysbox-pkgr sources (line 330-332), add sed patch:
   ```bash
   # Patch control template to add fuse3 dependency
   find "$pkgr_dir/deb" -name control -exec sed -i 's/^Depends:/Depends: fuse3,/' {} \;
   ```
   - This adds `fuse3,` to the beginning of the Depends line

3. **Update CI workflow** - Modify `.github/workflows/build-sysbox.yml`:
   - Add same sed patch step before the make command
   - Add validation step after build:
   ```bash
   dpkg-deb -I <deb> | grep -q "fuse3" || exit 1
   ```

4. **Add CI validation** - After installing the built deb in the workflow:
   - Verify `dpkg -s sysbox-ce` shows fuse3 in Depends
   - Verify `command -v fusermount3` succeeds

## Key context

- fuse3 is in Debian stable since Buster (widely available on all supported distros)
- Use `Depends: fuse3` as hard requirement since sysbox-fs requires fusermount3
- Container Dockerfile at `src/container/Dockerfile.base:54-55` has fuse but not fuse3 (separate concern)
- sysbox-pkgr is cloned during build at line 315 of build script

## Acceptance
- [ ] Custom sysbox deb package depends on fuse3
- [ ] `dpkg-deb -I <deb>` shows fuse3 in Depends line
- [ ] `command -v fusermount3` present after sysbox install
- [ ] sysbox-fs starts without manual `apt install fuse3`
- [ ] CI validates fuse3 dependency in built package using dpkg-deb
- [ ] Both local build script and CI workflow patched consistently

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
