# fn-53-architecture-refactor-completion-naming.6 Contract/implementation separation: P0 modules (ContainerRuntime, DockerProxy, Devcontainer)

## Description
Extract co-located interfaces from implementation files in P0 modules: ContainerRuntime (~25 mixed files), DockerProxy (~5 mixed files), Devcontainer (~25 mixed files). Create separate `I*.cs` files following .NET conventions.

**Size:** M
**Files:** ~55 files to evaluate, ~40-45 splits expected, ~10-15 approved exceptions

### Approach
- Process module by module: ContainerRuntime → DockerProxy → Devcontainer
- For each mixed file: extract `interface I*` declaration into adjacent `I*.cs` file in same folder
- Document each approved exception immediately in `docs/architecture/refactor-exceptions.md`
- Existing separate contract files serve as models: `DockerProxy/Contracts/`, `ShellProfile/ShellProfileIntegration.Contracts.cs`, `ConfigManifest/ConfigManifestContracts.cs`

### Exception rubric
Keep mixed only when one of these applies:
1. **Private nested helper:** Inner type used only by the containing class, not visible outside assembly
2. **Source-generator context:** Type decorated with source-generator attributes (e.g., `[TomlSerializedObject]`, `[JsonSerializable]`) that must stay co-located with generated code
3. **Tiny adapter:** Total combined interface + class body ≤15 non-blank, non-comment lines (measured by `wc -l` after stripping blank lines and `//` comments)

**Anti-pattern:** Do not use "convenience" as justification. If an interface is used by more than one consumer, it must be separated regardless of size.

**Required fields per exception entry in `docs/architecture/refactor-exceptions.md`:**
- File path
- Exception type (one of: private-nested, source-generator, tiny-adapter)
- Justification (one sentence)
- Line count (required for tiny-adapter type)

### Key context
- Typical pattern (from `ContainerRuntimeCommandService.Initialization.cs:9-14`): interface + sealed class in one file
- DockerProxy already has a `Contracts/` subfolder and `Parsing/Contracts` — extend this pattern
- Source-generator exception: `DevcontainerFeatureJsonContext` and `ContainerLinkSpecJsonContext` must stay co-located with their types
- The dual-constructor pattern remains unchanged (WS4 scope)
## Acceptance
- [ ] All mixed files in ContainerRuntime, DockerProxy, Devcontainer evaluated
- [ ] Interface/class splits completed for non-exception files
- [ ] `docs/architecture/refactor-exceptions.md` created with approved exceptions (per rubric: file path, exception type, justification, line count)
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing tests pass unchanged
- [ ] slopwatch clean: `dotnet tool run slopwatch analyze -d . --fail-on warning`
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
