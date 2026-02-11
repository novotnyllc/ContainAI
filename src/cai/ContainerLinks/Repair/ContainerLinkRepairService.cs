namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkRepairService
{
    private const string BuiltinSpecPath = "/usr/local/lib/containai/link-spec.json";
    private const string UserSpecPath = "/mnt/agent-data/containai/user-link-spec.json";
    private const string CheckedAtFilePath = "/mnt/agent-data/.containai-links-checked-at";

    private readonly TextWriter stderr;
    private readonly ContainerLinkSpecReader specReader;
    private readonly ContainerLinkRepairOperations repairOperations;
    private readonly ContainerLinkRepairReporter reporter;
    private readonly ContainerLinkEntryProcessor entryProcessor;

    public ContainerLinkRepairService(
        TextWriter standardOutput,
        TextWriter standardError,
        DockerCommandExecutor dockerExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(dockerExecutor);

        stderr = standardError;

        var commandClient = new ContainerLinkCommandClient(dockerExecutor);
        specReader = new ContainerLinkSpecReader(commandClient);
        repairOperations = new ContainerLinkRepairOperations(commandClient);
        reporter = new ContainerLinkRepairReporter(standardOutput);
        entryProcessor = new ContainerLinkEntryProcessor(standardError, new ContainerLinkEntryInspector(commandClient), repairOperations, reporter);
    }

    public async Task<int> RunAsync(
        string containerName,
        ContainerLinkRepairMode mode,
        bool quiet,
        CancellationToken cancellationToken)
    {
        var stats = new ContainerLinkRepairStats();

        var builtin = await LoadBuiltInSpecAsync(containerName, cancellationToken).ConfigureAwait(false);
        if (!builtin.Success)
        {
            return 1;
        }

        var user = await LoadUserSpecAsync(containerName, stats, cancellationToken).ConfigureAwait(false);

        await entryProcessor.ProcessEntriesAsync(containerName, builtin.Entries!, mode, quiet, stats, cancellationToken).ConfigureAwait(false);
        await entryProcessor.ProcessEntriesAsync(containerName, user.Entries, mode, quiet, stats, cancellationToken).ConfigureAwait(false);

        await TryUpdateCheckedTimestampAsync(containerName, mode, quiet, stats, cancellationToken).ConfigureAwait(false);

        await reporter.WriteSummaryAsync(mode, stats, quiet).ConfigureAwait(false);
        return ComputeExitCode(mode, stats);
    }

    private async Task<(bool Success, IReadOnlyList<ContainerLinkSpecEntry>? Entries)> LoadBuiltInSpecAsync(
        string containerName,
        CancellationToken cancellationToken)
    {
        var builtin = await specReader
            .ReadLinkSpecAsync(containerName, BuiltinSpecPath, required: true, cancellationToken)
            .ConfigureAwait(false);
        if (builtin.Error is not null)
        {
            await stderr.WriteLineAsync($"ERROR: {builtin.Error}").ConfigureAwait(false);
            return (false, null);
        }

        return (true, builtin.Entries);
    }

    private async Task<ContainerLinkSpecReadResult> LoadUserSpecAsync(
        string containerName,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        var user = await specReader
            .ReadLinkSpecAsync(containerName, UserSpecPath, required: false, cancellationToken)
            .ConfigureAwait(false);
        if (user.Error is not null)
        {
            stats.Errors++;
            await stderr.WriteLineAsync($"[WARN] Failed to process user link spec: {user.Error}").ConfigureAwait(false);
        }

        return user;
    }

    private async Task TryUpdateCheckedTimestampAsync(
        string containerName,
        ContainerLinkRepairMode mode,
        bool quiet,
        ContainerLinkRepairStats stats,
        CancellationToken cancellationToken)
    {
        if (mode != ContainerLinkRepairMode.Fix || stats.Errors != 0)
        {
            return;
        }

        var timestampResult = await repairOperations
            .WriteCheckedTimestampAsync(containerName, CheckedAtFilePath, cancellationToken)
            .ConfigureAwait(false);
        if (!timestampResult.Success)
        {
            stats.Errors++;
            await stderr.WriteLineAsync($"[WARN] Failed to update links-checked-at timestamp: {timestampResult.Error}").ConfigureAwait(false);
            return;
        }

        await reporter.LogInfoAsync(quiet, "Updated links-checked-at timestamp").ConfigureAwait(false);
    }

    private static int ComputeExitCode(ContainerLinkRepairMode mode, ContainerLinkRepairStats stats)
    {
        if (stats.Errors > 0)
        {
            return 1;
        }

        if (mode == ContainerLinkRepairMode.Check && (stats.Broken + stats.Missing) > 0)
        {
            return 1;
        }

        return 0;
    }
}
