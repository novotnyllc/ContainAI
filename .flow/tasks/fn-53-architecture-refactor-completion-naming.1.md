# fn-53-architecture-refactor-completion-naming.1 ContainerRuntime naming normalization and folder restructure

## Description
Rename 14 dotted-basename files in `src/cai/ContainerRuntime/` to folder-based organization and align namespaces.

**Size:** M
**Files:** 14 renames + ~30 dependent using-statement fixups

### Target files (audited, 14 total)
- `ContainerRuntimeCommandService.CommandDispatch.cs`
- `ContainerRuntimeCommandService.CommandWiring.DevcontainerForwarders.cs`
- `ContainerRuntimeCommandService.CommandWiring.Init.cs`
- `ContainerRuntimeCommandService.CommandWiring.LinkRepair.cs`
- `ContainerRuntimeCommandService.CommandWiring.LinkWatcher.cs`
- `ContainerRuntimeCommandService.EnvFile.cs`
- `ContainerRuntimeCommandService.GitConfigMigration.cs`
- `ContainerRuntimeCommandService.Initialization.cs`
- `ContainerRuntimeCommandService.LinkSpecParsing.cs`
- `ContainerRuntimeCommandService.LinkSpecParsing.Construction.cs`
- `ContainerRuntimeCommandService.ManifestHooks.cs`
- `ContainerRuntimeCommandService.OutputHandling.cs`
- `ContainerRuntimeCommandService.WorkspaceLinks.cs`
- `ContainerRuntimeOptionParser.Models.cs`

### Approach
- Use two-commit strategy: (1) `git mv` only for rename detection, (2) namespace/using fixups
- Existing subfolders already present: `Handlers/`, `Services/`, `Infrastructure/`, `Inspection/`
- Move renamed files into appropriate existing or new subfolders
- Update namespaces from flat `ContainAI.Cli.Host` to `ContainAI.Cli.Host.ContainerRuntime.<Subfolder>`
- Follow pattern at `src/cai/CommandRuntime/Dispatch/CaiCommandRuntimeDispatchBase.cs` (already uses subfolder namespaces)
- Set `git config diff.renameLimit 1000` before operations
- **Shared files:** Namespace fixup may touch `Program.cs` and `CaiCommandRuntimeHandlersFactory.cs` for `using` additions. Coordinate with other Phase 1 tasks to serialize shared-file fixup commits.

### Key context
- ContainerRuntime already has 4/49 files using sub-namespaces; expand this to all files
- `ContainerRuntimeCommandService.cs` (the main class) stays in place; only the dotted pseudo-partials move
- Cross-module concrete dep: `ContainerRuntimeCommandService.cs:48` directly instantiates `new DevcontainerFeatureRuntime()` — do NOT change this (WS4 scope)
## Acceptance
- [ ] Zero dotted basenames in `src/cai/ContainerRuntime/` (14 files renamed)
- [ ] All ContainerRuntime files use namespace matching folder hierarchy
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing ContainerRuntime tests pass unchanged
- [ ] `git log --follow` confirms rename detection for moved files
## Done summary
## Done Summary

Renamed 14 dotted-basename files in `src/cai/ContainerRuntime/` to proper folder-based organization:

- 7 files → `Handlers/` (command handler interfaces, implementations, workflow, link spec processor)
- 4 files → `Services/` (env file loader, git config, manifest bootstrap, workspace links)
- 1 file → `Infrastructure/` (exception handling)
- 1 file → `Configuration/` (command parsing models)
- 1 file → `Configuration/` (option parser models with namespace update)

Two-commit strategy preserved rename detection:
1. Pure `git mv` commit (14 renames, 0 content changes, 100% rename detection)
2. Namespace/using fixup commit (1 namespace change + 6 using additions)

### Verification
- Zero dotted basenames remaining in `src/cai/ContainerRuntime/`
- All 14 renamed files have namespaces matching folder hierarchy
- `dotnet build ContainAI.slnx -c Release -warnaserror` passes (0 warnings, 0 errors)
- `dotnet format analyzers --diagnostics IDE1006 --verify-no-changes` passes
- All 340 existing tests pass (2 pre-existing failures in DocumentationLinkTests and SyncIntegrationTests unrelated to this change)
- `git log --follow` confirms rename detection for all moved files
## Evidence
- Commits: 93b0e99f, 6c7806b6
- Tests:
- PRs: