using ContainAI.Cli.Host.RuntimeSupport.Process;

namespace ContainAI.Cli.Host;

internal interface ICaiLimaVmRecreator
{
    Task<int> RecreateAsync(CancellationToken cancellationToken);
}
