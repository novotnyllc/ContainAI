namespace ContainAI.Cli.Host;

internal interface IContainerLinkEntryInspector
{
    Task<ContainerLinkEntryState> GetEntryStateAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        CancellationToken cancellationToken);
}
