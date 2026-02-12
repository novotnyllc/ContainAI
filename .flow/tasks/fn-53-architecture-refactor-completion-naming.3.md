# fn-53-architecture-refactor-completion-naming.3 ShellProfile, Manifests/Toml, AcpProxy, Install, Importing naming normalization

## Description
Rename dotted-basename files in 5 smaller modules: ShellProfile (6 files), Manifests/Toml (5 files), AcpProxy (1 file), Install (3 files), Importing (3 files).

**Size:** M
**Files:** 18 renames + ~20 dependent using-statement fixups

### Target files by module

**ShellProfile (6):**
- `ShellProfileIntegration.Constants.cs`, `.Contracts.cs`, `.ProfileFileMutation.cs`, `.ProfileScriptContentGeneration.cs`, `.Service.cs`, `.ShellDetectionAndPathResolution.cs`

**Manifests/Toml (5):**
- `ManifestTomlParser.Models.Agent.cs`, `.Models.Document.cs`, `.Models.Entry.cs`, `.Models.ManifestAgentEntry.cs`, `.Models.ManifestEntry.cs`

**AcpProxy (1):** `AcpProxyRunner.Process.cs`

**Install (3):** `InstallCommandRuntime.ExecutionFlow.cs`, `.OptionsAndEnvironment.cs`, `.OutputReporting.cs`

**Importing (3):** `CaiImportService.CommandSurface.cs`, `.ImportEnvironment.cs`, `.ImportOrchestration.cs`

### Approach
- Two-commit strategy per module batch: (1) `git mv` only, (2) namespace/using fixups
- ShellProfile: strip `ShellProfileIntegration.` prefix, move into subfolders (e.g., `FileOperations/`)
- Manifests/Toml: the 5 `ManifestTomlParser.Models.*.cs` files are `partial class` types with `[TomlSerializedObject]` — validate CsToml source generator compiles after rename. Keep partial classes in same folder.
- AcpProxy, Install, Importing: straightforward prefix stripping
- Update namespaces where modules currently use flat `ContainAI.Cli.Host`
- **Shared files:** Namespace fixup for Install and Importing modules may touch `CaiCommandRuntimeHandlersFactory.cs` and `Program.cs` for `using` additions. Coordinate with other Phase 1 tasks to serialize shared-file fixup commits.

### Key context
- CsToml source-generator edge case: `ManifestTomlDocument`, `ManifestTomlEntry`, `ManifestTomlAgent` are `partial class` with `[TomlSerializedObject]`. Renames are safe as long as all partial parts stay in same namespace. Build immediately after each rename to verify.
- `ShellProfileIntegration.cs` is a static facade (like DockerProxy) — preserved as-is
- Sessions/Models has 5 similar files (`SessionRuntimeModels.*.cs`) but those are in task 4
## Acceptance
- [ ] Zero dotted basenames in ShellProfile, Manifests/Toml, AcpProxy, Install, Importing modules (18 files renamed)
- [ ] CsToml source-generated partial classes compile correctly after rename
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing tests for affected modules pass unchanged
- [ ] `git log --follow` confirms rename detection
## Done summary
Renamed 18 dotted-basename files across 5 modules (ShellProfile, Manifests/Toml, AcpProxy, Install, Importing) to folder-based organization matching primary type names. Pure git mv with zero content changes; CsToml source-generated partial classes compile correctly.
## Evidence
- Commits: 48635b6471a6da8e3ef35749032ee1bb4ea53210
- Tests: dotnet build ContainAI.slnx -c Release -warnaserror, dotnet test --solution ContainAI.slnx -c Release --xunit-info
- PRs: