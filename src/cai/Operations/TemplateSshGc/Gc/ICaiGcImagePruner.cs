using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiGcImagePruner
{
    Task<int> PruneAsync(bool dryRun, CancellationToken cancellationToken);
}
