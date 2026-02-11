using ContainAI.Cli.Abstractions;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host;

internal interface IContainerRuntimeOptionParser
{
    InitCommandParsing ParseInitCommandOptions(SystemInitCommandOptions options);

    LinkRepairCommandParsing ParseLinkRepairCommandOptions(SystemLinkRepairCommandOptions options);

    WatchLinksCommandParsing ParseWatchLinksCommandOptions(SystemWatchLinksCommandOptions options);
}

internal sealed partial class ContainerRuntimeOptionParser : IContainerRuntimeOptionParser;
