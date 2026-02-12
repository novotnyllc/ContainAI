namespace ContainAI.Cli.Host.ContainerRuntime.Services;

internal interface IContainerRuntimeWorkspaceLinkService
{
    Task SetupWorkspaceSymlinkAsync(string workspaceDir, bool quiet);
}
