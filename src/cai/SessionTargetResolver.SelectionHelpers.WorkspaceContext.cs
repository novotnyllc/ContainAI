namespace ContainAI.Cli.Host;

internal interface ISessionTargetWorkspaceContextSelectionService
{
    Task<ContextSelectionResult> ResolveContextAsync(string workspace, SessionCommandOptions options, CancellationToken cancellationToken);
}

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
