namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetExplicitContainerResolver
{
    private async Task<ResolvedTarget> ResolveExistingContainerAsync(
        SessionCommandOptions options,
        string context,
        CancellationToken cancellationToken)
    {
        var labels = await dockerLookupService.ReadContainerLabelsAsync(options.Container!, context, cancellationToken).ConfigureAwait(false);
        var existingContainerTarget = explicitContainerTargetFactory.CreateFromExistingContainer(
            options,
            options.Container!,
            context,
            labels);
        if (!existingContainerTarget.Success)
        {
            return ResolvedTarget.ErrorResult(existingContainerTarget.Error!, existingContainerTarget.ErrorCode);
        }

        return existingContainerTarget.Value!;
    }

    private async Task<ResolvedTarget> ResolveWorkspaceDerivedAsync(SessionCommandOptions options, CancellationToken cancellationToken)
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
