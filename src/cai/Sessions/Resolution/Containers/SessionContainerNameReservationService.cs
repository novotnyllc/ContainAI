using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers;

internal interface ISessionContainerNameReservationService
{
    Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken);
}

internal sealed class SessionContainerNameReservationService : ISessionContainerNameReservationService
{
    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;
    private readonly ISessionDockerQueryRunner dockerQueryRunner;
    private readonly ISessionContainerLabelReader containerLabelReader;

    public SessionContainerNameReservationService()
        : this(
            new SessionTargetWorkspaceDiscoveryService(),
            new SessionDockerQueryRunner(),
            new SessionContainerLabelReader())
    {
    }

    internal SessionContainerNameReservationService(
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService,
        ISessionDockerQueryRunner sessionDockerQueryRunner,
        ISessionContainerLabelReader sessionContainerLabelReader)
    {
        workspaceDiscoveryService = sessionTargetWorkspaceDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDiscoveryService));
        dockerQueryRunner = sessionDockerQueryRunner ?? throw new ArgumentNullException(nameof(sessionDockerQueryRunner));
        containerLabelReader = sessionContainerLabelReader ?? throw new ArgumentNullException(nameof(sessionContainerLabelReader));
    }

    public async Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var baseName = await workspaceDiscoveryService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        return await ResolveNameWithCollisionHandlingAsync(workspace, context, baseName, cancellationToken).ConfigureAwait(false);
    }

    private async Task<ResolutionResult<string>> ResolveNameWithCollisionHandlingAsync(
        string workspace,
        string context,
        string baseName,
        CancellationToken cancellationToken)
    {
        var candidate = baseName;
        for (var suffix = 1; suffix <= SessionTargetDockerLookupSelectionPolicy.MaxContainerNameCollisionAttempts; suffix++)
        {
            if (await IsNameAvailableOrOwnedByWorkspaceAsync(candidate, workspace, context, cancellationToken).ConfigureAwait(false))
            {
                return ResolutionResult<string>.SuccessResult(candidate);
            }

            candidate = SessionTargetDockerLookupSelectionPolicy.CreateCollisionCandidateName(baseName, suffix);
        }

        return ResolutionResult<string>.ErrorResult("Too many container name collisions (max 99)");
    }

    private async Task<bool> IsNameAvailableOrOwnedByWorkspaceAsync(
        string candidate,
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var inspect = await dockerQueryRunner.QueryContainerInspectAsync(candidate, context, cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            return true;
        }

        var labels = await containerLabelReader.ReadContainerLabelsAsync(candidate, context, cancellationToken).ConfigureAwait(false);
        return string.Equals(labels.Workspace, workspace, StringComparison.Ordinal);
    }
}
