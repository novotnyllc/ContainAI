namespace ContainAI.Cli.Host;

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
