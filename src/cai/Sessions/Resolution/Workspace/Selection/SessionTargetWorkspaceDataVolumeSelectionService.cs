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

internal sealed class SessionTargetWorkspaceDataVolumeSelectionService : ISessionTargetWorkspaceDataVolumeSelectionService
{
    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;
    private readonly ISessionRuntimeOperations runtimeOperations;

    internal SessionTargetWorkspaceDataVolumeSelectionService(ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService)
        : this(sessionTargetWorkspaceDiscoveryService, new SessionRuntimeOperations())
    {
    }

    internal SessionTargetWorkspaceDataVolumeSelectionService(
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService,
        ISessionRuntimeOperations sessionRuntimeOperations)
    {
        workspaceDiscoveryService = sessionTargetWorkspaceDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDiscoveryService));
        runtimeOperations = sessionRuntimeOperations ?? throw new ArgumentNullException(nameof(sessionRuntimeOperations));
    }

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
                    runtimeOperations.GenerateWorkspaceVolumeName(workspace),
                    GeneratedFromReset: true));
        }

        return ResolutionResult<SessionTargetVolumeSelection>.SuccessResult(
            new SessionTargetVolumeSelection(resolvedVolume.Value!, GeneratedFromReset: false));
    }
}
