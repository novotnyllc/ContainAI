using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host;

internal interface ICaiUninstallShellIntegrationCleaner
{
    Task CleanAsync(bool dryRun, CancellationToken cancellationToken);
}
