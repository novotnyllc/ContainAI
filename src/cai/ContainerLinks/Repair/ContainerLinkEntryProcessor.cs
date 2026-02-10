namespace ContainAI.Cli.Host;

internal interface IContainerLinkEntryProcessor
{
    Task ProcessEntriesAsync(
        string containerName,
        IReadOnlyList<ContainerLinkSpecEntry> entries,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken);
}

internal sealed partial class ContainerLinkEntryProcessor(
    TextWriter standardError,
    IContainerLinkEntryInspector entryInspector,
    IContainerLinkRepairOperations repairOperations,
    IContainerLinkRepairReporter reporter) : IContainerLinkEntryProcessor
{
    public async Task ProcessEntriesAsync(
        string containerName,
        IReadOnlyList<ContainerLinkSpecEntry> entries,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        foreach (var entry in entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (string.IsNullOrWhiteSpace(entry.Link) || string.IsNullOrWhiteSpace(entry.Target))
            {
                stats.Errors++;
                await standardError.WriteLineAsync("[WARN] Skipping invalid link spec entry").ConfigureAwait(false);
                continue;
            }

            await ProcessEntryAsync(containerName, entry, mode, quiet, stats, cancellationToken).ConfigureAwait(false);
        }
    }
}
