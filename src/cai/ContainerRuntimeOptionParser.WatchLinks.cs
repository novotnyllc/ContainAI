using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ContainerRuntime.Configuration;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerRuntimeOptionParser
{
    public WatchLinksCommandParsing ParseWatchLinksCommandOptions(SystemWatchLinksCommandOptions options)
    {
        var pollIntervalSeconds = 60;
        if (!string.IsNullOrWhiteSpace(options.PollInterval) &&
            (!int.TryParse(options.PollInterval, out pollIntervalSeconds) || pollIntervalSeconds < 1))
        {
            return WatchLinksCommandParsing.Invalid("--poll-interval requires a positive integer value");
        }

        return WatchLinksCommandParsing.Valid(
            pollIntervalSeconds: pollIntervalSeconds,
            importedAtPath: string.IsNullOrWhiteSpace(options.ImportedAtFile) ? ContainerRuntimeDefaults.DefaultImportedAtFile : options.ImportedAtFile,
            checkedAtPath: string.IsNullOrWhiteSpace(options.CheckedAtFile) ? ContainerRuntimeDefaults.DefaultCheckedAtFile : options.CheckedAtFile,
            quiet: options.Quiet);
    }
}
