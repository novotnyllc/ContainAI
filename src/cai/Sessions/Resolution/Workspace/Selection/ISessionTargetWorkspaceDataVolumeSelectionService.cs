using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace.Selection;

internal interface ISessionTargetWorkspaceDataVolumeSelectionService
{
    Task<ResolutionResult<SessionTargetVolumeSelection>> ResolveVolumeAsync(
        string workspace,
        SessionCommandOptions options,
        bool allowResetVolume,
        CancellationToken cancellationToken);
}
