using ContainAI.Cli.Host.Sessions.Models;

namespace ContainAI.Cli.Host;

internal interface ICaiStopTargetResolver
{
    Task<ResolutionResult<IReadOnlyList<CaiStopTarget>>> ResolveAsync(
        string? containerName,
        bool stopAll,
        CancellationToken cancellationToken);
}
