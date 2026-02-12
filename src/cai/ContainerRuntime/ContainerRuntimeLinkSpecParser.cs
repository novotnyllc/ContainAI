using System.Text.Json;

namespace ContainAI.Cli.Host.ContainerRuntime.Handlers;

internal sealed class ContainerRuntimeLinkSpecParser : IContainerRuntimeLinkSpecParser
{
    public IReadOnlyList<ContainerRuntimeLinkSpecRawEntry> ParseEntries(string specPath, string specJson)
    {
        using var document = JsonDocument.Parse(specJson);
        if (!document.RootElement.TryGetProperty("links", out var linksElement) || linksElement.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidOperationException($"Invalid link spec format: {specPath}");
        }

        var entries = new List<ContainerRuntimeLinkSpecRawEntry>(linksElement.GetArrayLength());
        foreach (var linkElement in linksElement.EnumerateArray())
        {
            var linkPath = linkElement.TryGetProperty("link", out var linkValue) ? linkValue.GetString() : null;
            var targetPath = linkElement.TryGetProperty("target", out var targetValue) ? targetValue.GetString() : null;
            var removeFirst = linkElement.TryGetProperty("remove_first", out var removeFirstValue)
                && removeFirstValue.ValueKind == JsonValueKind.True;
            entries.Add(new ContainerRuntimeLinkSpecRawEntry(linkPath, targetPath, removeFirst));
        }

        return entries;
    }
}
