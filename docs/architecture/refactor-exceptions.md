# Contract/Implementation Separation: Approved Exceptions

Interfaces co-located with implementation classes were extracted into separate `I*.cs`
files across the ContainerRuntime, DockerProxy, and Devcontainer modules. The following
files retain co-located declarations under the approved exception rubric.

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

### Already-Separated (No Action Needed)

These files already contained only interface declarations prior to this refactor:

| File | Interfaces |
|---|---|
| `src/cai/ContainerRuntime/Handlers/ContainerRuntimeCommandHandlerInterfaces.cs` | `IContainerRuntimeSystemInitHandler`, `IContainerRuntimeSystemLinkRepairHandler`, `IContainerRuntimeSystemWatchLinksHandler`, `IContainerRuntimeRuntimeCommandHandler` |
| `src/cai/ContainerRuntime/Handlers/IContainerRuntimeLinkSpecProcessor.cs` | `IContainerRuntimeLinkSpecProcessor` |
| `src/cai/ContainerRuntime/Infrastructure/IContainerRuntimeExecutionContext.cs` | `IContainerRuntimeExecutionContext` |
| `src/cai/Devcontainer/Configuration/DevcontainerFeatureWorkflowContracts.cs` | `IDevcontainerFeatureInstallWorkflow`, `IDevcontainerFeatureInitWorkflow`, `IDevcontainerFeatureStartWorkflow`, `IDevcontainerFeatureSettingsFactory`, `IDevcontainerFeatureConfigLoader` |
| `src/cai/DockerProxy/Parsing/ParsingContracts.cs` | `IDockerProxyArgumentParser`, `IDevcontainerFeatureSettingsParser` |
