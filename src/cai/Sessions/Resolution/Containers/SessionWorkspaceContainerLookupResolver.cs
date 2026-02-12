namespace ContainAI.Cli.Host;

internal interface ISessionWorkspaceContainerLookupResolver
{
    Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken);
}

internal sealed class SessionWorkspaceContainerLookupResolver : ISessionWorkspaceContainerLookupResolver
{
    private readonly ISessionWorkspaceConfiguredContainerResolver configuredContainerResolver;
    private readonly ISessionWorkspaceLabelContainerResolver labelContainerResolver;
    private readonly ISessionWorkspaceGeneratedContainerResolver generatedContainerResolver;

    public SessionWorkspaceContainerLookupResolver()
        : this(
            new SessionTargetWorkspaceDiscoveryService(),
            new SessionDockerQueryRunner(),
            new SessionWorkspaceConfigReader(),
            new SessionContainerLabelReader())
    {
    }

    internal SessionWorkspaceContainerLookupResolver(
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService,
        ISessionDockerQueryRunner sessionDockerQueryRunner,
        ISessionWorkspaceConfigReader sessionWorkspaceConfigReader,
        ISessionContainerLabelReader sessionContainerLabelReader)
        : this(
            new SessionWorkspaceConfiguredContainerResolver(
                sessionDockerQueryRunner,
                sessionWorkspaceConfigReader,
                sessionContainerLabelReader),
            new SessionWorkspaceLabelContainerResolver(sessionDockerQueryRunner),
            new SessionWorkspaceGeneratedContainerResolver(
                sessionTargetWorkspaceDiscoveryService,
                sessionDockerQueryRunner))
    {
    }

    internal SessionWorkspaceContainerLookupResolver(
        ISessionWorkspaceConfiguredContainerResolver sessionWorkspaceConfiguredContainerResolver,
        ISessionWorkspaceLabelContainerResolver sessionWorkspaceLabelContainerResolver,
        ISessionWorkspaceGeneratedContainerResolver sessionWorkspaceGeneratedContainerResolver)
    {
        configuredContainerResolver = sessionWorkspaceConfiguredContainerResolver ?? throw new ArgumentNullException(nameof(sessionWorkspaceConfiguredContainerResolver));
        labelContainerResolver = sessionWorkspaceLabelContainerResolver ?? throw new ArgumentNullException(nameof(sessionWorkspaceLabelContainerResolver));
        generatedContainerResolver = sessionWorkspaceGeneratedContainerResolver ?? throw new ArgumentNullException(nameof(sessionWorkspaceGeneratedContainerResolver));
    }

    public async Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var configuredContainer = await configuredContainerResolver.TryResolveAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (configuredContainer is not null)
        {
            return configuredContainer;
        }

        var byLabel = await labelContainerResolver.ResolveAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (!byLabel.ContinueSearch)
        {
            return byLabel.Result;
        }

        return await generatedContainerResolver.ResolveAsync(workspace, context, cancellationToken).ConfigureAwait(false);
    }
}
