using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkSpecProcessor
{
    Task ProcessLinkSpecAsync(
        string specPath,
        LinkRepairMode mode,
        bool quiet,
        string specName,
        LinkRepairStats stats,
        CancellationToken cancellationToken);

    Task WriteSummaryAsync(LinkRepairMode mode, LinkRepairStats stats, bool quiet);
}
