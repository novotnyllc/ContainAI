namespace ContainAI.Cli.Host.Devcontainer.Install;

internal interface IDevcontainerFeatureOptionalInstaller
{
    Task InstallAsync(FeatureConfig settings, CancellationToken cancellationToken);
}
