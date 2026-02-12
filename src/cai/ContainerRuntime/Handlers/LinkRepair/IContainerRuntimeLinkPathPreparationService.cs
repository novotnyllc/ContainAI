using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkPathPreparationService
{
    Task<bool> PrepareAsync(
        string linkPath,
        bool removeFirst,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats);
}
