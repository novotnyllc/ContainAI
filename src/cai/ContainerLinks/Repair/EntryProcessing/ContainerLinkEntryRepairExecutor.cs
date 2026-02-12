namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkEntryRepairExecutor(
    TextWriter standardError,
    IContainerLinkRepairOperations repairOperations,
    IContainerLinkRepairReporter reporter) : IContainerLinkEntryRepairExecutor
{
    public async Task ExecuteAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        ContainerLinkEntryState state,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(containerName);
        ArgumentNullException.ThrowIfNull(stats);

        if (mode == ContainerLinkRepairMode.Check)
        {
            return;
        }

        if (mode == ContainerLinkRepairMode.DryRun)
        {
            await reporter.LogInfoAsync(quiet, $"[WOULD] Create symlink: {entry.Link} -> {entry.Target}").ConfigureAwait(false);
            stats.Fixed++;
            return;
        }

        var repair = await repairOperations.RepairEntryAsync(containerName, entry, state, cancellationToken).ConfigureAwait(false);
        if (!repair.Success)
        {
            stats.Errors++;
            await standardError.WriteLineAsync($"ERROR: {repair.Error}").ConfigureAwait(false);
            return;
        }

        stats.Fixed++;
        await reporter.LogInfoAsync(quiet, $"[FIXED] {entry.Link} -> {entry.Target}").ConfigureAwait(false);
    }
}
