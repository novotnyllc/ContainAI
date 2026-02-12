namespace ContainAI.Cli.Host.Devcontainer.Configuration;

internal interface IDevcontainerFeatureOptionsLoader
{
    Task<FeatureConfig?> LoadAsync(string path, CancellationToken cancellationToken);
}
