using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed class ContainerLinkSpecReader(IContainerLinkCommandClient commandClient) : IContainerLinkSpecReader
{
    public async Task<ContainerLinkSpecReadResult> ReadLinkSpecAsync(
        string containerName,
        string specPath,
        bool required,
        CancellationToken cancellationToken)
    {
        var read = await commandClient.ExecuteInContainerAsync(containerName, ["cat", specPath], cancellationToken).ConfigureAwait(false);
        if (read.ExitCode != 0)
        {
            if (required)
            {
                return ContainerLinkSpecReadResult.Fail($"Link spec not found: {specPath}");
            }

            return ContainerLinkSpecReadResult.Ok(Array.Empty<ContainerLinkSpecEntry>());
        }

        try
        {
            var document = JsonSerializer.Deserialize(
                read.StandardOutput,
                ContainerLinkSpecJsonContext.Default.ContainerLinkSpecDocument);
            if (document?.Links is null)
            {
                return required
                    ? ContainerLinkSpecReadResult.Fail($"Invalid link spec format: {specPath}")
                    : ContainerLinkSpecReadResult.Ok(Array.Empty<ContainerLinkSpecEntry>());
            }

            return ContainerLinkSpecReadResult.Ok(document.Links);
        }
        catch (JsonException ex)
        {
            return ContainerLinkSpecReadResult.Fail($"Invalid JSON in {specPath}: {ex.Message}");
        }
    }
}
