# fn-17-axl.1 Re-validate current import config and create sync manifest

## Description

Audit the current import system, document inconsistencies, create the sync manifest, and implement destination-relative exclude evaluation.

## Part A: Audit (documentation)

1. Audit `src/lib/import.sh` `_IMPORT_SYNC_MAP` entries - document what's synced, flags used
2. Audit `src/container/Dockerfile.agents` symlink creation - document all symlinks
3. Audit `src/container/containai-init.sh` directory structure creation
4. Compare all three - identify mismatches, duplicates, missing entries
5. Document exclude pattern behavior - how patterns are currently applied per-entry

## Part B: Create sync manifest (implementation)

1. Create `src/sync-manifest.toml` with all current entries
2. Format: source, target, container_link (optional), flags
3. Include comments documenting each section

**Manifest flags:**
- `f` = file
- `d` = directory
- `j` = json-init (create {} if empty)
- `s` = secret (600/700 permissions)
- `m` = mirror mode (--delete)
- `x` = exclude .system/
- `g` = git-filter (strip credential.helper)
- `R` = remove existing path first (rm -rf before ln -sfn)

## Part C: Implement destination-relative excludes (implementation)

**Current behavior:** Excludes are applied globally via `EXCLUDE_DATA_B64` to each rsync invocation, but each entry has a different source root.

**New behavior:** Excludes are evaluated against destination paths and transported per-entry.

### Transport Mechanism

**Current:** Single global `EXCLUDE_DATA_B64` env var applied to all entries.

**New:** Extend MAP_DATA format to include per-entry excludes:
```
source:target:flags:excludes_b64
```

Where `excludes_b64` is base64-encoded newline-delimited excludes for that specific entry (or empty if none apply).

**Update `copy()` function** to decode and apply per-entry excludes.
**Remove global exclude env var** (`EXCLUDE_DATA_B64`) - all excludes now per-entry.

### Pattern Classification (No-Slash Handling)

**No-slash patterns are classified by presence of glob metacharacters:**

1. **No-slash WITH glob metacharacters** (`*`, `?`, `[`): Global globs
   - Examples: `*.log`, `*.tmp`, `*~`, `?.bak`
   - Applied to ALL entries as-is
   - Always count as matched

2. **No-slash WITHOUT glob metacharacters**: Destination-root prefixes
   - Examples: `claude`, `codex`, `config`
   - Treated as parent patterns matching destination root
   - `claude` matches entries where `dst_rel` starts with `claude/` or equals `claude`

**Detection:**
```bash
has_glob_metachar() {
    case "$1" in
        *'*'*|*'?'*|*'['*) return 0 ;;  # Has glob
        *) return 1 ;;  # No glob
    esac
}
```

### Exclude Rewrite Algorithm (Bidirectional Matching)

```bash
# Entry destination: /target/claude/plugins (dst_rel = "claude/plugins")

for pattern in "${patterns[@]}"; do
    # Strip leading / for anchored patterns
    p="${pattern#/}"

    # Classify no-slash patterns
    if [[ "$p" != */* ]]; then
        if has_glob_metachar "$p"; then
            # Global glob (e.g., *.log) - apply to all entries
            entry_excludes+=("$p")
            pattern_matched["$pattern"]=1
        else
            # No-glob no-slash = destination-root prefix (e.g., "claude")
            # Treat as parent pattern
            case "$dst_rel" in
                "${p}"|"${p}/"*)
                    echo "[SKIP ENTRY]"
                    pattern_matched["$pattern"]=1
                    ;;
            esac
        fi
        continue
    fi

    # Path patterns (have /)

    # Case: Pattern matches destination exactly
    if [ "$p" = "$dst_rel" ]; then
        echo "[SKIP ENTRY]"
        pattern_matched["$pattern"]=1
        continue
    fi

    # Case: Pattern is PARENT of destination
    case "$dst_rel" in
        "${p}/"*)
            echo "[SKIP ENTRY]"
            pattern_matched["$pattern"]=1
            continue
            ;;
    esac

    # Case: Pattern is CHILD of destination
    case "$p" in
        "${dst_rel}/"*)
            remainder="${p#"$dst_rel/"}"
            entry_excludes+=("$remainder")
            pattern_matched["$pattern"]=1
            continue
            ;;
    esac
done
```

**Summary of pattern behavior:**
| Pattern | Type | Behavior |
|---------|------|----------|
| `*.log` | Global glob | Apply to all entries |
| `*.tmp` | Global glob | Apply to all entries |
| `claude` | Root prefix | Skip entries starting with `claude/` |
| `config` | Root prefix | Skip entries starting with `config/` |
| `claude/plugins` | Path | Skip exact match or parent |
| `claude/plugins/.system` | Path | Rewrite to `.system` for matching entry |

**Unmatched patterns:**
- After processing all entries, patterns that matched NO entry are warned and dropped
- Global glob patterns always count as matched

### Implementation Changes

1. Update `_import_rewrite_excludes()` with pattern classification and bidirectional matching
2. Modify MAP_DATA generation to include per-entry excludes field
3. Update `copy()` to accept and apply per-entry excludes
4. Remove global `EXCLUDE_DATA_B64` usage
5. Add unit tests for all pattern types

## Output

- `docs/sync-architecture.md` documenting current state and v2 design
- `src/sync-manifest.toml` as single source of truth
- Updated exclude handling in import.sh
- Unit tests for exclude rewriting

## Acceptance

- [ ] Documented all `_IMPORT_SYNC_MAP` entries with source, target, flags
- [ ] Documented all Dockerfile.agents symlink creations
- [ ] Documented all containai-init.sh directory structures
- [ ] Identified all mismatches between the three components
- [ ] `src/sync-manifest.toml` created with all current sync entries
- [ ] Manifest includes source, target, container_link, flags for each entry
- [ ] `_import_rewrite_excludes()` implements pattern classification
- [ ] **No-slash with glob (`*.log`): applied to all entries**
- [ ] **No-slash without glob (`claude`): treated as root prefix, skips matching entries**
- [ ] Path patterns: parent/exact/child matching works correctly
- [ ] Per-entry excludes transported via MAP_DATA, not global env var
- [ ] copy() updated to accept per-entry excludes
- [ ] Unmatched patterns warned and DROPPED
- [ ] `cai import --dry-run` verifies exclude behavior
- [ ] Unit tests for all pattern types
- [ ] Integration test: `claude` skips all claude/* entries
- [ ] Integration test: `*.log` excludes logs from all entries

## Done summary
Audited the import/sync system components, documented mismatches, created the sync manifest, and implemented destination-relative exclude evaluation with per-entry transport.
## Evidence
- Commits:
- Tests: bash tests/unit/test-exclude-rewrite.sh
- PRs:
