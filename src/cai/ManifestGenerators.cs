using System.Text;
using System.Text.Json;

namespace ContainAI.Cli.Host;

internal static class ManifestGenerators
{
    public static ManifestGeneratedArtifact GenerateContainerLinkSpec(string manifestPath)
    {
        var parsed = ManifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false);
        var links = parsed
            .Where(static entry => !string.IsNullOrEmpty(entry.ContainerLink))
            .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
            .Select(static entry => new ManifestLinkSpec(
                Link: $"/home/agent/{entry.ContainerLink}",
                Target: $"/mnt/agent-data/{entry.Target}",
                RemoveFirst: entry.Flags.Contains('R', StringComparison.Ordinal)))
            .ToArray();

        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true });
        writer.WriteStartObject();
        writer.WriteNumber("version", 1);
        writer.WriteString("data_mount", "/mnt/agent-data");
        writer.WriteString("home_dir", "/home/agent");
        writer.WriteStartArray("links");
        foreach (var link in links)
        {
            writer.WriteStartObject();
            writer.WriteString("link", link.Link);
            writer.WriteString("target", link.Target);
            writer.WriteBoolean("remove_first", link.RemoveFirst);
            writer.WriteEndObject();
        }

        writer.WriteEndArray();
        writer.WriteEndObject();
        writer.Flush();

        var content = Encoding.UTF8.GetString(stream.ToArray()) + Environment.NewLine;
        return new ManifestGeneratedArtifact(content, links.Length);
    }

    private readonly record struct ManifestLinkSpec(string Link, string Target, bool RemoveFirst);
}

internal readonly record struct ManifestGeneratedArtifact(string Content, int Count);
