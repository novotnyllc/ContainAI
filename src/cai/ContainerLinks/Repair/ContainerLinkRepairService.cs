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
            ContainerLinkRepairComponentsFactory.CreateSpecSetLoader(standardError, dockerExecutor),
            ContainerLinkRepairComponentsFactory.CreateEntryProcessor(standardOutput, standardError, dockerExecutor),
            ContainerLinkRepairComponentsFactory.CreateCheckedTimestampUpdater(standardOutput, standardError, dockerExecutor),
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
}
