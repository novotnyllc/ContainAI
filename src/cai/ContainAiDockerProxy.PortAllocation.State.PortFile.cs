namespace ContainAI.Cli.Host;

internal sealed partial class DockerProxyPortAllocationStateReader
{
    public async Task<int?> TryReadPortFromFileAsync(string portFile, CancellationToken cancellationToken)
    {
        if (!File.Exists(portFile))
        {
            return null;
        }

        var content = (await File.ReadAllTextAsync(portFile, cancellationToken).ConfigureAwait(false)).Trim();
        return int.TryParse(content, out var parsedPort) ? parsedPort : null;
    }
}
