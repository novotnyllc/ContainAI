namespace ContainAI.Cli.Host;

internal interface IInstallFlowExecutor
{
    Task<int> ExecuteAsync(InstallCommandContext context, CancellationToken cancellationToken);
}
