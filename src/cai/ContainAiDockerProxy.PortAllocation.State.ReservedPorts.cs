namespace ContainAI.Cli.Host;

internal sealed partial class DockerProxyPortAllocationStateReader
{
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
