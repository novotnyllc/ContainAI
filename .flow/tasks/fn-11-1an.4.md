# fn-11-1an.4 Add integration tests for symlink relinking

## Description
Add integration tests validating symlink relinking behavior during import.

**Size:** M
**Files:** `tests/integration/test-sync-integration.sh`

## Approach

Follow existing test patterns in `test-sync-integration.sh`:
- Use `populate_fixture()` pattern (line 180)
- Use hermetic test volumes with `TEST_RUN_ID` (line 72-73)
- Use `run_in_rsync()` helper (line 126-143)

### Test cases

1. **Internal absolute symlink** - relinked correctly
   - Create: `/source/.config/nvim` → absolute symlink to `/host/dotfiles/.config/nvim.d`
   - Where `/host/dotfiles/.config/nvim.d` is the host path for the same directory
   - Verify after import: symlink points to `/mnt/agent-data/config/nvim.d`

2. **Relative symlink** - NOT relinked (preserved as-is)
   - Create: `/source/.config/link` → `./target` (relative)
   - Verify after import: symlink still points to `./target` (unchanged)

3. **External absolute symlink** - preserved with warning
   - Create: symlink to `/usr/bin/bash` (outside import tree)
   - Verify: symlink preserved, warning logged

4. **Broken symlink** - preserved as-is
   - Create: symlink to nonexistent target within host_src_dir
   - Verify: symlink preserved (not relinked), no error

5. **Circular symlinks** - no hang
   - Create: `a` → `b`, `b` → `a`
   - Verify: import completes without hanging

6. **Directory symlink pitfall** - handled correctly
   - Pre-populate volume: create real directory at `/data/config/nvim`
   - Import: symlink at same path
   - Verify: result is a symlink (not symlink inside directory)
   - This tests the `rm -rf` before `ln -s` pattern

### Test fixture setup

```sh
# Create host-like source structure with symlinks
alt_source_dir=$(mktemp -d "${REAL_HOME}/.containai-symlink-test-XXXXXX")
mkdir -p "$alt_source_dir/.config/nvim.d"
echo "content" > "$alt_source_dir/.config/nvim.d/init.vim"

# Internal absolute symlink (uses full host path)
ln -s "$alt_source_dir/.config/nvim.d" "$alt_source_dir/.config/nvim"

# Relative symlink
ln -s "./nvim.d" "$alt_source_dir/.config/nvim-rel"

# External symlink
ln -s "/usr/bin/bash" "$alt_source_dir/.config/external"
```

### Verification

```sh
# Check symlink targets in volume
docker run --rm -v "$test_vol":/data alpine sh -c '
    readlink /data/config/nvim       # Should be /mnt/agent-data/config/nvim.d
    readlink /data/config/nvim-rel   # Should be ./nvim.d (unchanged)
    readlink /data/config/external   # Should be /usr/bin/bash (unchanged)
'
```

## Key context

- Symlink test fixtures must use **host paths** for internal absolute symlinks
- The `HOST_SRC_DIR` is the host path, not `/source` mount path
- Directory symlink test must pre-populate volume to trigger the pitfall

## Acceptance
- [ ] Test: internal absolute symlink relinked to `/mnt/agent-data/...` path
- [ ] Test: relative symlink preserved unchanged (not relinked)
- [ ] Test: external absolute symlink preserved (not relinked), warning logged
- [ ] Test: broken symlink does not cause error, preserved as-is
- [ ] Test: circular symlinks do not hang
- [ ] Test: directory symlink replaces pre-existing directory (pitfall handled)
- [ ] All existing tests continue to pass

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
