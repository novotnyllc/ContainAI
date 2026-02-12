using ContainAI.Cli.Host.ContainerRuntime.Configuration;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeWatchLinksPollCycleProcessor
{
    Task ProcessCycleAsync(WatchLinksCommandParsing options, CancellationToken cancellationToken);
}
