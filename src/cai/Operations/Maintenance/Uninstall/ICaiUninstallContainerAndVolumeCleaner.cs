using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiUninstallContainerAndVolumeCleaner
{
    Task<CaiUninstallContainerCleanupResult> RemoveManagedContainersAndCollectVolumesAsync(
        bool dryRun,
        bool removeVolumes,
        CancellationToken cancellationToken);

    Task RemoveVolumesAsync(IReadOnlyCollection<string> volumeNames, bool dryRun, CancellationToken cancellationToken);
}
