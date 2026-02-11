namespace ContainAI.Cli.Host;

internal sealed partial class SessionTargetWorkspaceResolver
{
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
