using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class ContainerLinkRepairService
{
    private async Task<LinkSpecReadResult> ReadLinkSpecAsync(
        string containerName,
        string specPath,
        bool required,
        CancellationToken cancellationToken)
    {
        var read = await ExecAsync(containerName, ["cat", specPath], cancellationToken).ConfigureAwait(false);
        if (read.ExitCode != 0)
        {
            if (required)
            {
                return LinkSpecReadResult.Fail($"Link spec not found: {specPath}");
            }

            return LinkSpecReadResult.Ok(Array.Empty<ContainerLinkSpecEntry>());
        }

        try
        {
            var document = JsonSerializer.Deserialize(
                read.StandardOutput,
                ContainerLinkSpecJsonContext.Default.ContainerLinkSpecDocument);
            if (document?.Links is null)
            {
                return required
                    ? LinkSpecReadResult.Fail($"Invalid link spec format: {specPath}")
                    : LinkSpecReadResult.Ok(Array.Empty<ContainerLinkSpecEntry>());
            }

            return LinkSpecReadResult.Ok(document.Links);
        }
        catch (JsonException ex)
        {
            return LinkSpecReadResult.Fail($"Invalid JSON in {specPath}: {ex.Message}");
        }
    }

    private readonly record struct LinkSpecReadResult(IReadOnlyList<ContainerLinkSpecEntry> Entries, string? Error)
    {
        public static LinkSpecReadResult Ok(IReadOnlyList<ContainerLinkSpecEntry> entries) => new(entries, null);
        public static LinkSpecReadResult Fail(string error) => new(Array.Empty<ContainerLinkSpecEntry>(), error);
    }
}
