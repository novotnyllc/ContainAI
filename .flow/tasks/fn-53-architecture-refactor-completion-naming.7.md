# fn-53-architecture-refactor-completion-naming.7 Contract/implementation separation: P1 modules (Sessions, Importing, Operations, remaining)

## Description
Extract co-located interfaces from implementation files in P1 modules: Sessions (~46 mixed files), Importing (~42 mixed files), Operations (~29 mixed files), and remaining modules (ContainerLinks ~11, Install ~8, ShellProfile ~6, and other small modules ~35).

**Size:** M (high file count but mechanical operations with established pattern from task 6)
**Files:** ~177 files to evaluate, ~130-140 splits expected, ~35-40 approved exceptions

### Approach
- Follow the same pattern established in task 6
- Process by module: Sessions → Importing → Operations → remaining
- Apply the same exception criteria (private nested, source-generator, <15-line adapter)
- Add all approved exceptions to `docs/architecture/refactor-exceptions.md` (created in task 6)
- Sessions is the largest (46 files) — batch by subfolder (Resolution/, Execution/, Provisioning/, etc.)
- For Importing (42 files) and Operations (29 files): these modules already have some subfolder structure

### Key context
- Sessions: all 72 files now have hierarchical namespaces (from task 4), so interface extraction benefits from clear module boundaries
- Importing already has: `Environment/`, `Facade/`, `Orchestration/`, `Paths/`, `Symlinks/`, `Transfer/`
- Operations already has: `Diagnostics/`, `DiagnosticsAndSetup/`, `Facade/`, `Maintenance/`, `TemplateSshGc/`
- `ContainerLinks/Repair/ContainerLinkRepairContracts.cs` already exists as a contracts file — extend pattern
## Acceptance
- [ ] All mixed files in Sessions, Importing, Operations, and remaining modules evaluated
- [ ] Interface/class splits completed for non-exception files
- [ ] `docs/architecture/refactor-exceptions.md` updated with all approved exceptions
- [ ] Mixed file count reduced from 213 baseline to approved exceptions only
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing tests pass unchanged
- [ ] slopwatch clean
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
