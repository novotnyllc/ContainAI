using ContainAI.Cli.Host.DockerProxy.Contracts;

namespace ContainAI.Cli.Host.DockerProxy.Ports;

internal interface IDockerProxyPortAllocationStateReader
{
    Task<int?> TryReadPortFromFileAsync(string portFile, CancellationToken cancellationToken);

    Task<bool> IsWorkspacePortMatchAsync(string contextName, string workspaceName, string port, CancellationToken cancellationToken);

    Task<HashSet<int>> ReadReservedPortsAsync(string portDir, string contextName, CancellationToken cancellationToken);
}

internal sealed class DockerProxyPortAllocationStateReader : IDockerProxyPortAllocationStateReader
{
    private readonly IDockerProxyCommandExecutor commandExecutor;

    public DockerProxyPortAllocationStateReader(IDockerProxyCommandExecutor commandExecutor) => this.commandExecutor = commandExecutor;

    public async Task<int?> TryReadPortFromFileAsync(string portFile, CancellationToken cancellationToken)
    {
        if (!File.Exists(portFile))
        {
            return null;
        }

        var content = (await File.ReadAllTextAsync(portFile, cancellationToken).ConfigureAwait(false)).Trim();
        return int.TryParse(content, out var parsedPort) ? parsedPort : null;
    }

    public async Task<bool> IsWorkspacePortMatchAsync(string contextName, string workspaceName, string port, CancellationToken cancellationToken)
    {
        var existingContainerPort = await commandExecutor.RunCaptureAsync(
            [
                "--context", contextName,
                "ps", "-a",
                "--filter", $"label=containai.devcontainer.workspace={workspaceName}",
                "--filter", "label=containai.ssh-port",
                "--format", "{{.Label \"containai.ssh-port\"}}",
            ],
            cancellationToken).ConfigureAwait(false);

        return existingContainerPort.ExitCode == 0 &&
               string.Equals(existingContainerPort.StandardOutput.Trim(), port, StringComparison.Ordinal);
    }

    public async Task<HashSet<int>> ReadReservedPortsAsync(string portDir, string contextName, CancellationToken cancellationToken)
    {
        var reservedPorts = new HashSet<int>();

        var labelPorts = await commandExecutor.RunCaptureAsync(
            ["--context", contextName, "ps", "-a", "--filter", "label=containai.ssh-port", "--format", "{{.Label \"containai.ssh-port\"}}"],
            cancellationToken).ConfigureAwait(false);

        if (labelPorts.ExitCode == 0)
        {
            AddParsedPorts(reservedPorts, labelPorts.StandardOutput);
        }

        foreach (var file in Directory.EnumerateFiles(portDir))
        {
            try
            {
                var fileText = (await File.ReadAllTextAsync(file, cancellationToken).ConfigureAwait(false)).Trim();
                if (int.TryParse(fileText, out var parsedPort))
                {
                    reservedPorts.Add(parsedPort);
                }
            }
            catch (IOException ex)
            {
                // Ignore stale files and continue allocation.
                _ = ex;
            }
            catch (UnauthorizedAccessException ex)
            {
                // Ignore stale files and continue allocation.
                _ = ex;
            }
        }

        return reservedPorts;
    }

    private static void AddParsedPorts(HashSet<int> reservedPorts, string text)
    {
        foreach (var line in SplitLines(text))
        {
            if (int.TryParse(line, out var parsedPort))
            {
                reservedPorts.Add(parsedPort);
            }
        }
    }

    private static IEnumerable<string> SplitLines(string text) => text
        .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Where(static value => !string.IsNullOrWhiteSpace(value));
}
