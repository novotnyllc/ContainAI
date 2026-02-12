using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiStopTargetExecutor
{
    Task<int> ExecuteAsync(
        IReadOnlyList<CaiStopTarget> targets,
        bool remove,
        bool force,
        bool exportFirst,
        CancellationToken cancellationToken);
}
