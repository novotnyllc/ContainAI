namespace ContainAI.Cli.Host;

internal interface ISessionTargetResolutionPipeline
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken);
}

internal sealed class SessionTargetResolutionPipeline : ISessionTargetResolutionPipeline
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;
    private readonly ISessionTargetExplicitContainerResolver explicitContainerResolver;
    private readonly ISessionTargetWorkspaceResolver workspaceResolver;

    public SessionTargetResolutionPipeline()
        : this(
            new SessionTargetParsingValidationService(),
            new SessionTargetDockerLookupService(),
            new SessionTargetWorkspaceDiscoveryService())
    {
    }

    internal SessionTargetResolutionPipeline(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionTargetDockerLookupService sessionTargetDockerLookupService,
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService)
        : this(
            sessionTargetParsingValidationService,
            new SessionTargetExplicitContainerResolver(
                sessionTargetParsingValidationService,
                sessionTargetDockerLookupService,
                sessionTargetWorkspaceDiscoveryService),
            new SessionTargetWorkspaceResolver(
                sessionTargetParsingValidationService,
                sessionTargetDockerLookupService,
                sessionTargetWorkspaceDiscoveryService))
    {
    }

    internal SessionTargetResolutionPipeline(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionTargetExplicitContainerResolver sessionTargetExplicitContainerResolver,
        ISessionTargetWorkspaceResolver sessionTargetWorkspaceResolver)
    {
        parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));
        explicitContainerResolver = sessionTargetExplicitContainerResolver ?? throw new ArgumentNullException(nameof(sessionTargetExplicitContainerResolver));
        workspaceResolver = sessionTargetWorkspaceResolver ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceResolver));
    }

    public async Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken)
    {
        var validationError = parsingValidationService.ValidateOptions(options);
        if (validationError is not null)
        {
            return validationError;
        }

        if (!string.IsNullOrWhiteSpace(options.Container))
        {
            return await explicitContainerResolver.ResolveAsync(options, cancellationToken).ConfigureAwait(false);
        }

        return await workspaceResolver.ResolveAsync(options, cancellationToken).ConfigureAwait(false);
    }
}
