namespace ContainAI.Cli.Host.Devcontainer;

internal interface IDevcontainerFeatureConfigService
{
    bool ValidateFeatureConfig(FeatureConfig config, out string error);

    bool TryParseFeatureBoolean(string name, bool defaultValue, out bool value, out string error);

    Task<FeatureConfig?> LoadFeatureConfigAsync(string path, CancellationToken cancellationToken);
}
