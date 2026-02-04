# Task fn-51.3: Update generators to read from per-agent manifest files

**Status:** pending
**Depends on:** fn-51.1, fn-51.2

## Objective

Update existing generator scripts to read directly from `src/manifests/*.toml` and create new generator for `_IMPORT_SYNC_MAP`.

## Context

Current generators:
- `gen-dockerfile-symlinks.sh` - generates symlink creation script
- `gen-init-dirs.sh` - generates directory initialization script
- `gen-container-link-spec.sh` - generates link spec JSON

All currently read from single `sync-manifest.toml`. They need to iterate over `src/manifests/*.toml` files in sorted order for deterministic output.

## Implementation

1. Update `src/scripts/parse-manifest.sh`:
   - Accept directory path OR file path
   - When given directory, iterate `*.toml` files in sorted order (numeric prefixes ensure ordering)
   - Skip `[agent]` sections (not needed for sync entries)
   - Output same format as before
   - New flag: `--emit-source-file` to include source file path in output (for consistency checks)

2. Update each generator to use directory mode:
```bash
# Before
./src/scripts/gen-dockerfile-symlinks.sh src/sync-manifest.toml output.sh

# After (accepts directory)
./src/scripts/gen-dockerfile-symlinks.sh src/manifests/ output.sh
```

3. Update `build.sh` to pass directory instead of file

4. Create `src/scripts/gen-import-map.sh`:
   - Reads all manifests from `src/manifests/`
   - Generates `_IMPORT_SYNC_MAP` **indexed array** (same format as current):
   ```bash
   _IMPORT_SYNC_MAP=(
       "/source/.claude.json:/target/claude/claude.json:fjs"
       "/source/.claude/.credentials.json:/target/claude/credentials.json:fs"
       # ... etc
   )
   ```
   - Output can replace hardcoded map in `src/lib/import.sh`
   - **Note:** Keep the indexed array format used today, not associative

5. Update generator output headers:
   - Change "Generated from sync-manifest.toml" to "Generated from src/manifests/"
   - This means byte-for-byte comparison will fail, but semantic equivalence should hold

6. Verification: Compare **semantic** equivalence (ignore header changes, whitespace):
```bash
# Generate with old method (before deletion)
./src/scripts/gen-dockerfile-symlinks.sh src/sync-manifest.toml /tmp/old-symlinks.sh

# Generate with new method
./src/scripts/gen-dockerfile-symlinks.sh src/manifests /tmp/new-symlinks.sh

# Compare semantically (strip headers, normalize whitespace)
tail -n +3 /tmp/old-symlinks.sh | sort > /tmp/old-sorted.sh
tail -n +3 /tmp/new-symlinks.sh | sort > /tmp/new-sorted.sh
diff /tmp/old-sorted.sh /tmp/new-sorted.sh
```

7. Delete `src/sync-manifest.toml` after all generators verified

## Acceptance Criteria

- [ ] `parse-manifest.sh` accepts directory path and iterates in sorted order
- [ ] All three generators work with `src/manifests/` directory
- [ ] `build.sh` updated to use directory path
- [ ] New `gen-import-map.sh` generates `_IMPORT_SYNC_MAP` in **indexed array format** (same as today)
- [ ] Generated artifacts semantically equivalent to before (headers may differ)
- [ ] `sync-manifest.toml` deleted after verification
- [ ] Image builds successfully

## Notes

- Sorted order (via numeric prefixes) ensures deterministic output
- `[agent]` sections filtered out by parse-manifest.sh
- Backward compat: if single file passed, use old behavior
- Semantic equivalence check: ignore header comments, compare sorted output
- Keep `_IMPORT_SYNC_MAP` as indexed array of strings - do NOT change to associative

## Done summary
Updated generators to read from src/manifests/ directory. Created gen-import-map.sh. Updated build.sh, package-release.sh, install.sh, and sync.sh. Deleted sync-manifest.toml.
## Evidence
- Commits: 5d9432f, 2eb7306, f659716
- Tests: shellcheck -x src/scripts/*.sh, scripts/check-manifest-consistency.sh, src/scripts/parse-manifest.sh src/manifests/, src/scripts/gen-dockerfile-symlinks.sh src/manifests/ /tmp/test.sh, src/scripts/gen-init-dirs.sh src/manifests/ /tmp/test.sh, src/scripts/gen-container-link-spec.sh src/manifests/ /tmp/test.json, src/scripts/gen-import-map.sh src/manifests/
- PRs:
