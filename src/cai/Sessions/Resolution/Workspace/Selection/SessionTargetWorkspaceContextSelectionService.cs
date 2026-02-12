using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace.Selection;

internal sealed class SessionTargetWorkspaceContextSelectionService : ISessionTargetWorkspaceContextSelectionService
{
    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;

    internal SessionTargetWorkspaceContextSelectionService(ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService)
        => workspaceDiscoveryService = sessionTargetWorkspaceDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDiscoveryService));

    public async Task<ContextSelectionResult> ResolveContextAsync(string workspace, SessionCommandOptions options, CancellationToken cancellationToken)
        => await workspaceDiscoveryService.ResolveContextForWorkspaceAsync(
            workspace,
            options.ExplicitConfig,
            options.Force,
            cancellationToken).ConfigureAwait(false);
}
