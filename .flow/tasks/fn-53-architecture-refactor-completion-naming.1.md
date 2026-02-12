# fn-53-architecture-refactor-completion-naming.1 ContainerRuntime naming normalization and folder restructure

## Description
Rename 15 dotted-basename files in `src/cai/ContainerRuntime/` to folder-based organization and align namespaces.

**Size:** M
**Files:** ~15 renames + ~30 dependent using-statement fixups

### Target files
- `ContainerRuntimeCommandService.CommandDispatch.cs`
- `ContainerRuntimeCommandService.CommandWiring.DevcontainerForwarders.cs`
- `ContainerRuntimeCommandService.CommandWiring.Init.cs`
- `ContainerRuntimeCommandService.CommandWiring.LinkRepair.cs`
- `ContainerRuntimeCommandService.CommandWiring.LinkWatcher.cs`
- `ContainerRuntimeCommandService.EnvFile.cs`
- `ContainerRuntimeCommandService.GitConfigMigration.cs`
- `ContainerRuntimeCommandService.Initialization.cs`
- `ContainerRuntimeCommandService.LinkSpecParsing.Construction.cs`
- `ContainerRuntimeCommandService.LinkSpecParsing.cs`
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

### Key context
- ContainerRuntime already has 4/49 files using sub-namespaces; expand this to all files
- `ContainerRuntimeCommandService.cs` (the main class) stays in place; only the dotted pseudo-partials move
- Cross-module concrete dep: `ContainerRuntimeCommandService.cs:48` directly instantiates `new DevcontainerFeatureRuntime()` — do NOT change this (WS4 scope)
## Acceptance
- [ ] Zero dotted basenames in `src/cai/ContainerRuntime/`
- [ ] All ContainerRuntime files use namespace matching folder hierarchy
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing ContainerRuntime tests pass unchanged
- [ ] `git log --follow` confirms rename detection for moved files
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
