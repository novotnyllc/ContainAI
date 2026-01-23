# fn-10-vep.18 Create comprehensive test suite

## Description
Create a comprehensive test suite that verifies ContainAI works correctly in all scenarios. The user wants confidence that "after running the test suite, things are good to go."

**Size:** M
**Files:**
- `tests/integration/test-containai.sh` (new comprehensive test script)
- `tests/integration/test-fixtures/` (new directory with test configs/skills/data)

## Scenarios to test

1. **Clean start without import**
   - Build image
   - Run container
   - Verify basic functionality (shell, tools)
   - No import data present

2. **Clean start with import**
   - Create test fixtures (mock configs, skills, data)
   - Run `cai import` with test fixtures
   - Verify data synced correctly
   - Run container
   - Verify imported data is accessible inside container

3. **DinD operations** (requires dockerd running)
   - `docker info` works
   - `docker run --rm alpine echo test` works
   - `docker build` works

4. **Agent doctor commands**
   - `claude doctor` works (or reports clear error if not configured)
   - Other agents: codex, copilot (if available)

## Approach

1. Create test fixture files:
   - `test-fixtures/claude/settings.json`
   - `test-fixtures/claude/plugins/test-plugin/`
   - `test-fixtures/shell/.bash_aliases`

2. Write test script following pattern from `test-sync-integration.sh`:
   - `pass()`, `fail()`, `info()`, `section()` helpers
   - Cleanup on exit
   - Clear pass/fail output

3. Tests must be idempotent and not require human interaction

## Key files to reference

- `tests/integration/test-sync-integration.sh` - existing test pattern
- `tests/integration/test-secure-engine.sh` - test helper pattern
- `src/lib/import.sh` - import functionality
## Acceptance
- [ ] Test script `test-containai.sh` created
- [ ] Test fixtures directory with sample configs/skills/data
- [ ] Scenario: Clean start without import passes
- [ ] Scenario: Clean start with import passes
- [ ] Scenario: DinD operations pass (when dockerd available)
- [ ] Scenario: Agent doctor commands tested
- [ ] All tests pass when run inside sysbox container
- [ ] Tests are idempotent (can run multiple times)
- [ ] Clear output showing what passed/failed
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
