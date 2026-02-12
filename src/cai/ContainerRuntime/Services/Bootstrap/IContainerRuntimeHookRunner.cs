namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeHookRunner
{
    Task RunHooksAsync(
        string hooksDirectory,
        string workspaceDirectory,
        string homeDirectory,
        bool quiet,
        CancellationToken cancellationToken);
}
