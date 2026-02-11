namespace ContainAI.Cli.Host;

internal interface ISessionTargetResolver
{
    Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken);

    Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken);
}

internal sealed class SessionTargetResolver : ISessionTargetResolver
{
    private readonly ISessionTargetResolutionPipeline resolutionPipeline;
    private readonly ISessionTargetDockerLookupService dockerLookupService;

    public SessionTargetResolver()
        : this(new SessionTargetResolutionPipeline(), new SessionTargetDockerLookupService())
    {
    }

    internal SessionTargetResolver(
        ISessionTargetResolutionPipeline sessionTargetResolutionPipeline,
        ISessionTargetDockerLookupService sessionTargetDockerLookupService)
    {
        resolutionPipeline = sessionTargetResolutionPipeline ?? throw new ArgumentNullException(nameof(sessionTargetResolutionPipeline));
        dockerLookupService = sessionTargetDockerLookupService ?? throw new ArgumentNullException(nameof(sessionTargetDockerLookupService));
    }

    public Task<ResolvedTarget> ResolveAsync(SessionCommandOptions options, CancellationToken cancellationToken)
        => resolutionPipeline.ResolveAsync(options, cancellationToken);

    public Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
        => dockerLookupService.ReadContainerLabelsAsync(containerName, context, cancellationToken);
}
