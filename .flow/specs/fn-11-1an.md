# Symlink Relinking During Import

## Overview

When importing from a directory (`cai import --from <dir>`), symlinks that point to locations within the import source are preserved as-is by rsync. This means symlinks end up pointing to the original host paths instead of the new container paths, resulting in broken or incorrectly-targeted symlinks.

**Example (single SYNC_MAP entry):**
- Host: `/host/dotfiles/.config/nvim` → symlink to `/host/dotfiles/.config/nvim.d` (both within `.config` subtree)
- After import without relinking: `/mnt/agent-data/config/nvim` → still points to `/host/dotfiles/.config/nvim.d` (wrong!)
- After relinking: `/mnt/agent-data/config/nvim` → `/mnt/agent-data/config/nvim.d` (correct!)

**Definition:** "Internal symlink" means a symlink whose target is within the **same SYNC_MAP entry's subtree** (per-entry scope, not global import scope).

## Scope

**In scope:**
- Symlinks within sync-mode imports (`--from <dir>`)
- **Absolute symlinks only** whose targets are within the SYNC_MAP entry's source subtree
- Relative symlinks are preserved unchanged (they remain relative and typically work correctly)
- Warning/logging for symlinks pointing outside the entry's subtree

**Out of scope:**
- Archive restore mode (tgz) - symlinks intentionally rejected for security
- Symlinks pointing outside the SYNC_MAP entry's subtree (cannot be reliably relinked)
- Cross-SYNC_MAP symlink relinking (e.g., `.claude/` linking to `.config/` - complex, defer to future)
- Relinking relative symlinks (they naturally adapt to new location)
- Default import path (no `--from` argument) - `HOST_SOURCE_ROOT` empty, relinking skipped

## Quick commands

```bash
# Run integration tests for import
./tests/integration/test-sync-integration.sh

# Check symlinks in volume
docker run --rm -v containai-data:/data alpine find /data -type l -exec ls -la {} \;
```

## Acceptance

- [ ] Absolute symlinks within the SYNC_MAP entry subtree are relinked to container paths
- [ ] Relative symlinks are preserved unchanged (no relinking)
- [ ] Relinked absolute symlinks use `/mnt/agent-data/...` prefix (runtime container path)
- [ ] Symlinks pointing outside entry subtree are preserved as-is with warning
- [ ] Broken symlinks (target doesn't exist in source) are preserved as-is (no error, no relinking)
- [ ] Circular symlink chains do not cause infinite loops (we only call `readlink` once per symlink, no recursive resolution)
- [ ] `--dry-run` shows symlinks that would be relinked (by scanning source, not target)
- [ ] Existing integration tests continue to pass
- [ ] New integration test validates symlink relinking

## Key Implementation Details

### Host path detection in container

The rsync container mounts sources at `/source` but symlink targets contain **host paths**. Pass `HOST_SOURCE_ROOT` env var and compute per-entry paths:

```sh
# Set once when building heredoc (only if --from <dir> provided):
HOST_SOURCE_ROOT="$(cd "$from_source" && pwd)"

# Inside copy(), for each SYNC_MAP entry (_src=/source/..., _dst=/target/...):
_rel_path="${_src#/source}"
_host_src_dir="${HOST_SOURCE_ROOT}${_rel_path}"     # e.g., /host/dotfiles/.config
_runtime_dst_dir="/mnt/agent-data${_dst#/target}"   # e.g., /mnt/agent-data/config

# Guard: only run relinking if HOST_SOURCE_ROOT is set
[ -n "$HOST_SOURCE_ROOT" ] && relink_internal_symlinks ...
```

### Existence checks map host → source mount

Symlink targets are host paths (e.g., `/host/dotfiles/.config/foo`), but the host isn't mounted. Map to `/source` mount for existence checks:

```sh
# For target="/host/dotfiles/.config/foo" and host_src_dir="/host/dotfiles/.config":
rel_target="${target#$host_src_dir}"           # /foo
src_target="${src_dir}${rel_target}"           # /source/.config/foo
test -e "$src_target"  # Now we can check existence
```

### POSIX-safe symlink iteration

Use `find -exec` (not `find | while read`) to handle paths with spaces:
```sh
find "$target_dir" -type l -exec sh -c '
    for link do
        # process $link safely
    done
' sh {} +
```

### No infinite loops on circular symlinks

We only call `readlink` once per symlink (which returns the immediate target). We do NOT recursively resolve symlinks or call `realpath`, so circular chains like `a→b→a` are harmless - each is processed independently with a single `readlink` call.

## Security

- Relinked symlinks MUST use `/mnt/agent-data/...` prefix (runtime path)
- **Path escape prevention**: Reject `rel_target` containing `/../` or `/..` segments before remapping
- Validate: transformed target must start with `$_runtime_dst_dir` (belt-and-suspenders check)
- Only relink if target exists in source (prevents creating new attack vectors)
- Guard: relinking only runs if `HOST_SOURCE_ROOT` is set (prevents accidental matching)
- Archive restore symlink rejection (`_import_restore_from_tgz`) remains unchanged

## References

- Import implementation: `src/lib/import.sh:464-967`
- SYNC_MAP entries: `src/lib/import.sh:348-408`
- POSIX sh copy script: `src/lib/import.sh:731-936`
- Symlink pitfall: `.flow/memory/pitfalls.md:26` (`ln -sfn` directory gotcha)
- Archive symlink rejection: `src/lib/import.sh:133-328`
- fn-9-mqv symlink limitation: `.flow/specs/fn-9-mqv.md:162-179`
