# fn-11-1an.3 Add symlink relinking to dry-run output

## Description
Add symlink relinking preview to `--dry-run` output so users can see what symlinks will be relinked.

**Size:** S
**Files:** `src/lib/import.sh` (dry-run handling within POSIX sh script block)

## Approach

### Key insight: dry-run scans SOURCE, not TARGET

In dry-run mode, `rsync --dry-run` does NOT create symlinks in `/target`. Therefore, we must:
- Scan symlinks in the **source** subtree (`/source/...`)
- Simulate what would be relinked without touching `/target`

### 1. Add `preview_symlink_relinks()` function

```sh
preview_symlink_relinks() {
    _host_src_dir="$1"
    _runtime_dst_dir="$2"
    _source_dir="$3"

    # Scan symlinks in SOURCE (not target, since dry-run doesn't create files)
    find "$_source_dir" -type l -exec sh -c '
        host_src="$1"; runtime_dst="$2"; src_dir="$3"; shift 3
        for link do
            target=$(readlink "$link" 2>/dev/null) || continue

            # Relative symlinks: no change
            case "$target" in
                /*) ;; # absolute, continue checking
                *) continue ;; # relative symlinks not relinked, skip silently
            esac

            # Check if internal absolute
            case "$target" in
                "$host_src"*)
                    rel_target="${target#$host_src}"

                    # Reject paths with .. segments (security)
                    case "$rel_target" in
                        */../*|*/..) printf "[WARN] %s -> %s (path escape attempt, skipped)\n" "$link" "$target" >&2; continue ;;
                    esac

                    # Check if target exists in source (map host path to source mount)
                    src_target="${src_dir}${rel_target}"
                    if ! test -e "$src_target" && ! test -L "$src_target"; then
                        printf "[WARN] %s -> %s (broken, would be preserved)\n" "$link" "$target" >&2
                        continue
                    fi

                    # Would be relinked
                    new_target="${runtime_dst}${rel_target}"
                    printf "[RELINK] %s -> %s\n" "$link" "$new_target" >&2
                    ;;
                *)
                    # External absolute
                    printf "[WARN] %s -> %s (outside entry subtree, would be preserved)\n" "$link" "$target" >&2
                    ;;
            esac
        done
    ' sh "$_host_src_dir" "$_runtime_dst_dir" "$_source_dir" {} +
}
```

### 2. Call in dry-run code path inside copy()

Use the same per-entry variables as fn-11-1an.2, computed inside `copy()`:

```sh
copy() {
    _src="$1"
    _dst="$2"
    ...

    # Derive per-entry paths (same as fn-11-1an.2)
    _rel_path="${_src#/source}"
    _host_src_dir="${HOST_SOURCE_ROOT}${_rel_path}"
    _runtime_dst_dir="/mnt/agent-data${_dst#/target}"

    if [ "$DRY_RUN" = "1" ]; then
        rsync --dry-run ...
        # Preview symlink relinks (scan source since dry-run doesn't create files)
        [ -n "$HOST_SOURCE_ROOT" ] && preview_symlink_relinks "$_host_src_dir" "$_runtime_dst_dir" "$_src"
    else
        rsync ...
        [ -n "$HOST_SOURCE_ROOT" ] && relink_internal_symlinks "$_host_src_dir" "$_runtime_dst_dir" "$_src" "$_dst"
    fi
}
```

### 3. Output format

- `[RELINK]` prefix for symlinks that would be relinked
- `[WARN] ... (outside entry subtree, would be preserved)` for external symlinks
- `[WARN] ... (broken, would be preserved)` for broken symlinks
- Relative symlinks are skipped silently (they're preserved unchanged, no action needed)

## Key context

- Dry-run mode: rsync doesn't create files in `/target`, so scan `/source` instead
- **Use same per-entry variables as fn-11-1an.2**: `_host_src_dir`, `_runtime_dst_dir` computed inside `copy()`
- Must check existence in source (same as real run) to avoid false `[RELINK]` for broken symlinks
- Guard: only run if `HOST_SOURCE_ROOT` is set (skip for default import path)

## Acceptance
- [ ] `--dry-run` shows symlinks that would be relinked (`[RELINK]`)
- [ ] `--dry-run` shows warnings for external symlinks (`[WARN] ... outside entry subtree`)
- [ ] `--dry-run` shows warnings for broken symlinks (`[WARN] ... broken, would be preserved`)
- [ ] Relative symlinks skipped silently (no output, they remain unchanged)
- [ ] Uses same per-entry `_host_src_dir`/`_runtime_dst_dir` as fn-11-1an.2
- [ ] Scans SOURCE directory (not TARGET, since rsync dry-run doesn't create files)
- [ ] Guarded: only runs if `HOST_SOURCE_ROOT` is set
- [ ] No actual changes made during dry-run

## Done summary
Added preview_symlink_relinks() function to show symlink relinking preview during dry-run mode. The function scans source directory (not target, since rsync dry-run doesn't create files), outputs [RELINK] for symlinks that would be relinked, [WARN] for external/broken symlinks, and silently skips relative symlinks. Respects .system/ exclusion (x flag) and includes belt-and-suspenders validation for new_target path.
## Evidence
- Commits: 9d5bc6ef52e5da20d17aa9f5308f7a26cc61a2cd, cc8146bdb8e904a39bab906fd3411fb26452218b
- Tests: bash -n src/lib/import.sh, shellcheck -x src/lib/import.sh
- PRs:
