namespace ContainAI.Cli.Host;

internal interface ISessionTargetWorkspaceResolver
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}

internal sealed partial class SessionTargetWorkspaceResolver : ISessionTargetWorkspaceResolver
{
    private readonly ISessionTargetWorkspacePathOptionResolver workspacePathOptionResolver;
    private readonly ISessionTargetWorkspaceDataVolumeSelectionService workspaceDataVolumeSelectionService;
    private readonly ISessionTargetWorkspaceContextSelectionService workspaceContextSelectionService;
    private readonly ISessionTargetWorkspaceContainerSelectionService workspaceContainerSelectionService;
}
