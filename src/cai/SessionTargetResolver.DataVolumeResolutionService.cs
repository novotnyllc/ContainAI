namespace ContainAI.Cli.Host;

internal interface ISessionTargetDataVolumeResolutionService
{
    Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken);
}

internal sealed class SessionTargetDataVolumeResolutionService : ISessionTargetDataVolumeResolutionService
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;

    internal SessionTargetDataVolumeResolutionService(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        => parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));

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
            SessionRuntimeInfrastructure.ResolveUserConfigPath(),
            workspace,
            cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(userConfigVolume))
        {
            return ResolutionResult<string>.SuccessResult(userConfigVolume);
        }

        var discoveredConfig = SessionRuntimeInfrastructure.FindConfigFile(workspace, explicitConfig);
        var workspaceVolume = await TryResolveWorkspaceVolumeAsync(discoveredConfig, workspace, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(workspaceVolume))
        {
            return ResolutionResult<string>.SuccessResult(workspaceVolume);
        }

        var globalVolume = await TryResolveGlobalVolumeAsync(discoveredConfig, cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(globalVolume))
        {
            return ResolutionResult<string>.SuccessResult(globalVolume);
        }

        return ResolutionResult<string>.SuccessResult(SessionRuntimeConstants.DefaultVolume);
    }

    private async Task<string?> TryResolveWorkspaceVolumeAsync(string? configPath, string workspace, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var workspaceResult = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetWorkspace(configPath, workspace),
            cancellationToken).ConfigureAwait(false);
        if (workspaceResult.ExitCode != 0 || string.IsNullOrWhiteSpace(workspaceResult.StandardOutput))
        {
            return null;
        }

        var value = parsingValidationService.TryReadWorkspaceStringProperty(workspaceResult.StandardOutput, "data_volume");
        return IsValidVolume(value) ? value : null;
    }

    private static async Task<string?> TryResolveGlobalVolumeAsync(string? configPath, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configPath) || !File.Exists(configPath))
        {
            return null;
        }

        var globalResult = await SessionRuntimeInfrastructure.RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, "agent.data_volume"),
            cancellationToken).ConfigureAwait(false);
        if (globalResult.ExitCode != 0)
        {
            return null;
        }

        var value = globalResult.StandardOutput.Trim();
        return IsValidVolume(value) ? value : null;
    }

    private static bool IsValidVolume(string? value)
        => !string.IsNullOrWhiteSpace(value) && SessionRuntimeInfrastructure.IsValidVolumeName(value);
}
