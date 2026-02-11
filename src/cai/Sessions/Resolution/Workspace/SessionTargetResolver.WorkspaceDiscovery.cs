namespace ContainAI.Cli.Host;

internal interface ISessionTargetWorkspaceDiscoveryService
{
    Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken);

    Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken);

    Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken);

    Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken);
}

internal sealed class SessionTargetWorkspaceDiscoveryService : ISessionTargetWorkspaceDiscoveryService
{
    private readonly ISessionTargetContextDiscoveryService contextDiscoveryService;
    private readonly ISessionTargetDataVolumeResolutionService dataVolumeResolutionService;
    private readonly ISessionTargetContainerNameGenerationService containerNameGenerationService;

    public SessionTargetWorkspaceDiscoveryService()
        : this(new SessionTargetParsingValidationService())
    {
    }

    internal SessionTargetWorkspaceDiscoveryService(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        : this(
            new SessionTargetContextDiscoveryService(new SessionTargetConfiguredContextResolver()),
            new SessionTargetDataVolumeResolutionService(sessionTargetParsingValidationService),
            new SessionTargetContainerNameGenerationService())
    {
    }

    internal SessionTargetWorkspaceDiscoveryService(
        ISessionTargetContextDiscoveryService sessionTargetContextDiscoveryService,
        ISessionTargetDataVolumeResolutionService sessionTargetDataVolumeResolutionService,
        ISessionTargetContainerNameGenerationService sessionTargetContainerNameGenerationService)
    {
        contextDiscoveryService = sessionTargetContextDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetContextDiscoveryService));
        dataVolumeResolutionService = sessionTargetDataVolumeResolutionService ?? throw new ArgumentNullException(nameof(sessionTargetDataVolumeResolutionService));
        containerNameGenerationService = sessionTargetContainerNameGenerationService ?? throw new ArgumentNullException(nameof(sessionTargetContainerNameGenerationService));
    }

    public async Task<ContextSelectionResult> ResolveContextForWorkspaceAsync(string workspace, string? explicitConfig, bool force, CancellationToken cancellationToken)
        => await contextDiscoveryService.ResolveContextForWorkspaceAsync(workspace, explicitConfig, force, cancellationToken).ConfigureAwait(false);

    public async Task<List<string>> BuildCandidateContextsAsync(string? workspace, string? explicitConfig, CancellationToken cancellationToken)
        => await contextDiscoveryService.BuildCandidateContextsAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);

    public async Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken)
        => await dataVolumeResolutionService.ResolveDataVolumeAsync(workspace, explicitVolume, explicitConfig, cancellationToken).ConfigureAwait(false);

    public async Task<string> GenerateContainerNameAsync(string workspace, CancellationToken cancellationToken)
        => await containerNameGenerationService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
}
