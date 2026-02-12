namespace ContainAI.Cli.Host;

internal interface IInstallShellIntegrationUpdater
{
    Task EnsureShellIntegrationAsync(
        string binDir,
        string homeDirectory,
        bool autoUpdateShellConfig,
        CancellationToken cancellationToken);
}
