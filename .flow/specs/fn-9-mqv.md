# Import Source Specification with tgz/Directory Support

## Overview

Extend `cai import` to support specifying an import source, enabling:
1. **Restore from tgz archive** - Direct extraction to volume (idempotent)
2. **Sync from directory** - rsync from arbitrary directory (not just `$HOME`)

Currently, import is hardcoded to sync from host `$HOME` via bind mount at `lib/import.sh:529-533`.

## Scope

**In scope:**
- `--from <path>` flag to specify source (tgz file or directory)
- Auto-detect source type (directory vs gzip archive)
- Idempotent tgz import (same result on repeated runs)
- Directory import reusing existing rsync mechanism with configurable source root

**Out of scope:**
- URL import (http/https)
- Stdin import (`--from -`)
- Encrypted/password-protected archives
- Mirror/delete mode for directory sync (keeps current non-destructive rsync behavior)

## Key Design Decisions

### Two Source Layouts

**Critical insight**: Host `$HOME` and tgz archives have different layouts:

| Source | Layout | Example Path |
|--------|--------|--------------|
| Host $HOME | Host paths | `~/.claude/settings.json` |
| tgz archive | Volume paths | `./claude/settings.json` |

**Implication**: tgz import is a **restore** operation that bypasses the entire sync pipeline (`_IMPORT_SYNC_MAP`, env import, post-transforms) and extracts directly to volume. Directory import uses existing rsync mechanism with configurable source root.

### Idempotency Definition

For tgz import, "idempotent with respect to the provided archive contents":
- **Same file content** - byte-for-byte identical
- **Same permissions** - mode preserved by tar
- **Timestamps** - preserved from archive (tar default behavior)

Running `cai import --data-volume vol --from backup.tgz` twice produces identical volume state.

### Path Handling for --from

The `--from` argument undergoes path normalization before use:

```bash
# Expand ~ and resolve to absolute path
from_path="${from_arg/#\~/$HOME}"  # Expand leading ~

# Validate parent directory exists before resolving
parent_dir="$(dirname "$from_path")"
if ! resolved_parent="$(cd "$parent_dir" 2>/dev/null && pwd)"; then
    _error "Invalid path: parent directory does not exist: $parent_dir"
    return 1
fi
from_path="$resolved_parent/$(basename "$from_path")"
```

This ensures consistent behavior with other CLI flags that expand `~` and resolve paths.

### Source Type Detection

Validate source existence first, then detect type:
```bash
# Early existence check (after path normalization)
if [ ! -e "$source" ]; then
    _error "Source not found: $source"
    return 1
fi

# Type-specific validation
if [ -d "$source" ]; then
    # Directory: check readable and traversable
    if [ ! -r "$source" ] || [ ! -x "$source" ]; then
        _error "Source directory not accessible: $source"
        return 1
    fi
    # directory mode
elif [ -f "$source" ]; then
    # File: check readable
    if [ ! -r "$source" ]; then
        _error "Source file not readable: $source"
        return 1
    fi
    # Validate as gzip-compressed tar
    if tar -tzf "$source" >/dev/null 2>&1; then
        # gzip-compressed tar archive (restore mode)
    else
        _error "Invalid archive: must be gzip-compressed tar (.tgz/.tar.gz)"
        return 1
    fi
else
    _error "Unsupported source type: must be directory or file"
    return 1
fi
```

This avoids dependency on `file` command and provides clear error messages.

### Prerequisites

Archive restore requires `tar` with gzip support on the host:

```bash
# Check tar availability before archive operations
if ! command -v tar >/dev/null 2>&1; then
    _error "tar command not found (required for --from <archive>)"
    return 1
fi
```

### Archive Safety

Before extraction, validate archive entries to prevent security issues. Use separate validation steps:

```bash
# Step 1: Get file names only (tar -tzf) and check for path traversal
# This handles filenames with spaces correctly
tar_names=$(tar -tzf "$archive" 2>/dev/null) || {
    _error "Failed to read archive: $archive"
    return 1
}

if echo "$tar_names" | grep -qE '(^/|(^|/)\.\.(/|$))'; then
    _error "Archive contains unsafe paths (absolute or parent traversal)"
    return 1
fi

# Step 2: Get verbose listing for type checking
# Filter to actual entry lines only (start with type char + permissions)
# Allow: regular files (-), directories (d), and tar metadata entries (x, g, L, K)
# Metadata entries are PAX headers (x/g) and GNU longname/link (L/K) - these are internal tar bookkeeping
tar_types=$(tar -tvzf "$archive" 2>/dev/null) || {
    _error "Failed to list archive contents: $archive"
    return 1
}

# Extract only entry lines (start with file type indicator + permissions pattern)
# Then check for disallowed types
entry_types=$(echo "$tar_types" | grep -E '^[a-z-]([r-][w-][xsStT-]){3}' | cut -c1)

# Allow: d (directory), - (regular file)
# Also allow metadata entries which appear as regular files but are tar internal
# Reject: l (symlink), h (hardlink), b (block), c (char), p (FIFO), s (socket)
if echo "$entry_types" | grep -qE '^[lhbcps]'; then
    _error "Archive contains disallowed entry types (only regular files and directories permitted)"
    _info "Symlinks, hardlinks, devices, FIFOs, and sockets are not allowed"
    return 1
fi
```

**Security posture**: Only regular files and directories are permitted. This rejects:
- Symlinks and hardlinks (potential traversal/overwrite attacks)
- Block/character devices (security risk when extracting as root)
- FIFOs and sockets (unexpected special files)

### Symlink Round-Trip Limitation

**Important**: Current `cai export` preserves symlinks if they exist in the volume. Archives containing symlinks will be rejected by `--from` restore.

**This is a known limitation**: If a volume contains symlinks, the export → import round-trip will fail:
```bash
# This may fail if volume contains symlinks:
cai export --data-volume vol -o backup.tgz
cai import --data-volume vol --from backup.tgz  # Error: symlinks not allowed
```

**Workarounds**:
1. **Remove symlinks before export**: Clean up the volume before creating the archive
2. **Use directory sync**: `cai import --from <dir>` handles symlinks via rsync
3. **Future enhancement**: Add `cai export --dereference` to follow symlinks

This limitation is intentional for security - symlinks in archives can be used for traversal attacks.

### Directory Sync Semantics

Directory import uses rsync **without** `--delete`:
- New files from source are copied
- Existing files in volume are updated if different (size or mtime mismatch)
- Files in volume not present in source are **preserved** (no deletion)

This matches current `cai import` behavior and is non-destructive.

### Transform Behavior with source_root

When `source_root` differs from `$HOME`, path rewriting transforms (`_IMPORT_HOST_PATH_PREFIX`) behavior:

| Scenario | Transform Behavior |
|----------|-------------------|
| `source_root == $HOME` (normalized) | Normal path rewriting (current behavior) |
| `source_root != $HOME` (normalized) | **Skip path rewriting with warning** |

**Path normalization**: Use `cd "$path" && pwd` to resolve `~/`, symlinks, and relative paths before comparison.

```bash
# Normalize paths for comparison
normalized_source=$(cd "$source_root" 2>/dev/null && pwd)
normalized_home=$(cd "$HOME" 2>/dev/null && pwd)

if [ "$normalized_source" != "$normalized_home" ]; then
    _warn "Skipping installPath transforms: source ($source_root) differs from \$HOME"
    _info "Config files may contain paths that need manual adjustment"
fi
```

**Rationale**: Path rewriting is designed to translate `$HOME`-relative paths in config files. When importing from a different directory, those paths may not make sense. Rather than guess, skip rewriting and warn the user.

### Env Import Behavior

Env import (`_containai_import_env`) remains **workspace-driven** regardless of `--from`:
- Env file resolution uses current workspace config (not source_root)
- This is intentional: env vars are workspace-specific, not source-specific
- The `--from` flag affects file sync source, not config/env resolution

For directory import with `--from`, only file syncing changes source; env import continues to use workspace config.

## Approach

### tgz Import (Restore Mode)

When `--from` points to a gzip-compressed tar archive:

1. Normalize `--from` path (expand `~`, resolve to absolute, validate parent exists)
2. Validate source file exists, is a file, and is readable (early check)
3. Validate archive integrity and safety:
   - Use `tar -tzf` for path names, check for absolute paths and `../` traversal
   - Use `tar -tvzf` (stdout only) for type checking, reject non-regular files/directories
4. **If `--dry-run`**: List archive contents and exit immediately (skip config/volume/Docker operations)
5. Resolve/create target volume
6. Clear target volume contents including dotfiles (`find /target -mindepth 1 -delete`)
7. Extract directly to volume via alpine container
8. **Return immediately** - skip env import and all post-sync transforms

**CLI gate**: Add `_CAI_RESTORE_MODE=1` flag when `--from` is an archive. Check this flag in `containai.sh` before calling `_containai_import_env` to skip env import.

**Dry-run behavior**: Archive dry-run short-circuits immediately after archive validation (step 4). It does not attempt config resolution, volume operations, or Docker context selection. This allows `--dry-run --from <tgz>` to work even without Docker or a valid workspace.

This provides a "pure restore" that is fully idempotent.

### Directory Import (Sync Mode)

When `--from` points to a directory:

1. Normalize `--from` path (expand `~`, resolve to absolute, validate parent exists)
2. Validate source directory exists, is readable (-r), and traversable (-x) (early check)
3. Plumb `source_root` parameter through `_containai_import` and transform helpers
4. Bind mount `source_root` (instead of hardcoded `$HOME`) as `/source` in container
5. Run existing rsync + SYNC_MAP mechanism reading from `/source`
6. Run post-transforms:
   - If `source_root == $HOME` (normalized): normal path rewriting
   - If `source_root != $HOME` (normalized): skip path rewriting with warning
7. Run env import (workspace-driven, ignores source_root - uses current workspace config)
8. Preserve `DOCKER_CONFIG` to avoid breaking Docker CLI operations

**Implementation detail**: Use env var `_CAI_SOURCE_ROOT` that defaults to `$HOME` when `--from` is unset. Pass through to sync and transform helpers.

### Flag Interactions

| Flag Combination | Behavior |
|------------------|----------|
| `--from <tgz>` | Restore mode, ignores `--no-excludes` (excludes don't apply to restore) |
| `--from <tgz> --dry-run` | List archive contents only; skips config, volume, and Docker operations |
| `--from <dir>` | Sync mode with rsync from directory |
| `--from <dir> --dry-run` | Rsync dry-run showing what would sync |
| `--from <dir> --no-excludes` | Sync without exclude patterns |

### Docker Desktop Considerations

For macOS/Windows with Docker Desktop, arbitrary `--from` directory paths must be within Docker's file-sharing configuration. Add preflight check for directory mode:

```bash
# Only for directory mode (archives are read directly, not mounted)
if [ -d "$source" ]; then
    if ! docker run --rm -v "$source:/test:ro" alpine:3.19 true 2>/dev/null; then
        _error "Cannot mount '$source' - ensure it's within Docker Desktop's file-sharing paths"
        _info "On macOS/Windows, add the path in Docker Desktop Settings > Resources > File Sharing"
        return 1
    fi
fi
```

**Note**: tgz files don't need this check - they're read directly by tar, not mounted.

## CLI Interface

Use existing flag-based interface (not positional volume):

```bash
# Restore from tgz archive
cai import --data-volume vol --from /path/to/backup.tgz

# Sync from directory (~ is expanded)
cai import --data-volume vol --from ~/other-configs/

# With dry-run (archive: list contents only, no Docker/config required)
cai import --from backup.tgz --dry-run

# Existing behavior unchanged (syncs from $HOME)
cai import --data-volume vol
```

## Quick Commands

```bash
# Test tgz restore (note: will fail if volume contains symlinks)
cai export --data-volume test-vol -o /tmp/backup.tgz
cai import --data-volume test-vol --from /tmp/backup.tgz

# Test directory sync (handles symlinks via rsync)
cai import --data-volume test-vol --from ~/other-configs/

# Dry-run to preview archive (no Docker/config required)
cai import --from backup.tgz --dry-run
```

## Acceptance Criteria

- [ ] `cai import --data-volume vol --from <path.tgz>` extracts archive to volume
- [ ] `--from` path is normalized (~ expanded, resolved to absolute)
- [ ] Invalid `--from` path (non-existent parent) produces clear error message
- [ ] Missing `tar` command produces clear error message for archive operations
- [ ] tgz restore validates archive safety:
  - Uses `tar -tzf` for path validation (handles filenames with spaces)
  - Filters verbose listing to entry lines only (handles tar warnings/metadata)
  - Allows PAX/GNU metadata entries (x, g, L, K) which are internal tar bookkeeping
  - Rejects absolute paths and `../` traversal
  - Only allows regular files and directories
  - Rejects symlinks, hardlinks, devices, FIFOs, sockets
- [ ] Archive validation checks tar exit status properly
- [ ] tgz restore is idempotent (repeated runs produce identical volume state)
- [ ] tgz restore skips all host-derived mutations (env import, transforms)
- [ ] Archives with symlinks produce clear error explaining the limitation
- [ ] `cai import --data-volume vol --from <dir>` syncs from directory using rsync
- [ ] Directory sync uses normalized `source_root` comparison; skips path rewriting with warning when different from `$HOME`
- [ ] Source type auto-detected (directory vs gzip archive via tar validation)
- [ ] Missing source produces clear error message (before type detection)
- [ ] Unreadable/non-traversable source produces clear error message
- [ ] Invalid/corrupt tgz produces clear error message
- [ ] Docker Desktop file-sharing errors produce actionable message (directory mode only)
- [ ] `--dry-run --from <tgz>` lists archive contents only; skips config/volume/Docker operations
- [ ] `--no-excludes` ignored for tgz restore (documented behavior)
- [ ] Env import remains workspace-driven (not affected by `--from`)
- [ ] Help text updated with `--from` flag documentation
- [ ] Existing `cai import` (no `--from`) continues to work unchanged

## References

- Current import: `agent-sandbox/lib/import.sh:201-552`
- Current export: `agent-sandbox/lib/export.sh:96-271`
- CLI handler: `agent-sandbox/containai.sh:427-529`
- Env import call: `agent-sandbox/containai.sh:565` (`_containai_import_env`)
- SYNC_MAP: `agent-sandbox/lib/import.sh:88-147`
- Host path prefix: `agent-sandbox/lib/import.sh:44` (`_IMPORT_HOST_PATH_PREFIX`)
- Volume validation: `agent-sandbox/lib/import.sh:254` (creates volume in dry-run)
- Env import: `agent-sandbox/lib/env.sh:278`
- Docker context selection: `agent-sandbox/lib/import.sh:211-217`
