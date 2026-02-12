using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Validation;
using ContainAI.Cli.Host.Sessions.Resolution.Workspace;

namespace ContainAI.Cli.Host.Sessions.Resolution.Containers;

internal sealed class SessionTargetDockerLookupService : ISessionTargetDockerLookupService
{
    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;
    private readonly ISessionDockerQueryRunner dockerQueryRunner;
    private readonly SessionContainerLabelReader containerLabelReader;
    private readonly SessionWorkspaceContainerLookupResolver workspaceContainerLookupResolver;
    private readonly SessionContainerNameReservationService containerNameReservationService;

    public SessionTargetDockerLookupService()
        : this(
            new SessionTargetWorkspaceDiscoveryService(),
            new SessionDockerQueryRunner(),
            new SessionWorkspaceConfigReader())
    {
    }

    internal SessionTargetDockerLookupService(
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService,
        ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        : this(
            sessionTargetWorkspaceDiscoveryService,
            new SessionDockerQueryRunner(),
            new SessionWorkspaceConfigReader(sessionTargetParsingValidationService))
    {
    }

    internal SessionTargetDockerLookupService(
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService,
        ISessionDockerQueryRunner sessionDockerQueryRunner,
        ISessionWorkspaceConfigReader sessionWorkspaceConfigReader)
    {
        workspaceDiscoveryService = sessionTargetWorkspaceDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDiscoveryService));
        dockerQueryRunner = sessionDockerQueryRunner ?? throw new ArgumentNullException(nameof(sessionDockerQueryRunner));
        var validatedWorkspaceConfigReader = sessionWorkspaceConfigReader ?? throw new ArgumentNullException(nameof(sessionWorkspaceConfigReader));

        containerLabelReader = new SessionContainerLabelReader(dockerQueryRunner);
        workspaceContainerLookupResolver = new SessionWorkspaceContainerLookupResolver(
            workspaceDiscoveryService,
            dockerQueryRunner,
            validatedWorkspaceConfigReader,
            containerLabelReader);
        containerNameReservationService = new SessionContainerNameReservationService(
            workspaceDiscoveryService,
            dockerQueryRunner,
            containerLabelReader);
    }

    public async Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
        => await containerLabelReader.ReadContainerLabelsAsync(containerName, context, cancellationToken).ConfigureAwait(false);

    public async Task<FindContainerByNameResult> FindContainerByNameAcrossContextsAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken)
    {
        var contexts = await workspaceDiscoveryService
            .BuildCandidateContextsAsync(workspace, explicitConfig, cancellationToken)
            .ConfigureAwait(false);

        var foundContexts = await dockerQueryRunner
            .FindContextsContainingContainerAsync(containerName, contexts, cancellationToken)
            .ConfigureAwait(false);

        return SessionTargetDockerLookupSelectionPolicy.SelectContainerContextCandidate(containerName, foundContexts);
    }

    public async Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken)
        => await workspaceContainerLookupResolver.FindWorkspaceContainerAsync(workspace, context, cancellationToken).ConfigureAwait(false);

    public async Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken)
        => await containerNameReservationService.ResolveContainerNameForCreationAsync(workspace, context, cancellationToken).ConfigureAwait(false);
}
