using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Parsing;

namespace ContainAI.Cli.Host;

internal interface ICaiGcCandidateCollector
{
    Task<CaiGcPruneCandidateResult> CollectAsync(TimeSpan minimumAge, CancellationToken cancellationToken);
}
