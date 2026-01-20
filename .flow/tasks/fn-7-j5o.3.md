# fn-7-j5o.3 Create quickstart guide

## Description
Create a standalone quickstart guide that gets users from zero to first sandbox in under 5 minutes (assuming Docker is installed).

**Size:** S
**Files:** `docs/quickstart.md`

## Approach

- Separate from README to allow detail without bloating entry point
- Clear prerequisites section (Docker Desktop 4.50+, bash shell)
- Numbered steps with verification at each stage
- Include "What just happened?" explanation section
- End with "Next steps" linking to configuration and troubleshooting

## Key Context

- CLI must be sourced, not executed: `source agent-sandbox/containai.sh`
- First run requires agent authentication (e.g., `claude login`)
- Default agent is Claude, configurable via `--agent` flag
- Works on Linux, WSL2, macOS (with different isolation modes)
## Acceptance
- [ ] docs/quickstart.md exists
- [ ] Prerequisites section lists Docker Desktop version, bash requirement
- [ ] Numbered steps from clone to first sandbox
- [ ] Each step has verification command/output
- [ ] Explains what happens during first run
- [ ] Links to troubleshooting for common setup issues
- [ ] Links to configuration guide for customization
- [ ] Achievable in <5 minutes for user with Docker installed
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
