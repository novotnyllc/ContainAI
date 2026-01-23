# fn-11-1an.1 Add symlink detection and path mapping helper

## Description
Add POSIX-compliant helper functions for symlink detection and path mapping within the rsync container script.

**Size:** S
**Files:** `src/lib/import.sh` (within POSIX sh script block, lines 731-936)

## Approach

Add these functions inside the existing POSIX sh script heredoc:

1. `is_internal_absolute_symlink()` - Check if absolute symlink target is within the host source subtree
   - Takes: `host_src_dir`, `link_path`
   - Use `readlink "$link_path"` to get target
   - If target starts with `/` (absolute): check if it starts with `$host_src_dir`
   - If target is relative: return false (we don't relink relative symlinks)
   - Return 0 (true) if internal absolute, 1 otherwise

2. `remap_absolute_symlink()` - Calculate new container-absolute target path
   - Takes: `host_src_dir`, `runtime_dst_dir`, `link_path`
   - Get target via `readlink "$link_path"`
   - Strip `$host_src_dir` prefix, prepend `$runtime_dst_dir`
   - Validate result starts with `$runtime_dst_dir` (security check)
   - Echo the new target path

3. `symlink_target_exists_in_source()` - Check if symlink target exists in mounted source
   - Takes: `host_src_dir`, `source_mount`, `link_path`
   - Get target via `readlink "$link_path"`
   - **Map host path to source mount**: `src_target="${source_mount}${target#$host_src_dir}"`
   - Test: `test -e "$src_target" || test -L "$src_target"`
   - Return 0 if exists, 1 if broken
   - **Critical**: We test against `/source` mount, not the host path (which isn't accessible in container)

## Key context

- Script runs as POSIX sh, not bash - no arrays, no `[[ ]]`, use `[ ]` tests
- `readlink` is available in eeacms/rsync container (returns raw target, not resolved)
- **Only handle absolute symlinks** - relative symlinks remain unchanged
- `HOST_SRC_DIR` is the **host path** (e.g., `/host/dotfiles/.config`), not `/source`
- `RUNTIME_DST_DIR` is `/mnt/agent-data/$dst_key` (container runtime path)
- For existence checks: map `$host_src_dir/foo` → `/source/foo` since host paths aren't mounted
- `readlink` does NOT fail on circular symlinks - it returns the immediate target
- We only call `readlink` once (no recursive resolution), so no infinite loop risk

## Acceptance
- [ ] `is_internal_absolute_symlink()` returns true for absolute symlinks within host_src_dir
- [ ] `is_internal_absolute_symlink()` returns false for relative symlinks (no relinking)
- [ ] `is_internal_absolute_symlink()` returns false for absolute symlinks outside host_src_dir
- [ ] `remap_absolute_symlink()` correctly transforms paths: `$host_src_dir/foo` → `$runtime_dst_dir/foo`
- [ ] `remap_absolute_symlink()` validates result stays under `$runtime_dst_dir`
- [ ] `symlink_target_exists_in_source()` maps host path to `/source` mount before testing
- [ ] `symlink_target_exists_in_source()` returns false for broken symlinks
- [ ] Functions are POSIX sh compliant (no bashisms)

## Done summary
# Task fn-11-1an.1: Add symlink detection and path mapping helpers

## Summary

Added three POSIX-compliant helper functions for symlink detection and path mapping within the rsync container script (`src/lib/import.sh`). These functions will be used by the future `relink_internal_symlinks` function (task fn-11-1an.2) to correctly handle absolute symlinks during import.

## Changes

**File: `src/lib/import.sh` (lines 910-1003)**

Added three helper functions inside the POSIX sh script heredoc:

1. **`is_internal_absolute_symlink(host_src_dir, link_path)`**
   - Returns 0 (true) if symlink is absolute AND target is within host_src_dir
   - Returns 1 (false) for relative symlinks or external absolute symlinks
   - Uses case/esac pattern matching for POSIX compliance

2. **`remap_absolute_symlink(host_src_dir, runtime_dst_dir, link_path)`**
   - Transforms host paths to container runtime paths
   - Includes security checks for path traversal attempts (`/../`)
   - Belt-and-suspenders validation that result stays under runtime_dst_dir
   - Outputs new target path to stdout

3. **`symlink_target_exists_in_source(host_src_dir, source_mount, link_path)`**
   - Maps host paths to source mount for existence checks
   - Returns 0 if target exists (file, dir, or symlink)
   - Returns 1 for broken symlinks

## Verification

- All functions tested with both `bash --posix` and `dash` (strict POSIX sh)
- All 9 test cases pass:
  - Internal absolute symlinks correctly identified
  - External absolute symlinks correctly rejected
  - Relative symlinks correctly skipped
  - Path transformation works for files and directories
  - Path traversal attempts rejected
  - Existence checks map to source mount correctly
  - Broken symlinks detected
- `shellcheck -x` passes (1 false positive for \n in heredoc context)
- `import.sh` sources successfully
## Evidence
- Commits:
- Tests: {'name': 'is_internal_absolute_symlink returns true for internal absolute', 'status': 'pass'}, {'name': 'is_internal_absolute_symlink returns false for external absolute', 'status': 'pass'}, {'name': 'is_internal_absolute_symlink returns false for relative symlinks', 'status': 'pass'}, {'name': 'remap_absolute_symlink transforms paths correctly (file)', 'status': 'pass'}, {'name': 'remap_absolute_symlink transforms paths correctly (dir)', 'status': 'pass'}, {'name': 'remap_absolute_symlink rejects path traversal attempts', 'status': 'pass'}, {'name': 'symlink_target_exists_in_source returns true for existing target', 'status': 'pass'}, {'name': 'symlink_target_exists_in_source returns false for broken symlink', 'status': 'pass'}, {'name': 'symlink_target_exists_in_source works for directories', 'status': 'pass'}
- PRs:
