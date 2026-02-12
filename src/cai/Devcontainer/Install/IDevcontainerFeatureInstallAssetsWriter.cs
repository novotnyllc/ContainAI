namespace ContainAI.Cli.Host.Devcontainer.Install;

internal interface IDevcontainerFeatureInstallAssetsWriter
{
    Task WriteAsync(FeatureConfig settings, string? featureDirectory, CancellationToken cancellationToken);
}
