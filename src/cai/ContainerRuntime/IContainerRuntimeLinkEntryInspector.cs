using ContainAI.Cli.Host.ContainerRuntime.Inspection;
using ContainAI.Cli.Host.ContainerRuntime.Models;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal interface IContainerRuntimeLinkEntryInspector
{
    Task<ContainerRuntimeLinkInspectionResult> InspectAsync(
        string linkPath,
        string targetPath,
        bool removeFirst,
        bool quiet,
        LinkRepairStats stats);
}
