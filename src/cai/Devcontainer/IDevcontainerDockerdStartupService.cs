namespace ContainAI.Cli.Host.Devcontainer;

internal interface IDevcontainerDockerdStartupService
{
    Task<int> StartDockerdAsync(CancellationToken cancellationToken);
}
