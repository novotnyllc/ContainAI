namespace ContainAI.Cli.Host;

internal interface ISessionWorkspaceContainerLookupResolver
{
    Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken);
}

internal sealed class SessionWorkspaceContainerLookupResolver : ISessionWorkspaceContainerLookupResolver
{
    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;
    private readonly ISessionDockerQueryRunner dockerQueryRunner;
    private readonly ISessionWorkspaceConfigReader workspaceConfigReader;
    private readonly ISessionContainerLabelReader containerLabelReader;

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
    {
        workspaceDiscoveryService = sessionTargetWorkspaceDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDiscoveryService));
        dockerQueryRunner = sessionDockerQueryRunner ?? throw new ArgumentNullException(nameof(sessionDockerQueryRunner));
        workspaceConfigReader = sessionWorkspaceConfigReader ?? throw new ArgumentNullException(nameof(sessionWorkspaceConfigReader));
        containerLabelReader = sessionContainerLabelReader ?? throw new ArgumentNullException(nameof(sessionContainerLabelReader));
    }

    public async Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var configuredContainer = await TryResolveConfiguredWorkspaceContainerAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (configuredContainer is not null)
        {
            return configuredContainer;
        }

        var (continueSearch, byLabel) = await TryResolveWorkspaceContainerByLabelAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (!continueSearch)
        {
            return byLabel;
        }

        return await TryResolveGeneratedWorkspaceContainerAsync(workspace, context, cancellationToken).ConfigureAwait(false);
    }

    private async Task<(bool ContinueSearch, ContainerLookupResult Result)> TryResolveWorkspaceContainerByLabelAsync(
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var byLabel = await dockerQueryRunner.QueryContainersByWorkspaceLabelAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (byLabel.ExitCode != 0)
        {
            return (false, ContainerLookupResult.Empty());
        }

        var selection = SessionTargetDockerLookupSelectionPolicy.SelectLabelQueryCandidate(workspace, byLabel.StandardOutput);
        if (!selection.ContinueSearch || string.IsNullOrWhiteSpace(selection.ContainerId))
        {
            return (selection.ContinueSearch, selection.Result);
        }

        var nameResult = await dockerQueryRunner.QueryContainerNameByIdAsync(context, selection.ContainerId, cancellationToken).ConfigureAwait(false);
        if (nameResult.ExitCode == 0)
        {
            return (false, ContainerLookupResult.Success(SessionTargetDockerLookupParsing.ParseContainerName(nameResult.StandardOutput)));
        }

        return (true, ContainerLookupResult.Empty());
    }

    private async Task<ContainerLookupResult?> TryResolveConfiguredWorkspaceContainerAsync(
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var configuredName = await workspaceConfigReader
            .TryResolveWorkspaceContainerNameAsync(workspace, cancellationToken)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(configuredName))
        {
            return null;
        }

        var inspect = await dockerQueryRunner.QueryContainerInspectAsync(configuredName, context, cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            return null;
        }

        var labels = await containerLabelReader.ReadContainerLabelsAsync(configuredName, context, cancellationToken).ConfigureAwait(false);
        return string.Equals(labels.Workspace, workspace, StringComparison.Ordinal)
            ? ContainerLookupResult.Success(configuredName)
            : null;
    }

    private async Task<ContainerLookupResult> TryResolveGeneratedWorkspaceContainerAsync(
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var generated = await workspaceDiscoveryService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        var generatedExists = await dockerQueryRunner.QueryContainerInspectAsync(generated, context, cancellationToken).ConfigureAwait(false);

        return generatedExists.ExitCode == 0
            ? ContainerLookupResult.Success(generated)
            : ContainerLookupResult.Empty();
    }
}
