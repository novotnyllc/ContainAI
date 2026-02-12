namespace ContainAI.Cli.Host;

internal interface ISessionTargetDataVolumeResolutionService
{
    Task<ResolutionResult<string>> ResolveDataVolumeAsync(string workspace, string? explicitVolume, string? explicitConfig, CancellationToken cancellationToken);
}

internal sealed class SessionTargetDataVolumeResolutionService : ISessionTargetDataVolumeResolutionService
{
    private readonly ISessionTargetParsingValidationService parsingValidationService;
    private readonly ISessionTargetConfiguredDataVolumeResolver configuredDataVolumeResolver;

    internal SessionTargetDataVolumeResolutionService(ISessionTargetParsingValidationService sessionTargetParsingValidationService)
        : this(
            sessionTargetParsingValidationService,
            new SessionTargetConfiguredDataVolumeResolver(
                sessionTargetParsingValidationService,
                new SessionRuntimeOperations()))
    {
    }

    internal SessionTargetDataVolumeResolutionService(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionRuntimeOperations sessionRuntimeOperations)
        : this(
            sessionTargetParsingValidationService,
            new SessionTargetConfiguredDataVolumeResolver(
                sessionTargetParsingValidationService,
                sessionRuntimeOperations))
    {
    }

    internal SessionTargetDataVolumeResolutionService(
        ISessionTargetParsingValidationService sessionTargetParsingValidationService,
        ISessionTargetConfiguredDataVolumeResolver sessionTargetConfiguredDataVolumeResolver)
    {
        parsingValidationService = sessionTargetParsingValidationService ?? throw new ArgumentNullException(nameof(sessionTargetParsingValidationService));
        configuredDataVolumeResolver = sessionTargetConfiguredDataVolumeResolver ?? throw new ArgumentNullException(nameof(sessionTargetConfiguredDataVolumeResolver));
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

        var configuredVolume = await configuredDataVolumeResolver
            .ResolveConfiguredDataVolumeAsync(workspace, explicitConfig, cancellationToken)
            .ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(configuredVolume))
        {
            return ResolutionResult<string>.SuccessResult(configuredVolume);
        }

        return ResolutionResult<string>.SuccessResult(SessionRuntimeConstants.DefaultVolume);
    }
}
