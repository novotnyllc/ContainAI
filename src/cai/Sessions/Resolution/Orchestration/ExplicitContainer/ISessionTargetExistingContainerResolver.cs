using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Containers;
using ContainAI.Cli.Host.Sessions.Resolution.Orchestration;

namespace ContainAI.Cli.Host.Sessions.Resolution.Orchestration.ExplicitContainer;

internal interface ISessionTargetExistingContainerResolver
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, string context, CancellationToken cancellationToken);
}
