namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeEnvironmentFileLoader
{
    Task LoadEnvFileAsync(string envFilePath, bool quiet);
}
