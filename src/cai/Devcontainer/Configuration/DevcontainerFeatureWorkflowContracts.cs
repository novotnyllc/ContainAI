using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal interface IDevcontainerFeatureInstallWorkflow
{
    Task<int> RunInstallAsync(SystemDevcontainerInstallCommandOptions options, CancellationToken cancellationToken);
}

internal interface IDevcontainerFeatureInitWorkflow
{
    Task<int> RunInitAsync(CancellationToken cancellationToken);
}

internal interface IDevcontainerFeatureStartWorkflow
{
    Task<int> RunStartAsync(CancellationToken cancellationToken);

    Task<int> RunVerifySysboxAsync(CancellationToken cancellationToken);
}

internal interface IDevcontainerFeatureSettingsFactory
{
    bool TryCreateFeatureConfig(out FeatureConfig settings, out string error);
}

internal interface IDevcontainerFeatureConfigLoader
{
    Task<FeatureConfig?> LoadFeatureConfigOrWriteErrorAsync(CancellationToken cancellationToken);
}
