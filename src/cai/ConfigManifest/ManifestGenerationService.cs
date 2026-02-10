using System.Text.Json;

namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ManifestGenerationService
{
    private readonly IManifestTomlParser manifestTomlParser;

    public ManifestGenerationService(IManifestTomlParser manifestTomlParser)
        => this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));

    internal (string Content, int Count) GenerateManifest(string kind, string manifestPath)
    {
        var generated = kind switch
        {
            "container-link-spec" => ManifestGenerators.GenerateContainerLinkSpec(manifestPath, manifestTomlParser),
            _ => throw new InvalidOperationException($"unknown generator kind: {kind}"),
        };

        return (generated.Content, generated.Count);
    }

    internal static void EnsureOutputDirectory(string outputPath)
    {
        var outputDirectory = Path.GetDirectoryName(Path.GetFullPath(outputPath));
        if (!string.IsNullOrWhiteSpace(outputDirectory))
        {
            Directory.CreateDirectory(outputDirectory);
        }
    }

    internal static string? GetLinkSpecValidationError(string generatedContent)
    {
        try
        {
            using var document = JsonDocument.Parse(generatedContent);
            if (document.RootElement.ValueKind == JsonValueKind.Object &&
                document.RootElement.TryGetProperty("links", out var links) &&
                links.ValueKind == JsonValueKind.Array)
            {
                return null;
            }

            return "ERROR: generated link spec appears invalid";
        }
        catch (JsonException)
        {
            return "ERROR: generated link spec is not valid JSON";
        }
    }
}
