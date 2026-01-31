# fn-31-gib.16 Add .priv. file filtering to import

## Description
Exclude `.bashrc.d/*.priv.*` files during import to prevent accidental secret leakage.

## Acceptance
- [ ] Import excludes files matching `*.priv.*` pattern in `.bashrc.d/`
- [ ] `--no-excludes` flag does NOT disable `.priv.` filtering (security requirement)
- [ ] Filtering applies to `--from <dir>` import path
- [ ] Filtering applies to `--from <tgz>` restore path
- [ ] Config option `import.exclude_priv` exists (default: true)
- [ ] Config option documented in config reference
- [ ] Test case: create `.bashrc.d/secrets.priv.sh`, run import, verify NOT synced
- [ ] Test case: same with `--no-excludes`, verify `.priv.` STILL not synced

## Done summary
# fn-31-gib.16 Summary: Add .priv. file filtering to import

## Changes Made

### 1. Added `p` flag for *.priv.* exclusion in SYNC_MAP (src/lib/import.sh)
- New flag `p` added to the flags documentation
- Applied to `.bashrc.d` entry: `"/source/.bashrc.d:/target/shell/bashrc.d:dp"`
- **Security**: Flag is NOT disabled by `--no-excludes` CLI option

### 2. Updated rsync container copy() function (src/lib/import.sh)
- Added handling for `p` flag in the POSIX sh script that runs inside rsync container
- Adds `--exclude=*.priv.*` when flag is present and `EXCLUDE_PRIV` env var is not `0`
- Controlled by new `import.exclude_priv` config option

### 3. Added config option `import.exclude_priv` (src/lib/config.sh)
- Added to `_CAI_GLOBAL_KEYS` for config resolution
- Default value: `true` (filtering enabled by default)
- Resolved early in `_containai_import()` and passed to both rsync and tgz paths

### 4. Updated tgz restore path (src/lib/import.sh)
- Added `--exclude '*.priv.*'` to tar extraction
- Controlled by same `import.exclude_priv` config option

### 5. Updated sync-manifest.toml
- Changed `.bashrc.d` entry flags from `d` to `dp`

### 6. Added documentation (docs/configuration.md)
- Added `exclude_priv` to `[import]` section documentation
- Explained security behavior (not disabled by `--no-excludes`)

### 7. Added integration tests (tests/integration/test-sync-integration.sh)
- Test 61: Normal import filters .priv. files
- Test 62: --no-excludes does NOT disable .priv. filtering (security)
- Test 63: .priv. file filtering in tgz restore

### 8. Fixed tgz restore to use path-specific excludes (src/lib/import.sh)
- Changed from broad `--exclude '*.priv.*'` to path-specific excludes
- Uses `--exclude './shell/bashrc.d/*.priv.*' --exclude 'shell/bashrc.d/*.priv.*'`
- Handles both `./` and non-prefixed paths from tar

### 9. Added config resolver for explicit_config support (src/lib/config.sh)
- Added `_containai_resolve_import_exclude_priv()` function
- Properly honors `--config` explicit path when resolving `import.exclude_priv`

### 10. Updated check-manifest-consistency.sh (scripts/)
- Added `p` flag to `normalize_flags()` function for proper consistency checking

### 11. Updated parse-toml.py (src/)
- Added `exclude_priv` and `import.exclude_priv` to `bool_keys` for proper boolean parsing

## Acceptance Criteria Met
- [x] Import excludes files matching `*.priv.*` pattern in `.bashrc.d/`
- [x] `--no-excludes` flag does NOT disable `.priv.` filtering (security requirement)
- [x] Filtering applies to `--from <dir>` import path
- [x] Filtering applies to `--from <tgz>` restore path
- [x] Config option `import.exclude_priv` exists (default: true)
- [x] Config option documented in config reference
- [x] Test case: create `.bashrc.d/secrets.priv.sh`, run import, verify NOT synced
- [x] Test case: same with `--no-excludes`, verify `.priv.` STILL not synced
## Evidence
- Commits:
- Tests: {'name': 'Test 61: Normal import filters .priv. files', 'file': 'tests/integration/test-sync-integration.sh', 'function': 'test_priv_file_filtering'}, {'name': 'Test 62: --no-excludes does NOT disable .priv. filtering', 'file': 'tests/integration/test-sync-integration.sh', 'function': 'test_priv_file_filtering'}, {'name': 'Test 63: .priv. file filtering in tgz restore', 'file': 'tests/integration/test-sync-integration.sh', 'function': 'test_priv_file_filtering_tgz'}
- PRs:
