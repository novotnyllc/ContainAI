using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Containers;
using ContainAI.Cli.Host.Sessions.Resolution.Validation;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace.Selection;

namespace ContainAI.Cli.Host.Sessions.Resolution.Orchestration;

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
