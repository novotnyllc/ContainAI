using ContainAI.Cli.Host.RuntimeSupport.Docker;
using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorRuntimeProbe
{
    Task<CaiDoctorRuntimeProbeResult> ProbeAsync(CancellationToken cancellationToken);
}
