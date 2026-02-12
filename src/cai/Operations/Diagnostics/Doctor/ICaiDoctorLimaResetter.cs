using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal interface ICaiDoctorLimaResetter
{
    Task<int?> TryResetLimaAsync(bool resetLima, CancellationToken cancellationToken);
}
