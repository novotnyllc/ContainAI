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

internal interface ISessionTargetWorkspaceResolver
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class SessionTargetWorkspaceResolver : ISessionTargetWorkspaceResolver
{
    private readonly ISessionTargetWorkspacePathOptionResolver workspacePathOptionResolver;
    private readonly ISessionTargetWorkspaceDataVolumeSelectionService workspaceDataVolumeSelectionService;
    private readonly ISessionTargetWorkspaceContextSelectionService workspaceContextSelectionService;
    private readonly ISessionTargetWorkspaceContainerSelectionService workspaceContainerSelectionService;

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

    public async Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        var normalizedWorkspace = workspacePathOptionResolver.ResolveWorkspace(options);
        if (!normalizedWorkspace.Success)
        {
            return ResolvedTarget.ErrorResult(normalizedWorkspace.Error!, normalizedWorkspace.ErrorCode);
        }

        var resolvedVolume = await workspaceDataVolumeSelectionService.ResolveVolumeAsync(
            normalizedWorkspace.Value!,
            options,
            allowResetVolume: true,
            cancellationToken).ConfigureAwait(false);
        if (!resolvedVolume.Success)
        {
            return ResolvedTarget.ErrorResult(resolvedVolume.Error!, resolvedVolume.ErrorCode);
        }

        var contextResolved = await workspaceContextSelectionService.ResolveContextAsync(
            normalizedWorkspace.Value!,
            options,
            cancellationToken).ConfigureAwait(false);
        if (!contextResolved.Success)
        {
            return ResolvedTarget.ErrorResult(contextResolved.Error!, contextResolved.ErrorCode);
        }

        var containerResolved = await workspaceContainerSelectionService.ResolveContainerAsync(
            normalizedWorkspace.Value!,
            contextResolved.Context!,
            cancellationToken).ConfigureAwait(false);
        if (!containerResolved.Success)
        {
            return ResolvedTarget.ErrorResult(containerResolved.Error!, containerResolved.ErrorCode);
        }

        return new ResolvedTarget(
            ContainerName: containerResolved.Value!.ContainerName,
            Workspace: normalizedWorkspace.Value!,
            DataVolume: resolvedVolume.Value!.DataVolume,
            Context: contextResolved.Context!,
            ShouldPersistState: true,
            CreatedByThisInvocation: containerResolved.Value.CreatedByThisInvocation,
            GeneratedFromReset: resolvedVolume.Value.GeneratedFromReset,
            Error: null,
            ErrorCode: 1);
    }
}

internal sealed record SessionTargetVolumeSelection(string DataVolume, bool GeneratedFromReset);

internal sealed record SessionTargetContainerSelection(string ContainerName, bool CreatedByThisInvocation);

internal interface ISessionTargetWorkspacePathOptionResolver
{
    ResolutionResult<string> ResolveWorkspace(SessionCommandOptions options);
}

internal sealed class SessionTargetWorkspacePathOptionResolver : ISessionTargetWorkspacePathOptionResolver
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;

    internal SessionTargetWorkspacePathOptionResolver(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        => parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));

    public ResolutionResult<string> ResolveWorkspace(SessionCommandOptions options)
    {
        var workspaceInput = parsingValidationService.ResolveWorkspaceInput(options.Workspace);
        var normalized = parsingValidationService.NormalizeWorkspacePath(workspaceInput);
        if (!normalized.Success)
        {
            return ResolutionResult<string>.ErrorResult(normalized.Error!, normalized.ErrorCode);
        }

        return ResolutionResult<string>.SuccessResult(normalized.Value!);
    }
}

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

internal interface ISessionTargetWorkspaceDataVolumeSelectionService
{
    Task<ResolutionResult<SessionTargetVolumeSelection>> ResolveVolumeAsync(
        string workspace,
        SessionCommandOptions options,
        bool allowResetVolume,
        CancellationToken cancellationToken);
}

internal sealed class SessionTargetWorkspaceDataVolumeSelectionService : ISessionTargetWorkspaceDataVolumeSelectionService
{
    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;

    internal SessionTargetWorkspaceDataVolumeSelectionService(ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService)
        => workspaceDiscoveryService = sessionTargetWorkspaceDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDiscoveryService));

    public async Task<ResolutionResult<SessionTargetVolumeSelection>> ResolveVolumeAsync(
        string workspace,
        SessionCommandOptions options,
        bool allowResetVolume,
        CancellationToken cancellationToken)
    {
        var resolvedVolume = await workspaceDiscoveryService.ResolveDataVolumeAsync(
            workspace,
            options.DataVolume,
            options.ExplicitConfig,
            cancellationToken).ConfigureAwait(false);
        if (!resolvedVolume.Success)
        {
            return ResolutionResult<SessionTargetVolumeSelection>.ErrorResult(resolvedVolume.Error!, resolvedVolume.ErrorCode);
        }

        if (allowResetVolume && options.Mode == SessionMode.Shell && options.Reset)
        {
            return ResolutionResult<SessionTargetVolumeSelection>.SuccessResult(
                new SessionTargetVolumeSelection(
                    SessionRuntimeInfrastructure.GenerateWorkspaceVolumeName(workspace),
                    GeneratedFromReset: true));
        }

        return ResolutionResult<SessionTargetVolumeSelection>.SuccessResult(
            new SessionTargetVolumeSelection(resolvedVolume.Value!, GeneratedFromReset: false));
    }
}

internal interface ISessionTargetWorkspaceContainerSelectionService
{
    Task<ResolutionResult<SessionTargetContainerSelection>> ResolveContainerAsync(string workspace, string context, CancellationToken cancellationToken);
}

internal sealed class SessionTargetWorkspaceContainerSelectionService : ISessionTargetWorkspaceContainerSelectionService
{
    private readonly ISessionTargetDockerLookupService dockerLookupService;

    internal SessionTargetWorkspaceContainerSelectionService(ISessionTargetDockerLookupService sessionTargetDockerLookupService)
        => dockerLookupService = sessionTargetDockerLookupService ?? throw new ArgumentNullException(nameof(sessionTargetDockerLookupService));

    public async Task<ResolutionResult<SessionTargetContainerSelection>> ResolveContainerAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var existing = await dockerLookupService.FindWorkspaceContainerAsync(
            workspace,
            context,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(existing.Error))
        {
            return ResolutionResult<SessionTargetContainerSelection>.ErrorResult(existing.Error, existing.ErrorCode);
        }

        if (!string.IsNullOrWhiteSpace(existing.ContainerName))
        {
            return ResolutionResult<SessionTargetContainerSelection>.SuccessResult(
                new SessionTargetContainerSelection(existing.ContainerName, CreatedByThisInvocation: false));
        }

        var generated = await dockerLookupService.ResolveContainerNameForCreationAsync(
            workspace,
            context,
            cancellationToken).ConfigureAwait(false);
        if (!generated.Success)
        {
            return ResolutionResult<SessionTargetContainerSelection>.ErrorResult(generated.Error!, generated.ErrorCode);
        }

        return ResolutionResult<SessionTargetContainerSelection>.SuccessResult(
            new SessionTargetContainerSelection(generated.Value!, CreatedByThisInvocation: true));
    }
}

internal interface ISessionTargetExplicitContainerTargetFactory
{
    ResolutionResult<ResolvedTarget> CreateFromExistingContainer(
        SessionCommandOptions options,
        string containerName,
        string context,
        ContainerLabelState labels);
}

internal sealed class SessionTargetExplicitContainerTargetFactory : ISessionTargetExplicitContainerTargetFactory
{
    public ResolutionResult<ResolvedTarget> CreateFromExistingContainer(
        SessionCommandOptions options,
        string containerName,
        string context,
        ContainerLabelState labels)
    {
        if (!labels.IsOwned)
        {
            var code = options.Mode == SessionMode.Run ? 1 : 15;
            return ResolutionResult<ResolvedTarget>.ErrorResult($"Container '{containerName}' exists but was not created by ContainAI", code);
        }

        if (string.IsNullOrWhiteSpace(labels.Workspace))
        {
            return ResolutionResult<ResolvedTarget>.ErrorResult($"Container {containerName} is missing workspace label");
        }

        if (string.IsNullOrWhiteSpace(labels.DataVolume))
        {
            return ResolutionResult<ResolvedTarget>.ErrorResult($"Container {containerName} is missing data-volume label");
        }

        return ResolutionResult<ResolvedTarget>.SuccessResult(
            new ResolvedTarget(
                ContainerName: containerName,
                Workspace: labels.Workspace,
                DataVolume: labels.DataVolume,
                Context: context,
                ShouldPersistState: true,
                CreatedByThisInvocation: false,
                GeneratedFromReset: false,
                Error: null,
                ErrorCode: 1));
    }
}
