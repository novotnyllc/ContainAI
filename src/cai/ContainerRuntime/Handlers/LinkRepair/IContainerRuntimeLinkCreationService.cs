using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkCreationService
{
    Task CreateAsync(
        string linkPath,
        string targetPath,
        LinkRepairMode mode,
        bool quiet,
        LinkRepairStats stats);
}
