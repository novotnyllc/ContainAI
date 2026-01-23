# fn-11-1an.2 Implement symlink relinking in rsync copy script

## Description
Integrate symlink relinking into the rsync copy script's post-sync phase.

**Size:** M
**Files:** `src/lib/import.sh` (lines 731-936, POSIX sh script block)

## Approach

### 1. Pass HOST_SOURCE_ROOT to container script

Add a new environment variable `HOST_SOURCE_ROOT` that contains the `--from` directory path (normalized). This is set when constructing the heredoc:

```sh
# In _import_sync_from_directory(), before heredoc:
HOST_SOURCE_ROOT="$(cd "$from_source" && pwd)"  # Normalize path
```

### 2. Compute per-entry paths inside copy()

Each SYNC_MAP entry has `_src` (e.g., `/source/.config`) and `_dst` (e.g., `/target/config`). Derive per-entry host/runtime paths:

```sh
copy() {
    _src="$1"
    _dst="$2"
    ...

    # Derive per-entry paths for symlink relinking
    # _src is /source/relative_path, strip /source to get relative
    _rel_path="${_src#/source}"
    _host_src_dir="${HOST_SOURCE_ROOT}${_rel_path}"
    _runtime_dst_dir="/mnt/agent-data${_dst#/target}"

    rsync ... "$_src/" "$_dst/"

    # Only relink if HOST_SOURCE_ROOT is set (skip for default import)
    [ -n "$HOST_SOURCE_ROOT" ] && relink_internal_symlinks "$_host_src_dir" "$_runtime_dst_dir" "$_src" "$_dst"
}
```

### 3. Add `relink_internal_symlinks()` function

After rsync completes copying files, add a symlink fixup pass:

```sh
relink_internal_symlinks() {
    _host_src_dir="$1"
    _runtime_dst_dir="$2"
    _source_dir="$3"
    _target_dir="$4"

    # POSIX-safe iteration with find -exec
    find "$_target_dir" -type l -exec sh -c '
        host_src="$1"; runtime_dst="$2"; src_dir="$3"; shift 3
        for link do
            target=$(readlink "$link" 2>/dev/null) || continue

            # Skip relative symlinks (they remain unchanged)
            case "$target" in
                /*) ;; # absolute, continue
                *) continue ;;
            esac

            # Check if internal (target starts with host_src_dir)
            case "$target" in
                "$host_src"*)
                    rel_target="${target#$host_src}"

                    # SECURITY: Reject paths with .. segments to prevent escape
                    case "$rel_target" in
                        */../*|*/..)
                            printf "[WARN] %s -> %s (path escape attempt, skipped)\n" "$link" "$target" >&2
                            continue
                            ;;
                    esac

                    # Map host path to source mount for existence check
                    src_target="${src_dir}${rel_target}"

                    # Skip if broken (target does not exist in source)
                    if ! test -e "$src_target" && ! test -L "$src_target"; then
                        printf "[WARN] %s -> %s (broken, preserved)\n" "$link" "$target" >&2
                        continue
                    fi

                    # Remap to runtime path
                    new_target="${runtime_dst}${rel_target}"

                    # Security: validate stays under runtime_dst (belt-and-suspenders)
                    case "$new_target" in
                        "$runtime_dst"*) ;;
                        *) printf "[WARN] %s -> %s (escape attempt, skipped)\n" "$link" "$new_target" >&2; continue ;;
                    esac

                    # Relink (rm first for directory symlink pitfall)
                    rm -rf "$link"
                    ln -s "$new_target" "$link"
                    printf "[RELINK] %s -> %s\n" "$link" "$new_target" >&2
                    ;;
                *)
                    # External absolute symlink
                    printf "[WARN] %s -> %s (outside entry subtree, preserved)\n" "$link" "$target" >&2
                    ;;
            esac
        done
    ' sh "$_host_src_dir" "$_runtime_dst_dir" "$_source_dir" {} +
}
```

## Key context

- `HOST_SOURCE_ROOT` is set once from `--from` argument (normalized with `cd && pwd`)
- **Guard**: Only run relinking if `HOST_SOURCE_ROOT` is set (empty = default import, skip relinking)
- Per-entry `_host_src_dir` and `_runtime_dst_dir` are computed inside `copy()` from `_src`/`_dst`
- Pitfall at `.flow/memory/pitfalls.md:26`: `ln -sfn` to directories needs `rm -rf` first
- **Security**: Reject `rel_target` containing `/../` or `/..` to prevent path escape attacks
- Must be POSIX sh compliant - use `[ ]` not `[[ ]]`, case statements for pattern matching
- Log all outcomes: `[RELINK]`, `[WARN] ... (broken)`, `[WARN] ... (outside entry subtree)`, `[WARN] ... (path escape)`
- `readlink` does NOT fail on circular symlinks - returns immediate target, we only call once

## Acceptance
- [ ] `HOST_SOURCE_ROOT` env var passed to container script (from `--from` argument)
- [ ] Guard: relinking skipped if `HOST_SOURCE_ROOT` is empty
- [ ] Per-entry `_host_src_dir`/`_runtime_dst_dir` computed inside `copy()` function
- [ ] Absolute symlinks pointing within entry subtree are relinked after rsync
- [ ] Relinked symlinks use `/mnt/agent-data/...` runtime prefix
- [ ] Relative symlinks are NOT relinked (preserved as-is, no log)
- [ ] External absolute symlinks preserved with `[WARN] ... (outside entry subtree)` log
- [ ] Broken symlinks preserved with `[WARN] ... (broken, preserved)` log
- [ ] **Security**: Paths with `/../` or `/..` rejected with `[WARN] ... (path escape)` log
- [ ] Directory symlinks handled correctly (rm -rf before ln -s)
- [ ] POSIX-safe iteration (find -exec, not find | while read)

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
