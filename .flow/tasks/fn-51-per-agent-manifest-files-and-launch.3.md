# Task fn-51.3: Update generators to read from per-agent manifest files

**Status:** pending
**Depends on:** fn-51.1, fn-51.2

## Objective

Update existing generator scripts to read directly from `src/manifests/*.toml` instead of single `sync-manifest.toml`.

## Context

Current generators:
- `gen-dockerfile-symlinks.sh` - generates symlink creation script
- `gen-init-dirs.sh` - generates directory initialization script
- `gen-container-link-spec.sh` - generates link spec JSON

All currently read from single `sync-manifest.toml`. They need to iterate over `src/manifests/*.toml` files directly.

## Implementation

1. Update `src/scripts/parse-manifest.sh`:
   - Accept directory path OR file path
   - When given directory, iterate `*.toml` files in sorted order
   - Skip `[agent]` sections (not needed for sync entries)
   - Output same format as before

2. Update each generator to use directory mode:
```bash
# Before
./src/scripts/gen-dockerfile-symlinks.sh src/sync-manifest.toml output.sh

# After
./src/scripts/gen-dockerfile-symlinks.sh src/manifests/ output.sh
```

3. Update `build.sh` to pass directory instead of file:
```bash
./src/scripts/gen-dockerfile-symlinks.sh src/manifests artifacts/container-generated/symlinks.sh
./src/scripts/gen-init-dirs.sh src/manifests artifacts/container-generated/init-dirs.sh
./src/scripts/gen-container-link-spec.sh src/manifests artifacts/container-generated/link-spec.json
```

4. Delete `src/sync-manifest.toml` after all generators updated

## Acceptance Criteria

- [ ] `parse-manifest.sh` accepts directory path
- [ ] All three generators work with `src/manifests/` directory
- [ ] `build.sh` updated to use directory path
- [ ] Generated artifacts identical to before (byte-for-byte or equivalent)
- [ ] `sync-manifest.toml` deleted
- [ ] Image builds successfully

## Verification

```bash
# Generate with old method (before deletion)
./src/scripts/gen-dockerfile-symlinks.sh src/sync-manifest.toml /tmp/old-symlinks.sh

# Generate with new method
./src/scripts/gen-dockerfile-symlinks.sh src/manifests /tmp/new-symlinks.sh

# Compare (should be equivalent)
diff /tmp/old-symlinks.sh /tmp/new-symlinks.sh
```

## Notes

- Sorted order ensures deterministic output
- `[agent]` sections filtered out by parse-manifest.sh
- Backward compat: if single file passed, use old behavior
