# fn-31-gib.4 Audit sync-manifest.toml completeness

## Description
Verify manifest covers all CURRENTLY SUPPORTED agent config paths. Address drift between manifest and hardcoded paths in `_IMPORT_SYNC_MAP` and runtime init.

**Key files:**
- `src/sync-manifest.toml` - should be authoritative
- `src/lib/import.sh` - `_IMPORT_SYNC_MAP` array
- `src/container/entrypoint.sh` - hardcoded init paths

**Note:** Adding new agents (Kiro, Windsurf, Cline) is out of scope for this epic (covered in fn-35-e0x).

## Acceptance
- [ ] All currently supported agents (Claude, Codex, Gemini, Cursor, Aider, Continue, Copilot) have correct manifest entries
- [ ] `scripts/check-manifest-consistency.sh` created - verifies import map matches manifest
- [ ] CI workflow calls `check-manifest-consistency.sh` on PR
- [ ] CLAUDE.md or inline comment documents: "sync-manifest.toml is authoritative"
- [ ] If discrepancies found, either generate import map from manifest OR align manually

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
