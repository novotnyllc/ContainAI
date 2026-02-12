using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers;

internal interface ISessionTargetDockerLookupService
{
    Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken);

    Task<FindContainerByNameResult> FindContainerByNameAcrossContextsAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken);

    Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken);

    Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken);
}
