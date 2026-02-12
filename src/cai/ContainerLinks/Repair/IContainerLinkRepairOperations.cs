using System.Globalization;

namespace ContainAI.Cli.Host;

internal interface IContainerLinkRepairOperations
{
    Task<ContainerLinkOperationResult> RepairEntryAsync(
        string containerName,
        ContainerLinkSpecEntry entry,
        ContainerLinkEntryState state,
        CancellationToken cancellationToken);

    Task<ContainerLinkOperationResult> WriteCheckedTimestampAsync(
        string containerName,
        string checkedAtFilePath,
        CancellationToken cancellationToken);
}
