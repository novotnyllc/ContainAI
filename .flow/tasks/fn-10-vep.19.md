# fn-10-vep.19 Test AI agent doctor commands

## Description
Test that AI agent doctor/diagnostic commands work correctly inside the container. This verifies the agents are properly installed and configured.

**Size:** S
**Files:** Part of test suite from fn-10-vep.18

## Agent doctor commands to test

1. **cai doctor** - ContainAI's own diagnostic
   - Already implemented in `lib/doctor.sh`
   - Should show container health, runtime mode, etc.

2. **claude doctor** - Claude Code diagnostic
   - Shows Claude installation status
   - API connectivity (if configured)
   - Plugin status

3. **codex doctor** (if available) - OpenAI Codex diagnostic

4. **Other agents** as installed:
   - copilot (may not have doctor command)
   - gemini (may not have doctor command)

## Approach

1. Run each doctor command inside the container
2. Verify it exits successfully (or with expected "not configured" message)
3. Check output contains expected sections
4. Document which agents have doctor commands vs don't

## Key context

- Agents are installed via Dockerfile lines 166-171
- Some agents may require API keys to fully pass doctor checks
- Tests should handle "not configured" gracefully (not fail)
## Acceptance
- [x] `cai doctor` runs and shows status
- [x] `claude doctor` runs (may show "not configured" which is OK)
- [x] Other available agent doctor commands tested
- [x] Document which agents have/don't have doctor commands
- [x] Tests handle missing API keys gracefully
## Done summary
Updated `tests/integration/test-containai.sh` to add `cai doctor` testing and document AI agent diagnostic commands:

1. Added `cai doctor` check in prerequisites to verify ContainAI environment health
2. Added comprehensive Agent Doctor Command Reference documenting:
   - WITH doctor command: claude doctor, codex doctor
   - WITH diagnostics (no doctor): gh auth status, copilot --version
   - WITHOUT diagnostics: gemini, aider, cursor
3. Fixed copilot test to check version instead of non-existent doctor command
4. Tests handle missing API keys gracefully (accept "not configured" as valid outcome)

## Evidence
- Commits: 64c718d
- Tests: `shellcheck -x tests/integration/test-containai.sh` (passed), `cai doctor` (runs successfully)
- PRs: N/A (direct merge)
