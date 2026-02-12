namespace ContainAI.Cli.Host;

internal interface ISessionTargetExplicitContainerResolver
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class SessionTargetExplicitContainerResolver : ISessionTargetExplicitContainerResolver
{
    private readonly ISessionTargetDockerLookupService dockerLookupService;
    private readonly ISessionTargetExistingContainerResolver existingContainerResolver;
    private readonly ISessionTargetWorkspaceDerivedResolver workspaceDerivedResolver;

    internal SessionTargetExplicitContainerResolver(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionTargetDockerLookupService sessionTargetDockerLookupService,
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService)
        : this(
            sessionTargetDockerLookupService,
            new SessionTargetExistingContainerResolver(
                sessionTargetDockerLookupService,
                new SessionTargetExplicitContainerTargetFactory()),
            new SessionTargetWorkspaceDerivedResolver(
                new SessionTargetWorkspacePathOptionResolver(sessionTargetParsingValidationService),
                new SessionTargetWorkspaceContextSelectionService(sessionTargetWorkspaceDiscoveryService),
                new SessionTargetWorkspaceDataVolumeSelectionService(sessionTargetWorkspaceDiscoveryService)))
    {
    }

    internal SessionTargetExplicitContainerResolver(
        ISessionTargetDockerLookupService sessionTargetDockerLookupService,
        ISessionTargetExistingContainerResolver sessionTargetExistingContainerResolver,
        ISessionTargetWorkspaceDerivedResolver sessionTargetWorkspaceDerivedResolver)
    {
        dockerLookupService = sessionTargetDockerLookupService ?? throw new ArgumentNullException(nameof(sessionTargetDockerLookupService));
        existingContainerResolver = sessionTargetExistingContainerResolver ?? throw new ArgumentNullException(nameof(sessionTargetExistingContainerResolver));
        workspaceDerivedResolver = sessionTargetWorkspaceDerivedResolver ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDerivedResolver));
    }

    public async Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        var found = await dockerLookupService.FindContainerByNameAcrossContextsAsync(
            options.Container!,
            options.ExplicitConfig,
            options.Workspace,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(found.Error))
        {
            return ResolvedTarget.ErrorResult(found.Error, found.ErrorCode);
        }

        if (found.Exists)
        {
            return await existingContainerResolver.ResolveAsync(options, found.Context!, cancellationToken).ConfigureAwait(false);
        }

        return await workspaceDerivedResolver.ResolveAsync(options, cancellationToken).ConfigureAwait(false);
    }
}
