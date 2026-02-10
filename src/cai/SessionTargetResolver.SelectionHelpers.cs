namespace ContainAI.Cli.Host;

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
