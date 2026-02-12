using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorFixContainerRunner
{
    Task<int> RunAsync(bool fixAll, string? target, string? targetArg, CancellationToken cancellationToken);
}
