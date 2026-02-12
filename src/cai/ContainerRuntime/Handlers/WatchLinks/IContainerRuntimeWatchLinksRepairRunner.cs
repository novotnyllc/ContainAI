using ContainAI.Cli.Host.ContainerRuntime.Configuration;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeWatchLinksRepairRunner
{
    Task RunAsync(
        WatchLinksCommandParsing options,
        string importedTimestamp,
        string checkedTimestamp,
        CancellationToken cancellationToken);
}
