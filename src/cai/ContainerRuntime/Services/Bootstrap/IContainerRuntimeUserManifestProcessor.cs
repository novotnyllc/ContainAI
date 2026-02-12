namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeUserManifestProcessor
{
    Task ProcessUserManifestsAsync(string dataDir, string homeDir, bool quiet);
}
