using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Models;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers;

internal interface ISessionTargetWorkspaceContainerSelectionService
{
    Task<ResolutionResult<SessionTargetContainerSelection>> ResolveContainerAsync(string workspace, string context, CancellationToken cancellationToken);
}
