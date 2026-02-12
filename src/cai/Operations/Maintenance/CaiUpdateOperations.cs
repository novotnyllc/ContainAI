namespace ContainAI.Cli.Host;

internal sealed class CaiUpdateOperations : ICaiUpdateOperations
{
    private readonly ICaiUpdateUsageWriter usageWriter;
    private readonly ICaiUpdateDryRunReporter dryRunReporter;
    private readonly ICaiUpdateExecutionOrchestrator executionOrchestrator;

    public CaiUpdateOperations(
        TextWriter standardOutput,
        TextWriter standardError,
        ICaiRefreshOperations caiRefreshOperations,
        ICaiManagedContainerStopper caiManagedContainerStopper,
        ICaiLimaVmRecreator caiLimaVmRecreator,
        Func<bool, bool, bool, CancellationToken, Task<int>> runDoctorAsync)
        : this(
            new CaiUpdateUsageWriter(standardOutput),
            new CaiUpdateDryRunReporter(standardOutput),
            new CaiUpdateExecutionOrchestrator(
                standardOutput,
                standardError,
                caiRefreshOperations,
                caiManagedContainerStopper,
                caiLimaVmRecreator,
                runDoctorAsync))
    {
    }

    internal CaiUpdateOperations(
        ICaiUpdateUsageWriter caiUpdateUsageWriter,
        ICaiUpdateDryRunReporter caiUpdateDryRunReporter,
        ICaiUpdateExecutionOrchestrator caiUpdateExecutionOrchestrator)
    {
        usageWriter = caiUpdateUsageWriter ?? throw new ArgumentNullException(nameof(caiUpdateUsageWriter));
        dryRunReporter = caiUpdateDryRunReporter ?? throw new ArgumentNullException(nameof(caiUpdateDryRunReporter));
        executionOrchestrator = caiUpdateExecutionOrchestrator ?? throw new ArgumentNullException(nameof(caiUpdateExecutionOrchestrator));
    }

    public async Task<int> RunUpdateAsync(
        bool dryRun,
        bool stopContainers,
        bool limaRecreate,
        bool showHelp,
        CancellationToken cancellationToken)
    {
        if (showHelp)
        {
            return await usageWriter.WriteUpdateUsageAsync().ConfigureAwait(false);
        }

        if (dryRun)
        {
            return await dryRunReporter.RunUpdateDryRunAsync(stopContainers, limaRecreate).ConfigureAwait(false);
        }

        return await executionOrchestrator.ExecuteUpdateAsync(stopContainers, limaRecreate, cancellationToken).ConfigureAwait(false);
    }
}
