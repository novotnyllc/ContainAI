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
- [ ] `cai doctor` runs and shows status
- [ ] `claude doctor` runs (may show "not configured" which is OK)
- [ ] Other available agent doctor commands tested
- [ ] Document which agents have/don't have doctor commands
- [ ] Tests handle missing API keys gracefully
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
