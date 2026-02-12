# fn-53-architecture-refactor-completion-naming.6 Contract/implementation separation: P0 modules (ContainerRuntime, DockerProxy, Devcontainer)

## Description
Extract co-located interfaces from implementation files in P0 modules: ContainerRuntime (~25 mixed files), DockerProxy (~5 mixed files), Devcontainer (~25 mixed files). Create separate `I*.cs` files following .NET conventions.

**Size:** M
**Files:** ~55 files to evaluate, ~40-45 splits expected, ~10-15 approved exceptions

### Approach
- Process module by module: ContainerRuntime → DockerProxy → Devcontainer
- For each mixed file: extract `interface I*` declaration into adjacent `I*.cs` file in same folder
- Keep mixed only when:
  - Private nested helper type (e.g., inner class used only by the implementation)
  - Source-generator context pattern (e.g., `JsonSerializerContext` with its serializable types)
  - Tiny adapter where total interface + class is <15 lines
- Document each approved exception immediately in `docs/architecture/refactor-exceptions.md`
- Existing separate contract files serve as models: `DockerProxy/Contracts/`, `ShellProfile/ShellProfileIntegration.Contracts.cs`, `ConfigManifest/ConfigManifestContracts.cs`

### Key context
- Typical pattern (from `ContainerRuntimeCommandService.Initialization.cs:9-14`): interface + sealed class in one file
- DockerProxy already has a `Contracts/` subfolder and `Parsing/Contracts` — extend this pattern
- Source-generator exception: `DevcontainerFeatureJsonContext` and `ContainerLinkSpecJsonContext` must stay co-located with their types
- The dual-constructor pattern remains unchanged (WS4 scope)
## Acceptance
- [ ] All mixed files in ContainerRuntime, DockerProxy, Devcontainer evaluated
- [ ] Interface/class splits completed for non-exception files
- [ ] `docs/architecture/refactor-exceptions.md` created with approved exceptions list
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing tests pass unchanged
- [ ] slopwatch clean: `dotnet tool run slopwatch analyze -d . --fail-on warning`
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
