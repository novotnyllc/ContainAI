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
TBD

## Evidence
- Commits:
- Tests:
- PRs:
