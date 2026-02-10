namespace ContainAI.Cli.Host;

internal interface IDockerProxyPortAllocationStateReader
{
    Task<int?> TryReadPortFromFileAsync(string portFile, CancellationToken cancellationToken);

    Task<bool> IsWorkspacePortMatchAsync(string contextName, string workspaceName, string port, CancellationToken cancellationToken);

    Task<HashSet<int>> ReadReservedPortsAsync(string portDir, string contextName, CancellationToken cancellationToken);
}

internal sealed partial class DockerProxyPortAllocationStateReader : IDockerProxyPortAllocationStateReader
{
    private readonly IDockerProxyCommandExecutor commandExecutor;

    public DockerProxyPortAllocationStateReader(IDockerProxyCommandExecutor commandExecutor) => this.commandExecutor = commandExecutor;
}
