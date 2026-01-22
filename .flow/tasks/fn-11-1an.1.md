# fn-11-1an.1 Add symlink detection and path mapping helper

## Description
Add POSIX-compliant helper functions for symlink detection and path mapping within the rsync container script.

**Size:** S
**Files:** `src/lib/import.sh` (within POSIX sh script block, lines 731-936)

## Approach

Add these functions inside the existing POSIX sh script heredoc:

1. `is_internal_symlink()` - Check if symlink target is within source root
   - Use `readlink` to get target
   - Compare with source root prefix
   - Handle both relative and absolute symlinks

2. `remap_symlink_target()` - Calculate new target path
   - Take source root, target root, and symlink target as inputs
   - Return transformed path with source prefix replaced by target prefix

## Key context

- Script runs as POSIX sh, not bash - no arrays, no `local` in older sh
- `readlink` and `realpath` are available in eeacms/rsync container
- For relative symlinks: resolve to absolute first, remap, then convert back to relative
## Acceptance
- [ ] `is_internal_symlink()` correctly identifies symlinks pointing within source tree
- [ ] `is_internal_symlink()` returns false for symlinks pointing outside source tree
- [ ] `remap_symlink_target()` correctly transforms absolute symlink targets
- [ ] `remap_symlink_target()` correctly transforms relative symlink targets
- [ ] Functions are POSIX sh compliant (no bashisms)
- [ ] Functions handle edge cases: broken symlinks, circular refs (return early, don't loop)
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
