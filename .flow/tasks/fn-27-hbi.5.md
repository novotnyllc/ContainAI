# fn-27-hbi.5 Sysbox packaging fuse3 dependency fix

## Description
Fix custom sysbox deb package to depend on fuse3 instead of fuse (fuse2). Currently sysbox-fs expects fusermount3 but package only depends on fuse.

**Size:** S
**Files:** `scripts/build-sysbox.sh`, `.github/workflows/build-sysbox.yml`

## Approach

1. **Update deb control file** - Modify build script to add fuse3 dependency:
   - Change `Depends:` line to include `fuse3` (or `fuse3 | fuse` for transitional)
   - Note: fuse3 `Breaks:` and `Replaces:` fuse, so they can't coexist

2. **Add CI validation** - Update workflow to verify:
   - `dpkg -s sysbox-ce` shows fuse3 in dependencies
   - `command -v fusermount3` present after install

## Key context

- fuse3 is in Debian stable since Buster (widely available)
- Use `Depends: fuse3` (hard requirement) since sysbox-fs requires fusermount3
- Container Dockerfile at `src/container/Dockerfile.base:54-55` has fuse but not fuse3
## Acceptance
- [ ] Custom sysbox deb package depends on fuse3
- [ ] `dpkg -s sysbox-ce` shows fuse3 in Depends line
- [ ] `command -v fusermount3` present after sysbox install
- [ ] sysbox-fs starts without manual `apt install fuse3`
- [ ] CI validates fuse3 dependency in built package
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
