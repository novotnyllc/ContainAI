namespace ContainAI.Cli.Host;

internal interface IDevcontainerFeatureConfigService
{
    bool ValidateFeatureConfig(FeatureConfig config, out string error);

    bool TryParseFeatureBoolean(string name, bool defaultValue, out bool value, out string error);

    Task<FeatureConfig?> LoadFeatureConfigAsync(string path, CancellationToken cancellationToken);
}

internal sealed class DevcontainerFeatureConfigService : IDevcontainerFeatureConfigService
{
    private readonly IDevcontainerFeatureOptionsLoader configLoader;
    private readonly IDevcontainerFeatureConfigValidator configValidator;
    private readonly IDevcontainerFeatureBooleanParser booleanParser;

    public DevcontainerFeatureConfigService()
        : this(Environment.GetEnvironmentVariable)
    {
    }

    internal DevcontainerFeatureConfigService(Func<string, string?> environmentVariableReader)
        : this(
            new DevcontainerFeatureOptionsLoader(),
            new DevcontainerFeatureConfigValidator(),
            new DevcontainerFeatureBooleanParser(environmentVariableReader))
    {
    }

    internal DevcontainerFeatureConfigService(
        IDevcontainerFeatureOptionsLoader configLoader,
        IDevcontainerFeatureConfigValidator configValidator,
        IDevcontainerFeatureBooleanParser booleanParser)
    {
        this.configLoader = configLoader ?? throw new ArgumentNullException(nameof(configLoader));
        this.configValidator = configValidator ?? throw new ArgumentNullException(nameof(configValidator));
        this.booleanParser = booleanParser ?? throw new ArgumentNullException(nameof(booleanParser));
    }

    public Task<FeatureConfig?> LoadFeatureConfigAsync(string path, CancellationToken cancellationToken)
        => configLoader.LoadAsync(path, cancellationToken);

    public bool ValidateFeatureConfig(FeatureConfig config, out string error)
        => configValidator.Validate(config, out error);

    public bool TryParseFeatureBoolean(string name, bool defaultValue, out bool value, out string error)
        => booleanParser.TryParse(name, defaultValue, out value, out error);
}
