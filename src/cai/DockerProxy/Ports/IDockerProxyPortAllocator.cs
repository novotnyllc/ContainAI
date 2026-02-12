namespace ContainAI.Cli.Host.DockerProxy.Ports;

internal interface IDockerProxyPortAllocator
{
    Task<string> AllocateSshPortAsync(
        string lockPath,
        string containAiConfigDir,
        string contextName,
        string workspaceName,
        string workspaceSafe,
        CancellationToken cancellationToken);
}
