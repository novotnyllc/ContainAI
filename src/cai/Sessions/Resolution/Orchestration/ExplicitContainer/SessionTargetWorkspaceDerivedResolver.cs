using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace.Selection;

namespace ContainAI.Cli.Host.Sessions.Resolution.Orchestration.ExplicitContainer;

internal sealed class SessionTargetWorkspaceDerivedResolver(
    ISessionTargetWorkspacePathOptionResolver workspacePathOptionResolver,
    ISessionTargetWorkspaceContextSelectionService workspaceContextSelectionService,
    ISessionTargetWorkspaceDataVolumeSelectionService workspaceDataVolumeSelectionService) : ISessionTargetWorkspaceDerivedResolver
{
    public async Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
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
