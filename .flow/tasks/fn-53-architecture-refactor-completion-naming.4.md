# fn-53-architecture-refactor-completion-naming.4 Sessions naming normalization and folder restructure

## Description
Rename 27 dotted-basename files in `src/cai/Sessions/` and establish folder-based namespace hierarchy. This is the deepest restructure — 72 files all use flat `ContainAI.Cli.Host` despite 6+ levels of folder nesting.

**Size:** M (borderline L due to namespace scope, but operations are mechanical)
**Files:** 27 renames + ~72 namespace fixups + ~40 dependent using-statement fixups

### Target files by subfolder

**Sessions/Models (5):**
- `SessionRuntimeModels.CommandOptions.cs`, `.ProcessResult.cs`, `.ResolutionResults.cs`, `.SessionMode.cs`, `.TargetAndSession.cs`

**Sessions/Resolution/Containers (7):**
- `SessionTargetResolver.DockerLookup.Abstractions.cs`, `.Core.cs`, `.LabelReader.cs`, `.NameReservation.cs`, `.Parsing.cs`, `.SelectionPolicy.cs`, `.WorkspaceResolver.cs`

**Sessions/Resolution/Models (1):** `SessionTargetResolver.Models.cs`

**Sessions/Resolution/Orchestration (4):**
- `SessionTargetResolver.ExplicitContainerResolver.cs`, `.ResolutionPipeline.cs`, `.TargetFactory.cs`, `.WorkspaceResolver.cs`

**Sessions/Resolution/Validation (1):** `SessionTargetResolver.ParsingValidation.cs`

**Sessions/Resolution/Workspace (5):**
- `SessionTargetResolver.ConfiguredContextResolver.cs`, `.ContainerNameGenerationService.cs`, `.ContextDiscoveryService.cs`, `.DataVolumeResolutionService.cs`, `.WorkspaceDiscovery.cs`

**Sessions/Resolution/Workspace/Selection (4):**
- `SessionTargetResolver.SelectionHelpers.WorkspaceContainer.cs`, `.WorkspaceContext.cs`, `.WorkspacePath.cs`, `.WorkspaceVolume.cs`

### Approach
- Two-commit strategy: (1) `git mv` only, (2) namespace/using fixups
- Strip `SessionTargetResolver.` and `SessionRuntimeModels.` prefixes from filenames
- These are **separate classes** (not partial), despite the misleading dotted filenames
- Update all 72 Sessions files from `namespace ContainAI.Cli.Host` to `ContainAI.Cli.Host.Sessions.<Subfolder>`
- This is the highest-risk rename because dependency analysis is invisible at namespace level (everything was in one namespace)
- Build after every subfolder batch, not just at the end
- **Shared files:** Namespace fixup may touch `CaiCommandRuntimeHandlersFactory.cs` and `Program.cs` for `using` additions. Coordinate with other Phase 1 tasks to serialize shared-file fixup commits.

### Key context
- Sessions has the deepest folder nesting (Resolution/Workspace/Selection/) — namespace hierarchy must match
- All session types are currently in one namespace, so all `using` changes are additions (adding `using ContainAI.Cli.Host.Sessions.*`) rather than modifications
- `SessionLifecycleParityTests.cs` and `ContainerNamingTests.cs` are the key test files to verify
## Acceptance
- [ ] Zero dotted basenames in `src/cai/Sessions/` (27 files renamed)
- [ ] All Sessions files (72) use namespace matching folder hierarchy
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing Sessions tests pass unchanged
- [ ] `git log --follow` confirms rename detection for moved files
- [ ] No type name collisions introduced by namespace changes
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
