using System.Text.Json;
using ContainAI.Cli.Host.Manifests.Apply;

namespace ContainAI.Cli.Host.ConfigManifest;

internal sealed class ManifestCommandProcessor : IManifestCommandProcessor
{
    private readonly TextWriter stdout;
    private readonly TextWriter stderr;
    private readonly IManifestTomlParser manifestTomlParser;
    private readonly IManifestApplier manifestApplier;
    private readonly IManifestDirectoryResolver manifestDirectoryResolver;

    public ManifestCommandProcessor(
        TextWriter standardOutput,
        TextWriter standardError,
        IManifestTomlParser manifestTomlParser,
        IManifestApplier manifestApplier,
        IManifestDirectoryResolver manifestDirectoryResolver)
    {
        stdout = standardOutput ?? throw new ArgumentNullException(nameof(standardOutput));
        stderr = standardError ?? throw new ArgumentNullException(nameof(standardError));
        this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
        this.manifestApplier = manifestApplier ?? throw new ArgumentNullException(nameof(manifestApplier));
        this.manifestDirectoryResolver = manifestDirectoryResolver ?? throw new ArgumentNullException(nameof(manifestDirectoryResolver));
    }

    public async Task<int> RunParseAsync(ManifestParseRequest request, CancellationToken cancellationToken)
    {
        try
        {
            var parsed = manifestTomlParser.Parse(request.ManifestPath, request.IncludeDisabled, request.EmitSourceFile);
            foreach (var entry in parsed)
            {
                cancellationToken.ThrowIfCancellationRequested();
                await stdout.WriteLineAsync(entry.ToString()).ConfigureAwait(false);
            }

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

    public async Task<int> RunGenerateAsync(ManifestGenerateRequest request, CancellationToken cancellationToken)
    {
        try
        {
            var generated = GenerateManifest(request.Kind, request.ManifestPath);
            if (!string.IsNullOrWhiteSpace(request.OutputPath))
            {
                EnsureOutputDirectory(request.OutputPath);
                await File.WriteAllTextAsync(request.OutputPath, generated.Content, cancellationToken).ConfigureAwait(false);
                await stderr.WriteLineAsync($"Generated: {request.OutputPath} ({generated.Count} links)").ConfigureAwait(false);
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

    public async Task<int> RunApplyAsync(ManifestApplyRequest request, CancellationToken cancellationToken)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            var applied = ApplyManifest(
                request.Kind,
                request.ManifestPath,
                request.DataDir,
                request.HomeDir,
                request.ShimDir,
                request.CaiBinaryPath);
            await stderr.WriteLineAsync($"Applied {request.Kind}: {applied}").ConfigureAwait(false);
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

    public async Task<int> RunCheckAsync(ManifestCheckRequest request, CancellationToken cancellationToken)
    {
        var manifestDirectory = manifestDirectoryResolver.ResolveManifestDirectory(request.ManifestDirectory);
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
        var initApplied = ApplyInitDirsProbe(manifestDirectory);
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
            "container-links" => manifestApplier.ApplyContainerLinks(manifestPath, homeDir, dataDir),
            "init-dirs" => manifestApplier.ApplyInitDirs(manifestPath, dataDir),
            "agent-shims" => manifestApplier.ApplyAgentShims(manifestPath, shimDir, caiBinaryPath),
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

    private static string[] GetManifestFiles(string manifestDirectory) =>
        Directory
            .EnumerateFiles(manifestDirectory, "*.toml", SearchOption.TopDirectoryOnly)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();

    private int ApplyInitDirsProbe(string manifestDirectory)
    {
        var initProbeDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-check-{Guid.NewGuid():N}");
        try
        {
            return manifestApplier.ApplyInitDirs(manifestDirectory, initProbeDir);
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
