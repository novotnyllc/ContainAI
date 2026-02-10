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

    private async Task<ContainerLookupResult?> TryResolveConfiguredWorkspaceContainerAsync(
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var configPath = SessionRuntimeInfrastructure.ResolveUserConfigPath();
        if (!File.Exists(configPath))
        {
            return null;
        }

        var workspaceState = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);
        if (workspaceState.ExitCode != 0 || string.IsNullOrWhiteSpace(workspaceState.StandardOutput))
        {
            return null;
        }

        var configuredName = parsingValidationService.TryReadWorkspaceStringProperty(workspaceState.StandardOutput, "container_name");
        if (string.IsNullOrWhiteSpace(configuredName))
        {
            return null;
        }

        var inspect = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", configuredName],
            cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            return null;
        }

        var labels = await ReadContainerLabelsAsync(configuredName, context, cancellationToken).ConfigureAwait(false);
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
        var generatedExists = await SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", generated],
            cancellationToken).ConfigureAwait(false);

        return generatedExists.ExitCode == 0
            ? ContainerLookupResult.Success(generated)
            : ContainerLookupResult.Empty();
    }
}
