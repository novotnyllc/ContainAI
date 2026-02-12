# Contract/Implementation Separation: Approved Exceptions

Interfaces co-located with implementation classes were extracted into separate `I*.cs`
files across all modules (ContainerRuntime, DockerProxy, Devcontainer, Sessions, Importing,
Operations, ContainerLinks, Install, ShellProfile, ConfigManifest, Toml, AcpProxy,
AgentShims, Examples, Infrastructure, Manifests). The following files retain co-located
declarations under the approved exception rubric.

## Exception Rubric

| Category | Criteria |
|---|---|
| **source-generator** | Type participates in `[JsonSerializable]`, `[GeneratedRegex]`, or similar source-gen that requires adjacency |
| **tiny-adapter** | Implementation is 15 non-blank lines and has a single consumer |
| **private-nested** | Interface is private/nested and not visible outside its containing type |

## Approved Exceptions

### Source-Generator

| File | Interface/Type | Reason |
|---|---|---|
| `src/cai/Devcontainer/DevcontainerFeatureModels.cs` | `DevcontainerFeatureJsonContext` | `[JsonSerializable]` source generator requires model types adjacent to the serialization context |

### Tiny-Adapter

| File | Interface | Lines | Consumer |
|---|---|---|---|
| `src/cai/ContainerRuntime/ContainerRuntimeLinkSpecFileReader.cs` | `IContainerRuntimeLinkSpecFileReader` | 6 | `ContainerRuntimeLinkSpecProcessor` |
| `src/cai/Operations/Maintenance/CaiDockerImagePuller.cs` | `ICaiDockerImagePuller` | 12 | `CaiRefreshOperations` |
| `src/cai/Operations/TemplateSshGc/Gc/CaiGcAgeParser.cs` | `ICaiGcAgeParser` | 11 | `CaiGcOperations` |

### Already-Separated (No Action Needed)

These files already contained only interface declarations prior to this refactor:

| File | Interfaces |
|---|---|
| `src/cai/ContainerRuntime/Handlers/ContainerRuntimeCommandHandlerInterfaces.cs` | `IContainerRuntimeSystemInitHandler`, `IContainerRuntimeSystemLinkRepairHandler`, `IContainerRuntimeSystemWatchLinksHandler`, `IContainerRuntimeRuntimeCommandHandler` |
| `src/cai/ContainerRuntime/Handlers/IContainerRuntimeLinkSpecProcessor.cs` | `IContainerRuntimeLinkSpecProcessor` |
| `src/cai/ContainerRuntime/Infrastructure/IContainerRuntimeExecutionContext.cs` | `IContainerRuntimeExecutionContext` |
| `src/cai/Devcontainer/Configuration/DevcontainerFeatureWorkflowContracts.cs` | `IDevcontainerFeatureInstallWorkflow`, `IDevcontainerFeatureInitWorkflow`, `IDevcontainerFeatureStartWorkflow`, `IDevcontainerFeatureSettingsFactory`, `IDevcontainerFeatureConfigLoader` |
| `src/cai/DockerProxy/Parsing/ParsingContracts.cs` | `IDockerProxyArgumentParser`, `IDevcontainerFeatureSettingsParser` |
| `src/cai/Sessions/Provisioning/ISessionSshBootstrapService.cs` | `ISessionSshBootstrapService` |
| `src/cai/Sessions/Resolution/Containers/SessionTargetDockerLookupAbstractions.cs` | `ISessionTargetDockerLookupService`, `ISessionTargetDockerLookupParsing`, `ISessionTargetDockerLookupSelectionPolicy` |
| `src/cai/Importing/Environment/IImportEnvironmentValueOperations.cs` | `IImportEnvironmentValueOperations` |
| `src/cai/Importing/Facade/Contracts/IImportEnvironmentOperations.cs` | `IImportEnvironmentOperations` |
| `src/cai/Importing/Facade/Contracts/IImportPathOperations.cs` | `IImportPathOperations` |
| `src/cai/Importing/Facade/Contracts/IImportTransferOperations.cs` | `IImportTransferOperations` |
| `src/cai/Importing/Orchestration/DirectoryImport/IDirectoryImportStep.cs` | `IDirectoryImportStep` |
| `src/cai/Importing/Paths/IImportAdditionalPathCatalog.cs` | `IImportAdditionalPathCatalog` |
| `src/cai/Importing/Paths/IImportAdditionalPathTransferOperations.cs` | `IImportAdditionalPathTransferOperations` |
| `src/cai/Importing/Symlinks/IImportSymlinkRelinker.cs` | `IImportSymlinkRelinker` |
| `src/cai/Importing/Symlinks/IImportSymlinkScanner.cs` | `IImportSymlinkScanner` |
| `src/cai/Importing/Symlinks/IPosixPathService.cs` | `IPosixPathService` |
| `src/cai/Importing/Transfer/IImportArchiveTransferOperations.cs` | `IImportArchiveTransferOperations` |
| `src/cai/Importing/Transfer/IImportManifestTransferOperations.cs` | `IImportManifestTransferOperations` |
| `src/cai/Importing/Transfer/IImportOverrideTransferOperations.cs` | `IImportOverrideTransferOperations` |
| `src/cai/Importing/Transfer/IImportSecretPermissionOperations.cs` | `IImportSecretPermissionOperations` |
| `src/cai/Operations/TemplateSshGc/Stop/ICaiStopTargetResolver.cs` | `ICaiStopTargetResolver` |
| `src/cai/Install/IInstallDeploymentService.cs` | `IInstallDeploymentService` |
| `src/cai/ShellProfile/ShellProfileIntegrationContracts.cs` | `IShellProfileIntegrationService`, `IShellProfileIntegration` |
| `src/cai/ConfigManifest/ConfigManifestContracts.cs` | `IConfigCommandProcessor`, `IManifestCommandProcessor` |
| `src/cai/Toml/Contracts/TomlCommandContracts.cs` | `ITomlCommandProcessor` |
| `src/cai/AgentShims/IAgentShimBinaryResolver.cs` | `IAgentShimBinaryResolver` |
| `src/cai/AgentShims/IAgentShimCommandLauncher.cs` | `IAgentShimCommandLauncher` |
| `src/cai/AgentShims/IAgentShimDefinitionResolver.cs` | `IAgentShimDefinitionResolver` |
| `src/cai/AgentShims/IAgentShimDispatcher.cs` | `IAgentShimDispatcher` |
| `src/cai/Examples/ExamplesDictionaryProvider.cs` | `IExamplesDictionaryProvider` |
| `src/cai/Manifests/Apply/IManifestAgentShimApplier.cs` | `IManifestAgentShimApplier` |
| `src/cai/Manifests/Apply/IManifestApplier.cs` | `IManifestApplier` |
| `src/cai/Manifests/Apply/IManifestContainerLinkApplier.cs` | `IManifestContainerLinkApplier` |
| `src/cai/Manifests/Apply/IManifestInitDirectoryApplier.cs` | `IManifestInitDirectoryApplier` |

### Contract/Model Files (No Interface Extraction Applicable)

These files contain models, enums, delegates, or source-generator contexts rather than
interface+class co-locations. No extraction action was needed.

| File | Contents |
|---|---|
| `src/cai/ContainerLinks/Repair/ContainerLinkRepairContracts.cs` | Models: `ContainerLinkRepairMode`, `EntryStateKind`, `ContainerLinkSpecDocument`, `ContainerLinkSpecEntry`; source-gen: `ContainerLinkSpecJsonContext` |
