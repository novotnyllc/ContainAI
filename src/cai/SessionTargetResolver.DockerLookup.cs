namespace ContainAI.Cli.Host;

internal interface ISessionTargetDockerLookupService
{
    Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken);

    Task<FindContainerByNameResult> FindContainerByNameAcrossContextsAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken);

    Task<ContainerLookupResult> FindWorkspaceContainerAsync(string workspace, string context, CancellationToken cancellationToken);

    Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken);
}

internal sealed partial class SessionTargetDockerLookupService : ISessionTargetDockerLookupService
{
    private const string LabelInspectFormat =
        "{{index .Config.Labels \"containai.managed\"}}|{{index .Config.Labels \"containai.workspace\"}}|{{index .Config.Labels \"containai.data-volume\"}}|{{index .Config.Labels \"containai.ssh-port\"}}|{{.Config.Image}}|{{.State.Status}}";
    private const int LabelInspectFieldCount = 6;
    private const int MaxContainerNameCollisionAttempts = 99;
    private const int MaxDockerContainerNameLength = 24;

    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;
    private readonly ISessionTargetParsingValidationService parsingValidationService;

    public SessionTargetDockerLookupService()
        : this(new SessionTargetWorkspaceDiscoveryService(), new SessionTargetParsingValidationService())
    {
    }

    internal SessionTargetDockerLookupService(
        ISessionTargetWorkspaceDiscoveryService sessionTargetWorkspaceDiscoveryService,
        ISessionTargetParsingValidationService sessionTargetParsingValidationService)
    {
        workspaceDiscoveryService = sessionTargetWorkspaceDiscoveryService ?? throw new ArgumentNullException(nameof(sessionTargetWorkspaceDiscoveryService));
        parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));
    }

    public async Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
    {
        var inspect = await QueryContainerLabelFieldsAsync(containerName, context, cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            return ContainerLabelState.NotFound();
        }

        if (!TryParseContainerLabelFields(inspect.StandardOutput, out var parsed))
        {
            return ContainerLabelState.NotFound();
        }

        return BuildContainerLabelState(parsed);
    }

    public async Task<FindContainerByNameResult> FindContainerByNameAcrossContextsAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken)
    {
        var contextsContainingContainer = await FindContextsContainingContainerAsync(
            containerName,
            explicitConfig,
            workspace,
            cancellationToken).ConfigureAwait(false);

        return SelectContainerContextCandidate(containerName, contextsContainingContainer);
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

    public async Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var baseName = await workspaceDiscoveryService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        return await ResolveNameWithCollisionHandlingAsync(workspace, context, baseName, cancellationToken).ConfigureAwait(false);
    }
}
