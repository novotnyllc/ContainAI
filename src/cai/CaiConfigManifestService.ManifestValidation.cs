using System.Text.Json;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService
{
    private async Task<int> RunManifestCheckCoreAsync(string? manifestDirectory, CancellationToken cancellationToken)
    {
        manifestDirectory = ResolveManifestDirectory(manifestDirectory);
        if (!Directory.Exists(manifestDirectory))
        {
            await stderr.WriteLineAsync($"ERROR: manifest directory not found: {manifestDirectory}").ConfigureAwait(false);
            return 1;
        }

        var manifestFiles = GetManifestFiles(manifestDirectory);
        if (manifestFiles.Length == 0)
        {
            await stderr.WriteLineAsync($"ERROR: no .toml files found in directory: {manifestDirectory}").ConfigureAwait(false);
            return 1;
        }

        foreach (var file in manifestFiles)
        {
            cancellationToken.ThrowIfCancellationRequested();
            manifestTomlParser.Parse(file, includeDisabled: true, includeSourceFile: false);
        }

        var linkSpec = GenerateManifest("container-link-spec", manifestDirectory);
        var initApplied = ApplyInitDirsProbe(manifestDirectory, manifestTomlParser);
        if (initApplied <= 0)
        {
            await stderr.WriteLineAsync("ERROR: init-dir apply produced no operations").ConfigureAwait(false);
            return 1;
        }

        var linkSpecValidationError = GetLinkSpecValidationError(linkSpec.Content);
        if (linkSpecValidationError is not null)
        {
            await stderr.WriteLineAsync(linkSpecValidationError).ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Manifest consistency check passed.").ConfigureAwait(false);
        return 0;
    }

    private static string[] GetManifestFiles(string manifestDirectory) =>
        Directory
            .EnumerateFiles(manifestDirectory, "*.toml", SearchOption.TopDirectoryOnly)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();

    private static int ApplyInitDirsProbe(string manifestDirectory, IManifestTomlParser manifestTomlParser)
    {
        var initProbeDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-check-{Guid.NewGuid():N}");
        try
        {
            return ManifestApplier.ApplyInitDirs(manifestDirectory, initProbeDir, manifestTomlParser);
        }
        finally
        {
            if (Directory.Exists(initProbeDir))
            {
                Directory.Delete(initProbeDir, recursive: true);
            }
        }
    }

    private static string? GetLinkSpecValidationError(string generatedContent)
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
