namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeEnvironmentFileReadinessService
{
    Task<bool> CanLoadAsync(string envFilePath);
}
