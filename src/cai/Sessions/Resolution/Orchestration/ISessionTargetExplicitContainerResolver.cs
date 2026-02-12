using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Containers;
using ContainAI.Cli.Host.Sessions.Resolution.Orchestration.ExplicitContainer;
using ContainAI.Cli.Host.Sessions.Resolution.Validation;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace.Selection;

namespace ContainAI.Cli.Host.Sessions.Resolution.Orchestration;

internal interface ISessionTargetExplicitContainerResolver
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}
