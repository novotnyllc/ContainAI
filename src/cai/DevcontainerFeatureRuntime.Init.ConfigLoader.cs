namespace ContainAI.Cli.Host;

internal sealed class DevcontainerFeatureConfigLoader : IDevcontainerFeatureConfigLoader
{
    private readonly IDevcontainerFeatureConfigService configService;
    private readonly TextWriter stderr;

    public DevcontainerFeatureConfigLoader(IDevcontainerFeatureConfigService configService, TextWriter stderr)
    {
        this.configService = configService ?? throw new ArgumentNullException(nameof(configService));
        this.stderr = stderr ?? throw new ArgumentNullException(nameof(stderr));
    }

    public async Task<FeatureConfig?> LoadFeatureConfigOrWriteErrorAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(DevcontainerFeaturePaths.DefaultConfigPath))
        {
            await stderr.WriteLineAsync($"ERROR: Configuration file not found: {DevcontainerFeaturePaths.DefaultConfigPath}").ConfigureAwait(false);
            return null;
        }

        var settings = await configService.LoadFeatureConfigAsync(DevcontainerFeaturePaths.DefaultConfigPath, cancellationToken).ConfigureAwait(false);
        if (settings is null)
        {
            await stderr.WriteLineAsync($"ERROR: Failed to parse configuration file: {DevcontainerFeaturePaths.DefaultConfigPath}").ConfigureAwait(false);
            return null;
        }

        return settings;
    }
}
