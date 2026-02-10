namespace ContainAI.Cli.Host;

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

internal sealed class DockerProxyPortAllocator : IDockerProxyPortAllocator
{
    private readonly ContainAiDockerProxyOptions options;
    private readonly IContainAiSystemEnvironment environment;
    private readonly IDockerProxyCommandExecutor commandExecutor;

    public DockerProxyPortAllocator(
        ContainAiDockerProxyOptions options,
        IContainAiSystemEnvironment environment,
        IDockerProxyCommandExecutor commandExecutor)
    {
        this.options = options;
        this.environment = environment;
        this.commandExecutor = commandExecutor;
    }

    public Task<string> AllocateSshPortAsync(
        string lockPath,
        string containAiConfigDir,
        string contextName,
        string workspaceName,
        string workspaceSafe,
        CancellationToken cancellationToken)
        => WithPortLockAsync(
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
        if (File.Exists(portFile))
        {
            var content = (await File.ReadAllTextAsync(portFile, cancellationToken).ConfigureAwait(false)).Trim();
            if (int.TryParse(content, out var existingPort))
            {
                if (!environment.IsPortInUse(existingPort))
                {
                    return existingPort.ToString();
                }

                var existingContainerPort = await commandExecutor.RunCaptureAsync(
                    [
                        "--context", contextName,
                        "ps", "-a",
                        "--filter", $"label=containai.devcontainer.workspace={workspaceName}",
                        "--filter", "label=containai.ssh-port",
                        "--format", "{{.Label \"containai.ssh-port\"}}",
                    ],
                    cancellationToken).ConfigureAwait(false);

                if (existingContainerPort.ExitCode == 0 &&
                    string.Equals(existingContainerPort.StandardOutput.Trim(), content, StringComparison.Ordinal))
                {
                    return content;
                }
            }
        }

        var reservedPorts = new HashSet<int>();
        var labelPorts = await commandExecutor.RunCaptureAsync(
            ["--context", contextName, "ps", "-a", "--filter", "label=containai.ssh-port", "--format", "{{.Label \"containai.ssh-port\"}}"],
            cancellationToken).ConfigureAwait(false);

        if (labelPorts.ExitCode == 0)
        {
            foreach (var line in SplitLines(labelPorts.StandardOutput))
            {
                if (int.TryParse(line, out var parsedPort))
                {
                    reservedPorts.Add(parsedPort);
                }
            }
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
            catch (IOException)
            {
                // Ignore stale files and continue allocation.
            }
            catch (UnauthorizedAccessException)
            {
                // Ignore stale files and continue allocation.
            }
        }

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

    private static async Task<T> WithPortLockAsync<T>(string lockPath, Func<Task<T>> action, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(lockPath)!);

        for (var attempt = 0; attempt < 100; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                await using var stream = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None).ConfigureAwait(false);
                return await action().ConfigureAwait(false);
            }
            catch (IOException)
            {
                await Task.Delay(100, cancellationToken).ConfigureAwait(false);
            }
        }

        return await action().ConfigureAwait(false);
    }

    private static IEnumerable<string> SplitLines(string text) => text
        .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Where(static value => !string.IsNullOrWhiteSpace(value));
}
