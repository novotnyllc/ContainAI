using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiGcContainerPruner
{
    Task<int> PruneAsync(
        IReadOnlyList<string> pruneCandidates,
        bool dryRun,
        CancellationToken cancellationToken);
}
