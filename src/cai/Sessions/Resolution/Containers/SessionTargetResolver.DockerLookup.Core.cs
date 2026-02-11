namespace ContainAI.Cli.Host;

internal sealed class SessionTargetDockerLookupService : ISessionTargetDockerLookupService
{
    private readonly ISessionTargetWorkspaceDiscoveryService workspaceDiscoveryService;
    private readonly ISessionDockerQueryRunner dockerQueryRunner;
    private readonly ISessionWorkspaceConfigReader workspaceConfigReader;

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
        workspaceConfigReader = sessionWorkspaceConfigReader ?? throw new ArgumentNullException(nameof(sessionWorkspaceConfigReader));
    }

    public async Task<ContainerLabelState> ReadContainerLabelsAsync(string containerName, string context, CancellationToken cancellationToken)
    {
        var inspect = await dockerQueryRunner
            .QueryContainerLabelFieldsAsync(containerName, context, cancellationToken)
            .ConfigureAwait(false);

        return SessionTargetDockerLookupParsing.TryParseContainerLabelFields(inspect.StandardOutput, inspect.ExitCode, out var parsed)
            ? SessionTargetDockerLookupParsing.BuildContainerLabelState(parsed)
            : ContainerLabelState.NotFound();
    }

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

        var labels = await ReadContainerLabelsAsync(candidate, context, cancellationToken).ConfigureAwait(false);
        return string.Equals(labels.Workspace, workspace, StringComparison.Ordinal);
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
        var generatedExists = await dockerQueryRunner.QueryContainerInspectAsync(generated, context, cancellationToken).ConfigureAwait(false);

        return generatedExists.ExitCode == 0
            ? ContainerLookupResult.Success(generated)
            : ContainerLookupResult.Empty();
    }
}
