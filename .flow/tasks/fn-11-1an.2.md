# fn-11-1an.2 Implement symlink relinking in rsync copy script

## Description
Integrate symlink relinking into the rsync copy script's post-sync phase.

**Size:** M
**Files:** `src/lib/import.sh` (lines 731-936, POSIX sh script block)

## Approach

After rsync completes copying files, add a symlink fixup pass:

1. Add `relink_symlinks()` function that:
   - Uses `find "$target_dir" -type l` to locate all symlinks
   - For each symlink, calls `is_internal_symlink()` from task 1
   - If internal: relinks using `remap_symlink_target()` and `ln -sfn`
   - If external: logs warning, preserves as-is

2. Call `relink_symlinks()` after each rsync in the `copy()` function
   - Pass source_dir and target_dir from the copy context

## Key context

- Pitfall at `.flow/memory/pitfalls.md:26`: `ln -sfn` to directories needs `rm -rf` first
- Must be POSIX sh compliant
- Log relinked symlinks for visibility
- Security: validate relinked target stays under target_dir
## Acceptance
- [ ] Symlinks pointing within import tree are relinked after rsync
- [ ] Absolute symlinks are converted to container-absolute paths
- [ ] Relative symlinks remain relative after relinking
- [ ] Symlinks pointing outside import tree are preserved with warning log
- [ ] Directory symlinks handled correctly (rm -rf before ln -sfn if needed)
- [ ] Relinked symlinks resolve under target volume only (security check)
- [ ] No infinite loops on circular symlinks
- [ ] Broken symlinks preserved as-is
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
