namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkCheckedTimestampUpdater : IContainerLinkCheckedTimestampUpdater
{
    private readonly IContainerLinkRepairOperations repairOperations;
    private readonly IContainerLinkRepairReporter reporter;
    private readonly TextWriter standardError;

    public ContainerLinkCheckedTimestampUpdater(
        IContainerLinkRepairOperations repairOperations,
        IContainerLinkRepairReporter reporter,
        TextWriter standardError)
    {
        this.repairOperations = repairOperations ?? throw new ArgumentNullException(nameof(repairOperations));
        this.reporter = reporter ?? throw new ArgumentNullException(nameof(reporter));
        this.standardError = standardError ?? throw new ArgumentNullException(nameof(standardError));
    }

    public async Task TryUpdateAsync(
        string containerName,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(containerName);
        ArgumentNullException.ThrowIfNull(stats);

        if (mode != ContainerLinkRepairMode.Fix || stats.Errors != 0)
        {
            return;
        }

        var timestampResult = await repairOperations
            .WriteCheckedTimestampAsync(containerName, ContainerLinkRepairFilePaths.CheckedAtFilePath, cancellationToken)
            .ConfigureAwait(false);
        if (!timestampResult.Success)
        {
            stats.Errors++;
            await standardError.WriteLineAsync($"[WARN] Failed to update links-checked-at timestamp: {timestampResult.Error}").ConfigureAwait(false);
            return;
        }

        await reporter.LogInfoAsync(quiet, "Updated links-checked-at timestamp").ConfigureAwait(false);
    }
}
