using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed partial class ContainerRuntimeWatchLinksCommandHandler
{
    private async Task<bool> ValidateOptionsAsync(WatchLinksCommandParsing options)
    {
        if (options.IsValid)
        {
            return true;
        }

        await context.StandardError.WriteLineAsync(options.ErrorMessage).ConfigureAwait(false);
        return false;
    }

    private async Task LogWatcherStartupAsync(WatchLinksCommandParsing options)
    {
        await context.LogInfoAsync(options.Quiet, $"Link watcher started (poll interval: {options.PollIntervalSeconds}s)").ConfigureAwait(false);
        await context.LogInfoAsync(options.Quiet, $"Watching: {options.ImportedAtPath} vs {options.CheckedAtPath}").ConfigureAwait(false);
    }
}
