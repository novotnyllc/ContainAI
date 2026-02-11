namespace ContainAI.Cli.Host;

internal interface ISessionTargetDataVolumeResolutionService
{
    Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken);
}

internal sealed partial class SessionTargetDataVolumeResolutionService : ISessionTargetDataVolumeResolutionService
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
}
