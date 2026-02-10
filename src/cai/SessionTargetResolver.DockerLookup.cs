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

internal sealed class SessionTargetDockerLookupService : ISessionTargetDockerLookupService
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

    private static async Task<(bool ContinueSearch, ContainerLookupResult Result)> TryResolveWorkspaceContainerByLabelAsync(
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var byLabel = await QueryContainersByWorkspaceLabelAsync(workspace, context, cancellationToken).ConfigureAwait(false);
        if (byLabel.ExitCode != 0)
        {
            return (false, ContainerLookupResult.Empty());
        }

        var selection = SelectLabelQueryCandidate(workspace, byLabel.StandardOutput);
        if (!selection.ContinueSearch || string.IsNullOrWhiteSpace(selection.ContainerId))
        {
            return (selection.ContinueSearch, selection.Result);
        }

        var nameResult = await QueryContainerNameByIdAsync(context, selection.ContainerId, cancellationToken).ConfigureAwait(false);
        if (nameResult.ExitCode == 0)
        {
            return (false, ContainerLookupResult.Success(ParseContainerName(nameResult.StandardOutput)));
        }

        return (true, ContainerLookupResult.Empty());
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

    public async Task<ResolutionResult<string>> ResolveContainerNameForCreationAsync(string workspace, string context, CancellationToken cancellationToken)
    {
        var baseName = await workspaceDiscoveryService.GenerateContainerNameAsync(workspace, cancellationToken).ConfigureAwait(false);
        return await ResolveNameWithCollisionHandlingAsync(workspace, context, baseName, cancellationToken).ConfigureAwait(false);
    }

    private static Task<ProcessResult> QueryContainerLabelFieldsAsync(string containerName, string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--format", LabelInspectFormat, containerName],
            cancellationToken);

    private static Task<ProcessResult> QueryContainerInspectAsync(string containerName, string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--type", "container", containerName],
            cancellationToken);

    private static Task<ProcessResult> QueryContainersByWorkspaceLabelAsync(string workspace, string context, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["ps", "-aq", "--filter", $"label={SessionRuntimeConstants.WorkspaceLabelKey}={workspace}"],
            cancellationToken);

    private static Task<ProcessResult> QueryContainerNameByIdAsync(string context, string containerId, CancellationToken cancellationToken)
        => SessionRuntimeInfrastructure.DockerCaptureAsync(
            context,
            ["inspect", "--format", "{{.Name}}", containerId],
            cancellationToken);

    private async Task<List<string>> FindContextsContainingContainerAsync(
        string containerName,
        string? explicitConfig,
        string? workspace,
        CancellationToken cancellationToken)
    {
        var contexts = await workspaceDiscoveryService.BuildCandidateContextsAsync(workspace, explicitConfig, cancellationToken).ConfigureAwait(false);
        var foundContexts = new List<string>();

        foreach (var context in contexts)
        {
            var inspect = await SessionRuntimeInfrastructure.RunProcessCaptureAsync(
                "docker",
                ["--context", context, "inspect", "--type", "container", "--", containerName],
                cancellationToken).ConfigureAwait(false);
            if (inspect.ExitCode == 0)
            {
                foundContexts.Add(context);
            }
        }

        return foundContexts;
    }

    private static FindContainerByNameResult SelectContainerContextCandidate(string containerName, List<string> foundContexts)
    {
        if (foundContexts.Count == 0)
        {
            return new FindContainerByNameResult(false, null, null, 1);
        }

        if (foundContexts.Count > 1)
        {
            return new FindContainerByNameResult(
                false,
                null,
                $"Container '{containerName}' exists in multiple contexts: {string.Join(", ", foundContexts)}",
                1);
        }

        return new FindContainerByNameResult(true, foundContexts[0], null, 1);
    }

    private static bool TryParseContainerLabelFields(string inspectOutput, out ContainerLabelFields fields)
    {
        var parts = inspectOutput.Trim().Split('|');
        if (parts.Length < LabelInspectFieldCount)
        {
            fields = default;
            return false;
        }

        fields = new ContainerLabelFields(
            parts[0],
            parts[1],
            parts[2],
            parts[3],
            parts[4],
            parts[5]);
        return true;
    }

    private static ContainerLabelState BuildContainerLabelState(ContainerLabelFields fields)
    {
        var managed = string.Equals(fields.ManagedLabel, SessionRuntimeConstants.ManagedLabelValue, StringComparison.Ordinal);
        var owned = managed || SessionRuntimeInfrastructure.IsContainAiImage(fields.Image);

        return new ContainerLabelState(
            Exists: true,
            IsOwned: owned,
            Workspace: SessionRuntimeInfrastructure.NormalizeNoValue(fields.WorkspaceLabel),
            DataVolume: SessionRuntimeInfrastructure.NormalizeNoValue(fields.DataVolumeLabel),
            SshPort: SessionRuntimeInfrastructure.NormalizeNoValue(fields.SshPortLabel),
            State: SessionRuntimeInfrastructure.NormalizeNoValue(fields.State));
    }

    private static LabelQueryCandidateSelection SelectLabelQueryCandidate(string workspace, string standardOutput)
    {
        var ids = ParseDockerOutputLines(standardOutput);
        return ids.Length switch
        {
            0 => new LabelQueryCandidateSelection(true, null, ContainerLookupResult.Empty()),
            1 => new LabelQueryCandidateSelection(true, ids[0], ContainerLookupResult.Empty()),
            _ => new LabelQueryCandidateSelection(
                false,
                null,
                ContainerLookupResult.FromError($"Multiple containers found for workspace: {workspace}")),
        };
    }

    private static string ParseContainerName(string inspectOutput)
        => inspectOutput.Trim().TrimStart('/');

    private static string[] ParseDockerOutputLines(string output)
        => output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    private async Task<ResolutionResult<string>> ResolveNameWithCollisionHandlingAsync(
        string workspace,
        string context,
        string baseName,
        CancellationToken cancellationToken)
    {
        var candidate = baseName;
        for (var suffix = 1; suffix <= MaxContainerNameCollisionAttempts; suffix++)
        {
            if (await IsNameAvailableOrOwnedByWorkspaceAsync(candidate, workspace, context, cancellationToken).ConfigureAwait(false))
            {
                return ResolutionResult<string>.SuccessResult(candidate);
            }

            candidate = CreateCollisionCandidateName(baseName, suffix);
        }

        return ResolutionResult<string>.ErrorResult("Too many container name collisions (max 99)");
    }

    private async Task<bool> IsNameAvailableOrOwnedByWorkspaceAsync(
        string candidate,
        string workspace,
        string context,
        CancellationToken cancellationToken)
    {
        var inspect = await QueryContainerInspectAsync(candidate, context, cancellationToken).ConfigureAwait(false);
        if (inspect.ExitCode != 0)
        {
            return true;
        }

        var labels = await ReadContainerLabelsAsync(candidate, context, cancellationToken).ConfigureAwait(false);
        return string.Equals(labels.Workspace, workspace, StringComparison.Ordinal);
    }

    private static string CreateCollisionCandidateName(string baseName, int suffix)
    {
        var suffixText = $"-{suffix + 1}";
        var maxBaseLength = Math.Max(1, MaxDockerContainerNameLength - suffixText.Length);
        var trimmedBase = SessionRuntimeInfrastructure.TrimTrailingDash(baseName[..Math.Min(baseName.Length, maxBaseLength)]);
        return trimmedBase + suffixText;
    }

    private readonly record struct ContainerLabelFields(
        string ManagedLabel,
        string WorkspaceLabel,
        string DataVolumeLabel,
        string SshPortLabel,
        string Image,
        string State);

    private readonly record struct LabelQueryCandidateSelection(
        bool ContinueSearch,
        string? ContainerId,
        ContainerLookupResult Result);
}
