namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService
{
    private async Task<int> RunManifestGenerateCoreAsync(
        string kind,
        string manifestPath,
        string? outputPath,
        CancellationToken cancellationToken)
    {
        try
        {
            var generated = GenerateManifest(kind, manifestPath);
            if (!string.IsNullOrWhiteSpace(outputPath))
            {
                EnsureOutputDirectory(outputPath);
                await File.WriteAllTextAsync(outputPath, generated.Content, cancellationToken).ConfigureAwait(false);
                await stderr.WriteLineAsync($"Generated: {outputPath} ({generated.Count} links)").ConfigureAwait(false);
                return 0;
            }

            await stdout.WriteAsync(generated.Content).ConfigureAwait(false);
            return 0;
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private async Task<int> RunManifestApplyCoreAsync(
        string kind,
        string manifestPath,
        string dataDir,
        string homeDir,
        string shimDir,
        string caiBinaryPath,
        CancellationToken cancellationToken)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var applied = ApplyManifest(kind, manifestPath, dataDir, homeDir, shimDir, caiBinaryPath);
            await stderr.WriteLineAsync($"Applied {kind}: {applied}").ConfigureAwait(false);
            return 0;
        }
        catch (InvalidOperationException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (IOException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
        catch (UnauthorizedAccessException ex)
        {
            await stderr.WriteLineAsync($"ERROR: {ex.Message}").ConfigureAwait(false);
            return 1;
        }
    }

    private (string Content, int Count) GenerateManifest(string kind, string manifestPath)
    {
        var generated = kind switch
        {
            "container-link-spec" => ManifestGenerators.GenerateContainerLinkSpec(manifestPath, manifestTomlParser),
            _ => throw new InvalidOperationException($"unknown generator kind: {kind}"),
        };
        return (generated.Content, generated.Count);
    }

    private int ApplyManifest(
        string kind,
        string manifestPath,
        string dataDir,
        string homeDir,
        string shimDir,
        string caiBinaryPath) =>
        kind switch
        {
            "container-links" => ManifestApplier.ApplyContainerLinks(manifestPath, homeDir, dataDir, manifestTomlParser),
            "init-dirs" => ManifestApplier.ApplyInitDirs(manifestPath, dataDir, manifestTomlParser),
            "agent-shims" => ManifestApplier.ApplyAgentShims(manifestPath, shimDir, caiBinaryPath, manifestTomlParser),
            _ => throw new InvalidOperationException($"unknown apply kind: {kind}"),
        };

    private static void EnsureOutputDirectory(string outputPath)
    {
        var outputDirectory = Path.GetDirectoryName(Path.GetFullPath(outputPath));
        if (!string.IsNullOrWhiteSpace(outputDirectory))
        {
            Directory.CreateDirectory(outputDirectory);
        }
    }
}
