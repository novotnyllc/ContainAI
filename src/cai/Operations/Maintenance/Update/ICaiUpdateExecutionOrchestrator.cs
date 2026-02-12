namespace ContainAI.Cli.Host;

internal interface ICaiUpdateExecutionOrchestrator
{
    Task<int> ExecuteUpdateAsync(bool stopContainers, bool limaRecreate, CancellationToken cancellationToken);
}
