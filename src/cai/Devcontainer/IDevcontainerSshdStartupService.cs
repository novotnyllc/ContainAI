namespace ContainAI.Cli.Host.Devcontainer;

internal interface IDevcontainerSshdStartupService
{
    Task<int> StartSshdAsync(CancellationToken cancellationToken);
}
