namespace ContainAI.Cli.Host;

internal interface ISessionTargetExplicitContainerResolver
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class SessionTargetExplicitContainerResolver : ISessionTargetExplicitContainerResolver
{
    private readonly ISessionTargetDockerLookupService dockerLookupService;
    private readonly ISessionTargetWorkspacePathOptionResolver workspacePathOptionResolver;
    private readonly ISessionTargetWorkspaceContextSelectionService workspaceContextSelectionService;
    private readonly ISessionTargetWorkspaceDataVolumeSelectionService workspaceDataVolumeSelectionService;
    private readonly ISessionTargetExplicitContainerTargetFactory explicitContainerTargetFactory;

    internal SessionTargetExplicitContainerResolver(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionTargetDockerLookupService sessionTargetDockerLookupService,
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService)
        : this(
            sessionTargetDockerLookupService,
            new SessionTargetWorkspacePathOptionResolver(sessionTargetParsingValidationService),
            new SessionTargetWorkspaceContextSelectionService(sessionTargetWorkspaceDiscoveryService),
            new SessionTargetWorkspaceDataVolumeSelectionService(sessionTargetWorkspaceDiscoveryService),
            new SessionTargetExplicitContainerTargetFactory())
    {
    }

    internal SessionTargetExplicitContainerResolver(
        ISessionTargetDockerLookupService sessionTargetDockerLookupService,
        ISessionTargetWorkspacePathOptionResolver sessionTargetWorkspacePathOptionResolver,
        ISessionTargetWorkspaceContextSelectionService sessionTargetWorkspaceContextSelectionService,
        ISessionTargetWorkspaceDataVolumeSelectionService sessionTargetWorkspaceDataVolumeSelectionService,
        ISessionTargetExplicitContainerTargetFactory sessionTargetExplicitContainerTargetFactory)
    {
        dockerLookupService = sessionTargetDockerLookupService ?? throw new ArgumentNullException(nameof(sessionTargetDockerLookupService));
        workspacePathOptionResolver = sessionTargetWorkspacePathOptionResolver ?? throw new ArgumentNullException(nameof(sessionTargetWorkspacePathOptionResolver));
        workspaceContextSelectionService = sessionTargetWorkspaceContextSelectionService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceContextSelectionService));
        workspaceDataVolumeSelectionService = sessionTargetWorkspaceDataVolumeSelectionService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDataVolumeSelectionService));
        explicitContainerTargetFactory = sessionTargetExplicitContainerTargetFactory ?? throw new ArgumentNullException(nameof(sessionTargetExplicitContainerTargetFactory));
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
            var labels = await dockerLookupService.ReadContainerLabelsAsync(options.Container!, found.Context!, cancellationToken).ConfigureAwait(false);
            var existingContainerTarget = explicitContainerTargetFactory.CreateFromExistingContainer(
                options,
                options.Container!,
                found.Context!,
                labels);
            if (!existingContainerTarget.Success)
            {
                return ResolvedTarget.ErrorResult(existingContainerTarget.Error!, existingContainerTarget.ErrorCode);
            }

            return existingContainerTarget.Value!;
        }

        var workspace = workspacePathOptionResolver.ResolveWorkspace(options);
        if (!workspace.Success)
        {
            return ResolvedTarget.ErrorResult(workspace.Error!, workspace.ErrorCode);
        }

        var contextSelection = await workspaceContextSelectionService.ResolveContextAsync(
            workspace.Value!,
            options,
            cancellationToken).ConfigureAwait(false);
        if (!contextSelection.Success)
        {
            return ResolvedTarget.ErrorResult(contextSelection.Error!, contextSelection.ErrorCode);
        }

        var volume = await workspaceDataVolumeSelectionService.ResolveVolumeAsync(
            workspace.Value!,
            options,
            allowResetVolume: false,
            cancellationToken).ConfigureAwait(false);
        if (!volume.Success)
        {
            return ResolvedTarget.ErrorResult(volume.Error!, volume.ErrorCode);
        }

        return new ResolvedTarget(
            ContainerName: options.Container!,
            Workspace: workspace.Value!,
            DataVolume: volume.Value!.DataVolume,
            Context: contextSelection.Context!,
            ShouldPersistState: true,
            CreatedByThisInvocation: true,
            GeneratedFromReset: false,
            Error: null,
            ErrorCode: 1);
    }
}
