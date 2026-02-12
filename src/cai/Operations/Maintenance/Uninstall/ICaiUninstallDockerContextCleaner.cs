using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host;

internal interface ICaiUninstallDockerContextCleaner
{
    Task CleanAsync(bool dryRun, CancellationToken cancellationToken);
}
