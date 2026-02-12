using ContainAI.Cli.Host.DockerProxy.Contracts;
using ContainAI.Cli.Host.DockerProxy.Models;

namespace ContainAI.Cli.Host.DockerProxy.Ports;

internal sealed class DockerProxyPortAllocator : IDockerProxyPortAllocator
{
    private readonly ContainAiDockerProxyOptions options;
    private readonly IContainAiSystemEnvironment environment;
    private readonly IDockerProxyPortAllocationStateReader stateReader;

    public DockerProxyPortAllocator(
        ContainAiDockerProxyOptions options,
        IContainAiSystemEnvironment environment,
        IDockerProxyCommandExecutor commandExecutor)
        : this(options, environment, new DockerProxyPortAllocationStateReader(commandExecutor))
    {
    }

    internal DockerProxyPortAllocator(
        ContainAiDockerProxyOptions options,
        IContainAiSystemEnvironment environment,
        IDockerProxyPortAllocationStateReader stateReader)
    {
        this.options = options;
        this.environment = environment;
        this.stateReader = stateReader;
    }

    public Task<string> AllocateSshPortAsync(
        string lockPath,
        string containAiConfigDir,
        string contextName,
        string workspaceName,
        string workspaceSafe,
        CancellationToken cancellationToken)
        => DockerProxyPortLock.WithPortLockAsync(
            lockPath,
            () => AllocateUnlockedSshPortAsync(containAiConfigDir, contextName, workspaceName, workspaceSafe, cancellationToken),
            cancellationToken);

    private async Task<string> AllocateUnlockedSshPortAsync(
        string containAiConfigDir,
        string contextName,
        string workspaceName,
        string workspaceSafe,
        CancellationToken cancellationToken)
    {
        var portDir = Path.Combine(containAiConfigDir, "ports");
        Directory.CreateDirectory(portDir);

        var portFile = Path.Combine(portDir, $"devcontainer-{workspaceSafe}");
        var existingPort = await stateReader.TryReadPortFromFileAsync(portFile, cancellationToken).ConfigureAwait(false);
        if (existingPort is int parsedExistingPort)
        {
            if (!environment.IsPortInUse(parsedExistingPort))
            {
                return parsedExistingPort.ToString();
            }

            var existingPortText = parsedExistingPort.ToString();
            var existingContainerPortMatch = await stateReader.IsWorkspacePortMatchAsync(
                contextName,
                workspaceName,
                existingPortText,
                cancellationToken).ConfigureAwait(false);

            if (existingContainerPortMatch)
            {
                return existingPortText;
            }
        }

        var reservedPorts = await stateReader.ReadReservedPortsAsync(portDir, contextName, cancellationToken).ConfigureAwait(false);

        for (var port = options.SshPortRangeStart; port <= options.SshPortRangeEnd; port++)
        {
            if (reservedPorts.Contains(port) || environment.IsPortInUse(port))
            {
                continue;
            }

            await File.WriteAllTextAsync(portFile, port.ToString(), cancellationToken).ConfigureAwait(false);
            return port.ToString();
        }

        return "2322";
    }
}
