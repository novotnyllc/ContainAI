using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Containers;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers.Lookup;

internal interface ISessionWorkspaceConfiguredContainerResolver
{
    Task<ContainerLookupResult?> TryResolveAsync(string workspace, string context, CancellationToken cancellationToken);
}
