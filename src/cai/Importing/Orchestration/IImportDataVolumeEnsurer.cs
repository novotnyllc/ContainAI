using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface IImportDataVolumeEnsurer
{
    Task<int> EnsureVolumeAsync(string volume, bool dryRun, CancellationToken cancellationToken);
}
