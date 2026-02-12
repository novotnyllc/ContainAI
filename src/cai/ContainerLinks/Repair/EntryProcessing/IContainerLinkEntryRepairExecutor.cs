namespace ContainAI.Cli.Host;

internal interface IContainerLinkEntryRepairExecutor
{
    Task ExecuteAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        ContainerLinkEntryState state,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken);
}
