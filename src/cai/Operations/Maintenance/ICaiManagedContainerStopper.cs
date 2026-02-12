using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiManagedContainerStopper
{
    Task StopAsync(CancellationToken cancellationToken);
}
