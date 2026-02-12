namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeManifestBootstrapService
{
    Task EnsureVolumeStructureAsync(string dataDir, string manifestsDir, bool quiet);

    Task ProcessUserManifestsAsync(string dataDir, string homeDir, bool quiet);

    Task RunHooksAsync(string hooksDirectory, string workspaceDirectory, string homeDirectory, bool quiet, CancellationToken cancellationToken);
}
