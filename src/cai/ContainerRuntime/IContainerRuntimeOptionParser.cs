using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ContainerRuntime.Configuration;

namespace ContainAI.Cli.Host;

internal interface IContainerRuntimeOptionParser
{
    InitCommandParsing ParseInitCommandOptions(SystemInitCommandOptions options);

    LinkRepairCommandParsing ParseLinkRepairCommandOptions(SystemLinkRepairCommandOptions options);

    WatchLinksCommandParsing ParseWatchLinksCommandOptions(SystemWatchLinksCommandOptions options);
}
