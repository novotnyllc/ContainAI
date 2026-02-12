using ContainAI.Cli.Host.ContainerRuntime.Configuration;
using ContainAI.Cli.Host.ContainerRuntime.Models;
using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeWatchLinksPollCycleProcessor
{
    Task ProcessCycleAsync(WatchLinksCommandParsing options, CancellationToken cancellationToken);
}

internal sealed class ContainerRuntimeWatchLinksPollCycleProcessor(
    IContainerRuntimeExecutionContext context,
    IContainerRuntimeWatchLinksRepairRunner repairRunner) : IContainerRuntimeWatchLinksPollCycleProcessor
{
    public async Task ProcessCycleAsync(WatchLinksCommandParsing options, CancellationToken cancellationToken)
    {
        if (!File.Exists(options.ImportedAtPath))
        {
            return;
        }

        var importedTimestamp = await context.TryReadTrimmedTextAsync(options.ImportedAtPath).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(importedTimestamp))
        {
            return;
        }

        var checkedTimestamp = await context.TryReadTrimmedTextAsync(options.CheckedAtPath).ConfigureAwait(false) ?? string.Empty;
        if (!string.IsNullOrEmpty(checkedTimestamp) && string.CompareOrdinal(importedTimestamp, checkedTimestamp) <= 0)
        {
            return;
        }

        await repairRunner.RunAsync(options, importedTimestamp, checkedTimestamp, cancellationToken).ConfigureAwait(false);
    }
}
