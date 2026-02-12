using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace.Selection;

namespace ContainAI.Cli.Host.Sessions.Resolution.Orchestration.ExplicitContainer;

internal interface ISessionTargetWorkspaceDerivedResolver
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}
