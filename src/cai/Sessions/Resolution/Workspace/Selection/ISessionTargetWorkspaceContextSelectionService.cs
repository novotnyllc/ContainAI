using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace.Selection;

internal interface ISessionTargetWorkspaceContextSelectionService
{
    Task<ContextSelectionResult> ResolveContextAsync(string workspace, SessionCommandOptions options, CancellationToken cancellationToken);
}
