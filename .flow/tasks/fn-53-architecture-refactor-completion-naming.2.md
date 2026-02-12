# fn-53-architecture-refactor-completion-naming.2 DockerProxy naming normalization and folder restructure

## Description
Rename 26 dotted-basename files in `src/cai/DockerProxy/` to clean filenames within the existing folder structure.

**Size:** M
**Files:** 26 renames + ~15 dependent using-statement fixups

### Target files (audited, 26 total — exact old→new mapping)

| # | Current filename | New filename | Subfolder |
|---|-----------------|-------------|-----------|
| 1 | `ContainAiDockerProxy.ServiceContracts.cs` | `ServiceContracts.cs` | Contracts/ |
| 2 | `ContainAiDockerProxy.CommandExecutor.cs` | `CommandExecutor.cs` | Execution/ |
| 3 | `ContainAiDockerProxy.DockerProcessHelpers.cs` | `DockerProcessHelpers.cs` | Execution/ |
| 4 | `ContainAiDockerProxy.ProcessRunner.cs` | `ProcessRunner.cs` | Execution/ |
| 5 | `ContainAiDockerProxy.Models.cs` | `DockerProxyModels.cs` | Models/ |
| 6 | `ContainAiDockerProxy.Parsing.ArgumentParser.cs` | `ArgumentParser.cs` | Parsing/ |
| 7 | `ContainAiDockerProxy.Parsing.Contracts.cs` | `ParsingContracts.cs` | Parsing/ |
| 8 | `ContainAiDockerProxy.Parsing.Validation.cs` | `ParsingValidation.cs` | Parsing/ |
| 9 | `ContainAiDockerProxy.Parsing.Arguments.CommandParsing.cs` | `CommandParsing.cs` | Parsing/Arguments/ |
| 10 | `ContainAiDockerProxy.Parsing.Arguments.DevcontainerLabels.cs` | `DevcontainerLabels.cs` | Parsing/Arguments/ |
| 11 | `ContainAiDockerProxy.Parsing.Arguments.WrapperFlags.cs` | `WrapperFlags.cs` | Parsing/Arguments/ |
| 12 | `ContainAiDockerProxy.Parsing.FeatureSettings.cs` | `FeatureSettings.cs` | Parsing/FeatureSettings/ |
| 13 | `ContainAiDockerProxy.Parsing.FeatureSettings.Jsonc.cs` | `Jsonc.cs` | Parsing/FeatureSettings/ |
| 14 | `ContainAiDockerProxy.Parsing.FeatureSettings.Reader.cs` | `Reader.cs` | Parsing/FeatureSettings/ |
| 15 | `ContainAiDockerProxy.Parsing.FeatureSettings.ValueParsing.cs` | `ValueParsing.cs` | Parsing/FeatureSettings/ |
| 16 | `ContainAiDockerProxy.Parsing.FeatureSettingsParser.cs` | `FeatureSettingsParser.cs` | Parsing/FeatureSettings/ |
| 17 | `ContainAiDockerProxy.PortAllocation.cs` | `PortAllocation.cs` | Ports/ |
| 18 | `ContainAiDockerProxy.PortAllocation.Locking.cs` | `PortAllocationLocking.cs` | Ports/ |
| 19 | `ContainAiDockerProxy.PortAllocation.State.cs` | `PortAllocationState.cs` | Ports/ |
| 20 | `ContainAiDockerProxy.SshProfileUpdate.cs` | `SshProfileUpdate.cs` | System/ |
| 21 | `ContainAiDockerProxy.VolumeValidation.cs` | `VolumeValidation.cs` | System/ |
| 22 | `ContainAiDockerProxy.CoreWorkflow.cs` | `CoreWorkflow.cs` | Workflow/ |
| 23 | `ContainAiDockerProxy.CoreWorkflow.Output.cs` | `CoreWorkflowOutput.cs` | Workflow/ |
| 24 | `ContainAiDockerProxy.CoreWorkflow.RequestParsing.cs` | `CoreWorkflowRequestParsing.cs` | Workflow/ |
| 25 | `ContainAiDockerProxy.CreateWorkflow.cs` | `CreateWorkflow.cs` | Workflow/ |
| 26 | `ContainAiDockerProxy.PassthroughWorkflow.cs` | `PassthroughWorkflow.cs` | Workflow/ |

### Approach
- DockerProxy already has well-structured subfolders — files just need the `ContainAiDockerProxy.` prefix stripped from names
- Two-commit strategy: (1) `git mv` only, (2) namespace/using fixups
- Update namespaces from flat `ContainAI.Cli.Host` to `ContainAI.Cli.Host.DockerProxy.<Subfolder>`
- **Shared files:** Namespace fixup may touch `Program.cs` for `using` additions. Coordinate with other Phase 1 tasks to serialize shared-file fixup commits.

### Key context
- `ContainAiDockerProxy.cs` (static facade class at root) is a composition root — rename decision deferred to WS4
- All 28 DockerProxy files currently use flat `ContainAI.Cli.Host` namespace
- Tests: `ContainAiDockerProxyTests.cs` calls static methods on the facade — test API preserved
## Acceptance
- [ ] Zero dotted basenames in `src/cai/DockerProxy/` (26 files renamed per mapping table)
- [ ] All DockerProxy files use namespace matching folder hierarchy
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing DockerProxy tests pass unchanged
- [ ] `git log --follow` confirms rename detection for moved files
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
