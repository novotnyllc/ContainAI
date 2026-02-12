namespace ContainAI.Cli.Host;

internal interface IContainerLinkSpecSetLoader
{
    Task<ContainerLinkSpecSetLoadResult> LoadAsync(
        string containerName,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken);
}
