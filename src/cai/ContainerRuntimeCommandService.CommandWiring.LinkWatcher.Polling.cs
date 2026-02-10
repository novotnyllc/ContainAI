using ContainAI.Cli.Host.ContainerRuntime.Configuration;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed partial class ContainerRuntimeWatchLinksCommandHandler
{
    private async Task<int> RunWatchLoopAsync(WatchLinksCommandParsing options, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            if (!await WaitForPollIntervalAsync(options.PollIntervalSeconds, cancellationToken).ConfigureAwait(false))
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

            await RunRepairAsync(options, importedTimestamp, checkedTimestamp, cancellationToken).ConfigureAwait(false);
        }

        return 0;
    }

    private static async Task<bool> WaitForPollIntervalAsync(int pollIntervalSeconds, CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(pollIntervalSeconds), cancellationToken).ConfigureAwait(false);
            return true;
        }
        catch (OperationCanceledException)
        {
            return false;
        }
    }

    private async Task RunRepairAsync(
        WatchLinksCommandParsing options,
        string importedTimestamp,
        string checkedTimestamp,
        CancellationToken cancellationToken)
    {
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
}
