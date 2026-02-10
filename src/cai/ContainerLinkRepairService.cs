namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkRepairService
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
}
