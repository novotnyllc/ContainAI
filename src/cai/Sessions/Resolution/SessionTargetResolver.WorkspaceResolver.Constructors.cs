namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetWorkspaceResolver
{
    internal SessionTargetWorkspaceResolver(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionTargetDockerLookupService sessionTargetDockerLookupService,
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService)
        : this(
            new SessionTargetWorkspacePathOptionResolver(sessionTargetParsingValidationService),
            new SessionTargetWorkspaceDataVolumeSelectionService(sessionTargetWorkspaceDiscoveryService),
            new SessionTargetWorkspaceContextSelectionService(sessionTargetWorkspaceDiscoveryService),
            new SessionTargetWorkspaceContainerSelectionService(sessionTargetDockerLookupService))
    {
    }

    internal SessionTargetWorkspaceResolver(
        ISessionTargetWorkspacePathOptionResolver sessionTargetWorkspacePathOptionResolver,
        ISessionTargetWorkspaceDataVolumeSelectionService sessionTargetWorkspaceDataVolumeSelectionService,
        ISessionTargetWorkspaceContextSelectionService sessionTargetWorkspaceContextSelectionService,
        ISessionTargetWorkspaceContainerSelectionService sessionTargetWorkspaceContainerSelectionService)
    {
        workspacePathOptionResolver = sessionTargetWorkspacePathOptionResolver ?? throw new ArgumentNullException(nameof(sessionTargetWorkspacePathOptionResolver));
        workspaceDataVolumeSelectionService = sessionTargetWorkspaceDataVolumeSelectionService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDataVolumeSelectionService));
        workspaceContextSelectionService = sessionTargetWorkspaceContextSelectionService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceContextSelectionService));
        workspaceContainerSelectionService = sessionTargetWorkspaceContainerSelectionService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceContainerSelectionService));
    }
}
