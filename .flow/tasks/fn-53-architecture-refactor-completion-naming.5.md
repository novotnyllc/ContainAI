# fn-53-architecture-refactor-completion-naming.5 Devcontainer naming normalization and folder restructure

## Description
Rename 12 dotted-basename files in `src/cai/Devcontainer/` and establish consistent folder layering. Runs last in Phase 1 to minimize conflict with fn-49 (devcontainer integration).

**Size:** M
**Files:** 12 renames + ~20 dependent using-statement fixups

### Target files (audited, 12 total)
**DevcontainerFeatureRuntime pseudo-partials (8):**
- `DevcontainerFeatureRuntime.EntrypointOrchestration.cs`, `.FeatureFlags.cs`, `.Init.cs`, `.Init.ConfigLoader.cs`, `.Init.LinkApplier.cs`, `.Init.LinkSpecLoader.cs`, `.Install.cs`, `.Start.cs`

**DevcontainerProcessHelpers pseudo-partials (4):**
- `DevcontainerProcessHelpers.Collaborators.cs`, `.FileAndProc.cs`, `.Network.cs`, `.ProcessExecution.cs`

### Approach
- Two-commit strategy: (1) `git mv` only, (2) namespace/using fixups
- Existing subfolders: `Configuration/`, `InitLinks/`, `Inspection/`, `Install/`, `ProcessExecution/`, `Sysbox/`, `UserEnvironment/`
- Map dotted files into appropriate existing subfolders
- DevcontainerFeatureRuntime.Init.* files → `InitLinks/` or new `Init/` subfolder
- DevcontainerProcessHelpers.* files → `ProcessExecution/`
- Update namespaces from flat `ContainAI.Cli.Host` to `ContainAI.Cli.Host.Devcontainer.<Subfolder>`
- **Shared files:** Namespace fixup may touch `Program.cs` for `using` additions.

### Prerequisites
- **fn-49 must be merged to main or confirmed inactive** before starting this task
- Rebase onto main after fn-49 merge to pick up any Devcontainer file changes
- If fn-49 is still active with pending PRs touching Devcontainer, defer this task

### Key context
- `DevcontainerFeatureWorkflowFactory.cs` (in `Configuration/`) is the composition root for this module — follow its pattern
- 42 of 45 Devcontainer files use flat `ContainAI.Cli.Host` namespace
- PRD says Devcontainer is the "largest visible debt; user pain point" — but we run it last to avoid fn-49 conflicts
## Acceptance
- [ ] Zero dotted basenames in `src/cai/Devcontainer/` (12 files renamed)
- [ ] All Devcontainer files use namespace matching folder hierarchy
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing Devcontainer tests pass unchanged
- [ ] Prerequisite verified: fn-49 merged or confirmed inactive before work started
- [ ] Rebased onto main after fn-49 merge (if applicable)
- [ ] `git log --follow` confirms rename detection
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
