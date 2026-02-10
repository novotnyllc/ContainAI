using ContainAI.Cli.Host.ContainerRuntime.Configuration;
using ContainAI.Cli.Host.ContainerRuntime.Infrastructure;
using ContainAI.Cli.Host.ContainerRuntime.Models;
using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeWatchLinksCommandHandler : IContainerRuntimeWatchLinksCommandHandler
{
    private readonly IContainerRuntimeExecutionContext context;
    private readonly IContainerRuntimeLinkRepairCommandHandler linkRepairCommandHandler;

    public ContainerRuntimeWatchLinksCommandHandler(
        IContainerRuntimeExecutionContext context,
        IContainerRuntimeLinkRepairCommandHandler linkRepairCommandHandler)
    {
        this.context = context ?? throw new ArgumentNullException(nameof(context));
        this.linkRepairCommandHandler = linkRepairCommandHandler ?? throw new ArgumentNullException(nameof(linkRepairCommandHandler));
    }

    public async Task<int> HandleAsync(WatchLinksCommandParsing options, CancellationToken cancellationToken)
    {
        if (!options.IsValid)
        {
            await context.StandardError.WriteLineAsync(options.ErrorMessage).ConfigureAwait(false);
            return 1;
        }

        await context.LogInfoAsync(options.Quiet, $"Link watcher started (poll interval: {options.PollIntervalSeconds}s)").ConfigureAwait(false);
        await context.LogInfoAsync(options.Quiet, $"Watching: {options.ImportedAtPath} vs {options.CheckedAtPath}").ConfigureAwait(false);

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(options.PollIntervalSeconds), cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            if (!File.Exists(options.ImportedAtPath))
            {
                continue;
            }

            var importedTimestamp = await context.TryReadTrimmedTextAsync(options.ImportedAtPath).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(importedTimestamp))
            {
                continue;
            }

            var checkedTimestamp = await context.TryReadTrimmedTextAsync(options.CheckedAtPath).ConfigureAwait(false) ?? string.Empty;
            if (!string.IsNullOrEmpty(checkedTimestamp) && string.CompareOrdinal(importedTimestamp, checkedTimestamp) <= 0)
            {
                continue;
            }

            await context.LogInfoAsync(
                options.Quiet,
                $"Import newer than last check (imported={importedTimestamp}, checked={(string.IsNullOrWhiteSpace(checkedTimestamp) ? "never" : checkedTimestamp)}), running repair...").ConfigureAwait(false);
            var exitCode = await linkRepairCommandHandler.HandleAsync(
                new LinkRepairCommandParsing(
                    Mode: LinkRepairMode.Fix,
                    Quiet: true,
                    BuiltinSpecPath: ContainerRuntimeDefaults.DefaultBuiltinLinkSpec,
                    UserSpecPath: ContainerRuntimeDefaults.DefaultUserLinkSpec,
                    CheckedAtFilePath: options.CheckedAtPath),
                cancellationToken).ConfigureAwait(false);
            if (exitCode == 0)
            {
                await context.LogInfoAsync(options.Quiet, "Repair completed successfully").ConfigureAwait(false);
            }
            else
            {
                await context.StandardError.WriteLineAsync("[ERROR] Repair command failed").ConfigureAwait(false);
            }
        }

        return 0;
    }
}
