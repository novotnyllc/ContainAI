# fn-53-architecture-refactor-completion-naming.10 Final validation sweep and quality gates

## Description
Final validation sweep across the entire refactored codebase. Verify all acceptance criteria from the PRD are met and all quality gates pass.

**Size:** S
**Files:** 0 new files (verification only, fix any remaining issues)

### Approach
- Run full quality gate suite:
  - `dotnet build ContainAI.slnx -c Release -warnaserror`
  - `dotnet test --solution ContainAI.slnx -c Release --xunit-info`
  - `dotnet format analyzers --diagnostics IDE1006 --verify-no-changes`
  - `dotnet tool run slopwatch analyze -d . --fail-on warning`
- Verify zero dotted basenames: `find src/cai -type f -name "*.cs" | xargs -I{} basename {} | sed "s/\.cs$//" | awk "index(\$0,\".\")>0" | wc -l` should return 0
- Verify coverage >= 97% for ContainAI.Cli, ContainAI.Cli.Abstractions, AgentClientProtocol.Proxy
- Verify `docs/architecture/refactor-exceptions.md` is complete and all exceptions justified
- Verify `specs/cai-aot-composition-decision-record.md` is complete
- Verify all cross-module dependencies point inward to contracts
- Fix any remaining issues found during validation

### Key context
- This is a gate task — it verifies but does not introduce new changes
- If issues are found, fix them in this task rather than creating new tasks
- PR notes should include module-by-module migration summary (PRD requirement)
## Acceptance
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] `dotnet test --solution ContainAI.slnx -c Release --xunit-info` passes (all tests)
- [ ] `dotnet format analyzers --diagnostics IDE1006 --verify-no-changes` passes
- [ ] `dotnet tool run slopwatch analyze -d . --fail-on warning` passes
- [ ] Zero dotted basenames in hand-written src/cai source files
- [ ] Coverage >= 97% for CLI libraries
- [ ] All PRD Definition of Done criteria verified
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
