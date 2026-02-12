namespace ContainAI.Cli.Host.Devcontainer.Install;

internal interface IDevcontainerFeatureInstallSummaryWriter
{
    Task WriteAsync(FeatureConfig settings);
}
