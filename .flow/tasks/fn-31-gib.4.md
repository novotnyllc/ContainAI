# fn-31-gib.4 Audit sync-manifest.toml completeness

## Description
Verify manifest covers all CURRENTLY SUPPORTED agent config paths. Address drift between manifest and hardcoded paths in `_IMPORT_SYNC_MAP` and runtime init.

**Key files:**
- `src/sync-manifest.toml` - should be authoritative
- `src/lib/import.sh` - `_IMPORT_SYNC_MAP` array
- `src/container/entrypoint.sh` - hardcoded init paths

**Note:** Adding new agents (Kiro, Windsurf, Cline) is out of scope for this epic (covered in fn-35-e0x).

## Acceptance
- [x] All currently supported agents (Claude, Codex, Gemini, Cursor, Aider, Continue, Copilot) have correct manifest entries
- [x] `scripts/check-manifest-consistency.sh` created - verifies import map matches manifest
- [x] CI workflow calls `check-manifest-consistency.sh` on PR
- [x] CLAUDE.md or inline comment documents: "sync-manifest.toml is authoritative"
- [x] If discrepancies found, either generate import map from manifest OR align manually

## Done summary
Added sync-manifest consistency checking with CI enforcement. Created `scripts/check-manifest-consistency.sh` that verifies `_IMPORT_SYNC_MAP` in import.sh matches manifest entries. Added lint job to CI workflow that runs on PRs. Updated parse-manifest.sh to handle `disabled` field with `--include-disabled` flag. Generators now include disabled entries for symlinks while consistency check excludes them from import map validation.
## Evidence
- Commits: 2a8c87b feat(import): add sync-manifest consistency check with CI enforcement, c801b21 fix(import): address review feedback for manifest consistency check
- Tests: scripts/check-manifest-consistency.sh (pass - 62 entries verified)
- PRs:
