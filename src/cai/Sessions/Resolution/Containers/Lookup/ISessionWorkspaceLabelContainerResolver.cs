using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Containers;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers.Lookup;

internal interface ISessionWorkspaceLabelContainerResolver
{
    Task<LabelContainerLookupResolution> ResolveAsync(string workspace, string context, CancellationToken cancellationToken);
}
