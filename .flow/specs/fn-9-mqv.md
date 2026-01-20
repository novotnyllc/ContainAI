# Import Source Specification with tgz/Directory Support

## Overview

Extend `cai import` to support specifying an import source, enabling:
1. **Restore from tgz archive** - Direct extraction to volume (idempotent)
2. **Sync from directory** - rsync from arbitrary directory (not just `$HOME`)

Currently, import is hardcoded to sync from host `$HOME` via bind mount at `lib/import.sh:517-521`.

## Scope

**In scope:**
- `--from <path>` flag to specify source (tgz file or directory)
- Auto-detect source type (directory vs gzip archive via `file` command)
- Idempotent tgz import (same result on repeated runs)
- Directory import reusing existing rsync mechanism

**Out of scope:**
- URL import (http/https)
- Stdin import (`--from -`)
- Encrypted/password-protected archives
- Merge mode (always overwrite)

## Key Design Decisions

### Two Source Layouts

**Critical insight**: Host `$HOME` and tgz archives have different layouts:

| Source | Layout | Example Path |
|--------|--------|--------------|
| Host $HOME | Host paths | `~/.claude/settings.json` |
| tgz archive | Volume paths | `./claude/settings.json` |

**Implication**: tgz import is a **restore** operation that bypasses `_IMPORT_SYNC_MAP` and extracts directly to volume. Directory import uses existing rsync mechanism with configurable source.

### Idempotency Definition

For tgz import "idempotent with tgz assuming no excludes":
- **Same file content** - byte-for-byte identical
- **Same permissions** - mode preserved by tar
- **Timestamps** - preserved from archive (tar default behavior)

Running `cai import --from backup.tgz` twice produces identical volume state.

### Source Type Detection

Use `file` command (not extension) for reliable detection:
```bash
if [ -d "$source" ]; then
    # directory
elif file -b "$source" | grep -qE "gzip|tar"; then
    # archive
else
    # error
fi
```

## Approach

### tgz Import (Restore)

1. Validate archive with `tar -tzf`
2. Clear target volume contents (for true idempotency)
3. Extract directly to volume via alpine container
4. Skip post-transforms (not applicable for restore)

### Directory Import (Sync)

1. Detect directory source
2. Replace hardcoded `$HOME` bind mount with specified directory
3. Run existing rsync + SYNC_MAP mechanism
4. Run post-transforms (reads from source directory)

## Quick Commands

```bash
# Test tgz import idempotency
./containai.sh export test-vol /tmp/backup.tgz
./containai.sh import test-vol --from /tmp/backup.tgz
./containai.sh import test-vol --from /tmp/backup.tgz  # should be idempotent

# Test directory import
./containai.sh import test-vol --from ~/other-configs/
```

## Acceptance Criteria

- [ ] `cai import <vol> --from <path.tgz>` extracts archive to volume
- [ ] tgz import is idempotent (repeated runs produce identical volume state)
- [ ] `cai import <vol> --from <dir>` syncs from directory using rsync
- [ ] Source type auto-detected (directory vs gzip archive)
- [ ] Invalid/corrupt tgz produces clear error message
- [ ] Missing source produces clear error message
- [ ] Help text updated with `--from` flag documentation
- [ ] Existing `cai import` (no `--from`) continues to work unchanged

## References

- Current import: `agent-sandbox/lib/import.sh:201-552`
- Current export: `agent-sandbox/lib/export.sh:96-271`
- CLI handler: `agent-sandbox/containai.sh:427-529`
- SYNC_MAP: `agent-sandbox/lib/import.sh:88-147`
- Volume validation pattern: `lib/import.sh:54-68`
