namespace ContainAI.Cli.Host;

internal interface ISessionTargetDataVolumeResolutionService
{
    Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken);
}

internal sealed class SessionTargetDataVolumeResolutionService : ISessionTargetDataVolumeResolutionService
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;
    private readonly ISessionRuntimeOperations runtimeOperations;

    internal SessionTargetDataVolumeResolutionService(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        : this(sessionTargetParsingValidationService, new SessionRuntimeOperations())
    {
    }

    internal SessionTargetDataVolumeResolutionService(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionRuntimeOperations sessionRuntimeOperations)
    {
        parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));
        runtimeOperations = sessionRuntimeOperations ?? throw new ArgumentNullException(nameof(sessionRuntimeOperations));
    }

    public async Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(explicitVolume))
        {
            return parsingValidationService.ValidateVolumeName(explicitVolume, "Invalid volume name: ");
        }

        var envVolume = Environment.GetEnvironmentVariable("CONTAINAI_DATA_VOLUME");
        if (!string.IsNullOrWhiteSpace(envVolume))
        {
            return parsingValidationService.ValidateVolumeName(envVolume, "Invalid volume name in CONTAINAI_DATA_VOLUME: ");
        }

        var userConfigVolume = await TryResolveWorkspaceVolumeAsync(
            runtimeOperations.ResolveUserConfigPath(),
            workspace,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(userConfigVolume))
        {
            return ResolutionResult<string>.SuccessResult(userConfigVolume);
        }

        var discoveredConfig = runtimeOperations.FindConfigFile(workspace, explicitConfig);
        var workspaceVolume = await TryResolveWorkspaceVolumeAsync(discoveredConfig, workspace, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(workspaceVolume))
        {
            return ResolutionResult<string>.SuccessResult(workspaceVolume);
        }

        var globalVolume = await TryResolveGlobalVolumeAsync(discoveredConfig, runtimeOperations, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(globalVolume))
        {
            return ResolutionResult<string>.SuccessResult(globalVolume);
        }

        return ResolutionResult<string>.SuccessResult(SessionRuntimeConstants.DefaultVolume);
    }

    private async Task<string?> TryResolveGlobalVolumeAsync(
        string? configPath,
        ISessionRuntimeOperations runtimeOperations,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var globalResult = await runtimeOperations.RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, "agent.data_volume"),
            cancellationToken).ConfigureAwait(false);
        if (globalResult.ExitCode != 0)
        {
            return null;
        }

        var value = globalResult.StandardOutput.Trim();
        return IsValidVolume(value) ? value : null;
    }

    private async Task<string?> TryResolveWorkspaceVolumeAsync(string? configPath, string workspace, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var workspaceResult = await runtimeOperations.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);
        if (workspaceResult.ExitCode != 0 || string.IsNullOrWhiteSpace(workspaceResult.StandardOutput))
        {
            return null;
        }

        var value = parsingValidationService.TryReadWorkspaceStringProperty(workspaceResult.StandardOutput, "data_volume");
        return IsValidVolume(value) ? value : null;
    }

    private bool IsValidVolume(string? value)
        => !string.IsNullOrWhiteSpace(value) && runtimeOperations.IsValidVolumeName(value);
}
