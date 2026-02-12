# fn-53-architecture-refactor-completion-naming.2 DockerProxy naming normalization and folder restructure

## Description
Rename 25 dotted-basename files in `src/cai/DockerProxy/` to clean filenames within the existing folder structure.

**Size:** M
**Files:** ~25 renames + ~15 dependent using-statement fixups

### Target files (by existing subfolder)
**Contracts/** (1): `ContainAiDockerProxy.ServiceContracts.cs`
**Execution/** (3): `ContainAiDockerProxy.CommandExecutor.cs`, `.DockerProcessHelpers.cs`, `.ProcessRunner.cs`
**Models/** (1): `ContainAiDockerProxy.Models.cs`
**Parsing/** (6): `ContainAiDockerProxy.Parsing.ArgumentParser.cs`, `.Parsing.Contracts.cs`, `.Parsing.Validation.cs`, and 3 in `Arguments/`, 5 in `FeatureSettings/`
**Ports/** (3): `ContainAiDockerProxy.PortAllocation.cs`, `.PortAllocation.Locking.cs`, `.PortAllocation.State.cs`
**System/** (2): `ContainAiDockerProxy.SshProfileUpdate.cs`, `.VolumeValidation.cs`
**Workflow/** (5): `ContainAiDockerProxy.CoreWorkflow.cs`, `.CoreWorkflow.Output.cs`, `.CoreWorkflow.RequestParsing.cs`, `.CreateWorkflow.cs`, `.PassthroughWorkflow.cs`

### Approach
- DockerProxy already has well-structured subfolders — files just need the `ContainAiDockerProxy.` prefix stripped from names
- Example: `ContainAiDockerProxy.Parsing.ArgumentParser.cs` → `Parsing/DockerProxyArgumentParser.cs`
- Two-commit strategy: (1) `git mv` only, (2) namespace/using fixups
- Update namespaces from flat `ContainAI.Cli.Host` to `ContainAI.Cli.Host.DockerProxy.<Subfolder>`
- Fix `RegexOptions.Compiled` → `RegexOptions.CultureInvariant` on 3 `[GeneratedRegex]` usages (opportunistic cleanup, not a behavioral change)

### Key context
- `ContainAiDockerProxy.cs` (static facade class at root) is a composition root — rename decision deferred to WS4
- All 28 DockerProxy files currently use flat `ContainAI.Cli.Host` namespace
- Tests: `ContainAiDockerProxyTests.cs` calls static methods on the facade — test API preserved
## Acceptance
- [ ] Zero dotted basenames in `src/cai/DockerProxy/`
- [ ] All DockerProxy files use namespace matching folder hierarchy
- [ ] RegexOptions.Compiled replaced with RegexOptions.CultureInvariant on [GeneratedRegex] usages
- [ ] `dotnet build ContainAI.slnx -c Release -warnaserror` passes
- [ ] All existing DockerProxy tests pass unchanged
- [ ] `git log --follow` confirms rename detection for moved files
## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
