namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeGitConfigService
{
    Task MigrateGitConfigAsync(string dataDir, bool quiet);

    Task SetupGitConfigAsync(string dataDir, string homeDir, bool quiet);
}
