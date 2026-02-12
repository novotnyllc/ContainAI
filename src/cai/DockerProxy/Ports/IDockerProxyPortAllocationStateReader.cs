namespace ContainAI.Cli.Host.DockerProxy.Ports;

internal interface IDockerProxyPortAllocationStateReader
{
    Task<int?> TryReadPortFromFileAsync(string portFile, CancellationToken cancellationToken);

    Task<bool> IsWorkspacePortMatchAsync(string contextName, string workspaceName, string port, CancellationToken cancellationToken);

    Task<HashSet<int>> ReadReservedPortsAsync(string portDir, string contextName, CancellationToken cancellationToken);
}
