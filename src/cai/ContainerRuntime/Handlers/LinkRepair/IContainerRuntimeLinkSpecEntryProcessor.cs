using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkSpecEntryProcessor
{
    Task ProcessEntryAsync(
        ContainerRuntimeLinkSpecRawEntry entry,
        string specPath,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats);
}
