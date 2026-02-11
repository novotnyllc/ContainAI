namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkRepairService
{
    private readonly IContainerLinkSpecSetLoader specSetLoader;
    private readonly IContainerLinkEntryProcessor entryProcessor;
    private readonly IContainerLinkCheckedTimestampUpdater checkedTimestampUpdater;
    private readonly IContainerLinkRepairReporter reporter;
    private readonly IContainerLinkRepairExitCodeEvaluator exitCodeEvaluator;

    public ContainerLinkRepairService(
        TextWriter standardOutput,
        TextWriter standardError,
        DockerCommandExecutor dockerExecutor)
        : this(
            standardOutput,
            standardError,
            CreateSpecSetLoader(standardError, dockerExecutor),
            CreateEntryProcessor(standardOutput, standardError, dockerExecutor),
            CreateCheckedTimestampUpdater(standardOutput, standardError, dockerExecutor),
            new ContainerLinkRepairReporter(standardOutput),
            new ContainerLinkRepairExitCodeEvaluator())
    {
    }

    internal ContainerLinkRepairService(
        TextWriter standardOutput,
        TextWriter standardError,
        IContainerLinkSpecSetLoader containerLinkSpecSetLoader,
        IContainerLinkEntryProcessor containerLinkEntryProcessor,
        IContainerLinkCheckedTimestampUpdater containerLinkCheckedTimestampUpdater,
        IContainerLinkRepairReporter containerLinkRepairReporter,
        IContainerLinkRepairExitCodeEvaluator containerLinkRepairExitCodeEvaluator)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        specSetLoader = containerLinkSpecSetLoader ?? throw new ArgumentNullException(nameof(containerLinkSpecSetLoader));
        entryProcessor = containerLinkEntryProcessor ?? throw new ArgumentNullException(nameof(containerLinkEntryProcessor));
        checkedTimestampUpdater = containerLinkCheckedTimestampUpdater ?? throw new ArgumentNullException(nameof(containerLinkCheckedTimestampUpdater));
        reporter = containerLinkRepairReporter ?? throw new ArgumentNullException(nameof(containerLinkRepairReporter));
        exitCodeEvaluator = containerLinkRepairExitCodeEvaluator ?? throw new ArgumentNullException(nameof(containerLinkRepairExitCodeEvaluator));
    }

    public async Task<int> RunAsync(
        string containerName,
        ContainerLinkRepairMode mode,
        bool quiet,
        CancellationToken cancellationToken)
    {
        var stats = new ContainerLinkRepairStats();

        var specSet = await specSetLoader
            .LoadAsync(containerName, stats, cancellationToken)
            .ConfigureAwait(false);
        if (!specSet.Success)
        {
            return 1;
        }

        await entryProcessor.ProcessEntriesAsync(containerName, specSet.BuiltinEntries, mode, quiet, stats, cancellationToken).ConfigureAwait(false);
        await entryProcessor.ProcessEntriesAsync(containerName, specSet.UserEntries, mode, quiet, stats, cancellationToken).ConfigureAwait(false);
        await checkedTimestampUpdater.TryUpdateAsync(containerName, mode, quiet, stats, cancellationToken).ConfigureAwait(false);

        await reporter.WriteSummaryAsync(mode, stats, quiet).ConfigureAwait(false);
        return exitCodeEvaluator.Evaluate(mode, stats);
    }

    private static ContainerLinkSpecSetLoader CreateSpecSetLoader(TextWriter standardError, DockerCommandExecutor dockerExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(dockerExecutor);
        var commandClient = new ContainerLinkCommandClient(dockerExecutor);
        return new ContainerLinkSpecSetLoader(new ContainerLinkSpecReader(commandClient), standardError);
    }

    private static ContainerLinkEntryProcessor CreateEntryProcessor(
        TextWriter standardOutput,
        TextWriter standardError,
        DockerCommandExecutor dockerExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(dockerExecutor);
        var commandClient = new ContainerLinkCommandClient(dockerExecutor);
        var repairOperations = new ContainerLinkRepairOperations(commandClient);
        var reporter = new ContainerLinkRepairReporter(standardOutput);
        return new ContainerLinkEntryProcessor(standardError, new ContainerLinkEntryInspector(commandClient), repairOperations, reporter);
    }

    private static ContainerLinkCheckedTimestampUpdater CreateCheckedTimestampUpdater(
        TextWriter standardOutput,
        TextWriter standardError,
        DockerCommandExecutor dockerExecutor)
    {
        ArgumentNullException.ThrowIfNull(standardOutput);
        ArgumentNullException.ThrowIfNull(standardError);
        ArgumentNullException.ThrowIfNull(dockerExecutor);
        var commandClient = new ContainerLinkCommandClient(dockerExecutor);
        var repairOperations = new ContainerLinkRepairOperations(commandClient);
        var reporter = new ContainerLinkRepairReporter(standardOutput);
        return new ContainerLinkCheckedTimestampUpdater(repairOperations, reporter, standardError);
    }
}
