using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeCommandService
{
    private async Task<int> RunLinkWatcherCoreAsync(SystemWatchLinksCommandOptions options, CancellationToken cancellationToken)
    {
        var parsed = optionParser.ParseWatchLinksCommandOptions(options);
        if (!parsed.IsValid)
        {
            await stderr.WriteLineAsync(parsed.ErrorMessage).ConfigureAwait(false);
            return 1;
        }

        var pollIntervalSeconds = parsed.PollIntervalSeconds;
        var importedAtPath = parsed.ImportedAtPath;
        var checkedAtPath = parsed.CheckedAtPath;
        var quiet = parsed.Quiet;

        await LogInfoAsync(quiet, $"Link watcher started (poll interval: {pollIntervalSeconds}s)").ConfigureAwait(false);
        await LogInfoAsync(quiet, $"Watching: {importedAtPath} vs {checkedAtPath}").ConfigureAwait(false);

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(pollIntervalSeconds), cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }

            if (!File.Exists(importedAtPath))
            {
                continue;
            }

            var importedTimestamp = await TryReadTrimmedTextAsync(importedAtPath).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(importedTimestamp))
            {
                continue;
            }

            var checkedTimestamp = await TryReadTrimmedTextAsync(checkedAtPath).ConfigureAwait(false) ?? string.Empty;
            if (!string.IsNullOrEmpty(checkedTimestamp) && string.CompareOrdinal(importedTimestamp, checkedTimestamp) <= 0)
            {
                continue;
            }

            await LogInfoAsync(quiet, $"Import newer than last check (imported={importedTimestamp}, checked={(string.IsNullOrWhiteSpace(checkedTimestamp) ? "never" : checkedTimestamp)}), running repair...").ConfigureAwait(false);
            var exitCode = await RunLinkRepairCoreAsync(
                new SystemLinkRepairCommandOptions(
                    Check: false,
                    Fix: true,
                    DryRun: false,
                    Quiet: true,
                    BuiltinSpec: null,
                    UserSpec: null,
                    CheckedAtFile: checkedAtPath),
                cancellationToken).ConfigureAwait(false);
            if (exitCode == 0)
            {
                await LogInfoAsync(quiet, "Repair completed successfully").ConfigureAwait(false);
            }
            else
            {
                await stderr.WriteLineAsync("[ERROR] Repair command failed").ConfigureAwait(false);
            }
        }

        return 0;
    }
}
