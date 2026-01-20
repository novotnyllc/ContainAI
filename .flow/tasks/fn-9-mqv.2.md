# fn-9-mqv.2 Add source type detection helper

## Description
Add helper function to detect source type (directory vs gzip archive).

**Size:** S  
**Files:** `agent-sandbox/lib/import.sh`

## Approach

- Add `_import_detect_source_type()` function near top of `lib/import.sh`
- Use `file -b` command for reliable detection (not extension)
- Return: `dir`, `tgz`, or `unknown`
- Follow naming pattern from `_import_validate_volume_name()` at line 54

## Key context

- `file -b` outputs brief description, e.g., "gzip compressed data"
- Check `[ -d "$source" ]` first for directories
- For archives, grep for "gzip" in file output
- Must handle symlinks: check if target is dir after resolving
## Acceptance
- [ ] `_import_detect_source_type /path/to/dir` returns "dir"
- [ ] `_import_detect_source_type /path/to/file.tgz` returns "tgz"
- [ ] `_import_detect_source_type /path/to/unknown` returns "unknown"
- [ ] Symlink to directory detected as "dir"
- [ ] Function uses `file -b` not extension matching
## Done summary
## Done Summary

Added `_import_detect_source_type()` helper function to detect whether a source path is a directory or gzip archive.

### Implementation Details
- Function placed near top of `lib/import.sh` (line 82), following naming pattern from `_import_validate_volume_name()`
- Uses `file -b` command for reliable archive detection (not extension matching)
- Returns: `dir`, `tgz`, or `unknown`
- Handles symlinks correctly - uses `[[ -d "$source" ]]` which resolves symlinks

### Function Behavior
- Directory: Returns "dir" (handles symlinks to directories)
- Gzip archive: Uses `file -b` and checks for "gzip compressed" in output, returns "tgz"
- Unknown: Returns "unknown" for unrecognized file types
- Non-existent: Returns exit code 1 (no output)
## Evidence
- Commits: d883826 feat(import): add source type detection helper
- Tests: Manual verification: function added following spec approach
- PRs: