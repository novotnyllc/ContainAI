namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkEntryProcessor(
    TextWriter standardError,
    IContainerLinkEntryInspector entryInspector,
    IContainerLinkEntryStateReporter stateReporter,
    IContainerLinkEntryRepairExecutor repairExecutor) : IContainerLinkEntryProcessor
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

    private async Task ProcessEntryAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        var state = await entryInspector.GetEntryStateAsync(containerName, entry, cancellationToken).ConfigureAwait(false);
        var requiresRepair = await stateReporter
            .ReportAndDetermineRepairAsync(entry, state, quiet, stats)
            .ConfigureAwait(false);
        if (!requiresRepair)
        {
            return;
        }

        await repairExecutor
            .ExecuteAsync(containerName, entry, state, mode, quiet, stats, cancellationToken)
            .ConfigureAwait(false);
    }
}
