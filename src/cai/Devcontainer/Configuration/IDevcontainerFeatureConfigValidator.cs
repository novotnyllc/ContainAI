namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal interface IDevcontainerFeatureConfigValidator
{
    bool Validate(FeatureConfig config, out string error);
}
