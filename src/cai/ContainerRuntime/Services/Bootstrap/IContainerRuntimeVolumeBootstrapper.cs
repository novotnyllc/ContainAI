namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeVolumeBootstrapper
{
    Task EnsureVolumeStructureAsync(string dataDir, string manifestsDir, bool quiet);
}
