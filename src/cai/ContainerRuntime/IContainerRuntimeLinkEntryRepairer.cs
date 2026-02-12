using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkEntryRepairer
{
    Task RepairAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats);
}
