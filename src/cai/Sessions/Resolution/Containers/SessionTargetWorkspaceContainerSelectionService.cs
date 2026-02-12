namespace ContainAI.Cli.Host;

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
