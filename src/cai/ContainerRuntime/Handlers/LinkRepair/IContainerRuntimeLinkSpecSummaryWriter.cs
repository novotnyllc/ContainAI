using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkSpecSummaryWriter
{
    Task WriteSummaryAsync(LinkRepairMode mode, LinkRepairStats stats, bool quiet);
}
