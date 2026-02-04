# Task fn-51.7: Update check-manifest-consistency.sh for new structure

**Status:** done
**Depends on:** fn-51.1, fn-51.3, fn-51.6

## Objective

Update the consistency checker to work with per-agent manifest files and generated import map.

## Context

`scripts/check-manifest-consistency.sh` verifies that `_IMPORT_SYNC_MAP` in `import.sh` matches the manifest. After splitting manifests and adding import map generation, the checker needs updates.

## Implementation

1. Update script to read from `src/manifests/` directory instead of single file

2. Verify generated `_IMPORT_SYNC_MAP` matches manifest entries:
   - Run `gen-import-map.sh` to generate expected map
   - Compare against actual map in `import.sh`
   - Report mismatches with source file path

3. Add TOML syntax validation for all manifests:
   - Use `parse-toml.py --validate` mode
   - Report which file has syntax errors

4. Verify required fields in `[agent]` sections:
   - `name` required
   - `binary` required
   - `default_args` must be array (if present)
   - `aliases` must be array (if present)

5. Output improvements:
   - Show which source file contains each mismatch
   - Clear error messages for TOML syntax errors
   - Summary at end with pass/fail count

## Acceptance Criteria

- [ ] Script works with `src/manifests/` directory
- [ ] Validates TOML syntax for all manifest files
- [ ] Validates `[agent]` section schema
- [ ] Reports source file for each mismatch
- [ ] Verifies `_IMPORT_SYNC_MAP` matches generated version
- [ ] CI integration works (exit code 1 on failure)
- [ ] Clear, actionable error messages

## Notes

- Reuse `parse-toml.py` for validation
- Add `--emit-source-file` support to track entry origins
- Keep backward compat if possible (single file mode)

## Done summary
Updated `scripts/check-manifest-consistency.sh` to work with the per-agent manifest structure. The script now validates TOML syntax, [agent] section schema, and verifies the generated import-sync-map.sh matches manifest content, with source file attribution for mismatches.
## Evidence
- Commits:
- Tests: ./scripts/check-manifest-consistency.sh - passed all 26 checks (19 TOML, 6 agents, 1 import map)
- PRs:
