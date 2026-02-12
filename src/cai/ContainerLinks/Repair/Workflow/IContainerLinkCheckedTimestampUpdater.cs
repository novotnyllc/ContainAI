namespace ContainAI.Cli.Host;

internal interface IContainerLinkCheckedTimestampUpdater
{
    Task TryUpdateAsync(
        string containerName,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken);
}
