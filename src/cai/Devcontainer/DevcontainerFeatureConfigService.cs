namespace ContainAI.Cli.Host;

internal interface IDevcontainerFeatureConfigService
{
    bool ValidateFeatureConfig(FeatureConfig config, out string error);

    bool TryParseFeatureBoolean(string name, bool defaultValue, out bool value, out string error);

    Task<FeatureConfig?> LoadFeatureConfigAsync(string path, CancellationToken cancellationToken);
}

internal sealed partial class DevcontainerFeatureConfigService : IDevcontainerFeatureConfigService
{
    private readonly Func<string, string?> environmentVariableReader;

    public DevcontainerFeatureConfigService()
        : this(Environment.GetEnvironmentVariable)
    {
    }

    internal DevcontainerFeatureConfigService(Func<string, string?> environmentVariableReader)
        => this.environmentVariableReader = environmentVariableReader ?? throw new ArgumentNullException(nameof(environmentVariableReader));
}
