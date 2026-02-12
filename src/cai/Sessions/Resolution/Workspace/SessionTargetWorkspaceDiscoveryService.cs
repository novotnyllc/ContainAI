using ContainAI.Cli.Host.Sessions.Infrastructure;
using ContainAI.Cli.Host.Sessions.Models;
using ContainAI.Cli.Host.Sessions.Resolution.Validation;

namespace ContainAI.Cli.Host.Sessions.Resolution.Workspace;

internal sealed class SessionTargetWorkspaceDiscoveryService : ISessionTargetWorkspaceDiscoveryService
{
    private readonly ISessionTargetContextDiscoveryService contextDiscoveryService;
    private readonly ISessionTargetDataVolumeResolutionService dataVolumeResolutionService;
    private readonly ISessionTargetContainerNameGenerationService containerNameGenerationService;

    public SessionTargetWorkspaceDiscoveryService()
        : this(new SessionTargetParsingValidationService(), new SessionRuntimeOperations())
    {
    }

    internal SessionTargetWorkspaceDiscoveryService(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        : this(sessionTargetParsingValidationService, new SessionRuntimeOperations())
    {
    }

    internal SessionTargetWorkspaceDiscoveryService(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionRuntimeOperations sessionRuntimeOperations)
        : this(
            new SessionTargetContextDiscoveryService(new SessionTargetConfiguredContextResolver(sessionRuntimeOperations), sessionRuntimeOperations),
            new SessionTargetDataVolumeResolutionService(sessionTargetParsingValidationService, sessionRuntimeOperations),
            new SessionTargetContainerNameGenerationService(sessionRuntimeOperations))
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
