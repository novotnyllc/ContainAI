using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiConfigManifestService : CaiRuntimeSupport
{

    private async Task<int> RunParsedConfigCommandAsync(ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.Equals(parsed.Action, "resolve-volume", StringComparison.Ordinal))
        {
            return await ConfigResolveVolumeAsync(parsed, cancellationToken).ConfigureAwait(false);
        }

        var configPath = ResolveConfigPath(parsed.Workspace);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        if (!File.Exists(configPath))
        {
            await File.WriteAllTextAsync(configPath, string.Empty, cancellationToken).ConfigureAwait(false);
        }

        return parsed.Action switch
        {
            "list" => await ConfigListAsync(configPath, cancellationToken).ConfigureAwait(false),
            "get" => await ConfigGetAsync(configPath, parsed, cancellationToken).ConfigureAwait(false),
            "set" => await ConfigSetAsync(configPath, parsed, cancellationToken).ConfigureAwait(false),
            "unset" => await ConfigUnsetAsync(configPath, parsed, cancellationToken).ConfigureAwait(false),
            _ => 1,
        };
    }

    private async Task<int> RunManifestParseCoreAsync(
        string manifestPath,
        bool includeDisabled,
        bool emitSourceFile,
        CancellationToken cancellationToken)
    {
        try
        {
            var parsed = ManifestTomlParser.Parse(manifestPath, includeDisabled, emitSourceFile);
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

    private async Task<int> RunManifestGenerateCoreAsync(
        string kind,
        string manifestPath,
        string? outputPath,
        CancellationToken cancellationToken)
    {
        try
        {
            var generated = kind switch
            {
                "container-link-spec" => ManifestGenerators.GenerateContainerLinkSpec(manifestPath),
                _ => throw new InvalidOperationException($"unknown generator kind: {kind}"),
            };

            if (!string.IsNullOrWhiteSpace(outputPath))
            {
                var outputDirectory = Path.GetDirectoryName(Path.GetFullPath(outputPath));
                if (!string.IsNullOrWhiteSpace(outputDirectory))
                {
                    Directory.CreateDirectory(outputDirectory);
                }

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
            var applied = kind switch
            {
                "container-links" => ManifestApplier.ApplyContainerLinks(manifestPath, homeDir, dataDir),
                "init-dirs" => ManifestApplier.ApplyInitDirs(manifestPath, dataDir),
                "agent-shims" => ManifestApplier.ApplyAgentShims(manifestPath, shimDir, caiBinaryPath),
                _ => throw new InvalidOperationException($"unknown apply kind: {kind}"),
            };

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

    private async Task<int> RunManifestCheckCoreAsync(string? manifestDirectory, CancellationToken cancellationToken)
    {
        manifestDirectory = ResolveManifestDirectory(manifestDirectory);
        if (!Directory.Exists(manifestDirectory))
        {
            await stderr.WriteLineAsync($"ERROR: manifest directory not found: {manifestDirectory}").ConfigureAwait(false);
            return 1;
        }

        var manifestFiles = Directory
            .EnumerateFiles(manifestDirectory, "*.toml", SearchOption.TopDirectoryOnly)
            .OrderBy(static path => path, StringComparer.Ordinal)
            .ToArray();
        if (manifestFiles.Length == 0)
        {
            await stderr.WriteLineAsync($"ERROR: no .toml files found in directory: {manifestDirectory}").ConfigureAwait(false);
            return 1;
        }

        foreach (var file in manifestFiles)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ManifestTomlParser.Parse(file, includeDisabled: true, includeSourceFile: false);
        }

        var linkSpec = ManifestGenerators.GenerateContainerLinkSpec(manifestDirectory);
        var initProbeDir = Path.Combine(Path.GetTempPath(), $"cai-manifest-check-{Guid.NewGuid():N}");
        var initApplied = 0;
        try
        {
            initApplied = ManifestApplier.ApplyInitDirs(manifestDirectory, initProbeDir);
        }
        finally
        {
            if (Directory.Exists(initProbeDir))
            {
                Directory.Delete(initProbeDir, recursive: true);
            }
        }

        if (initApplied <= 0)
        {
            await stderr.WriteLineAsync("ERROR: init-dir apply produced no operations").ConfigureAwait(false);
            return 1;
        }

        try
        {
            using var document = JsonDocument.Parse(linkSpec.Content);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty("links", out var links) ||
                links.ValueKind != JsonValueKind.Array)
            {
                await stderr.WriteLineAsync("ERROR: generated link spec appears invalid").ConfigureAwait(false);
                return 1;
            }
        }
        catch (JsonException)
        {
            await stderr.WriteLineAsync("ERROR: generated link spec is not valid JSON").ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync("Manifest consistency check passed.").ConfigureAwait(false);
        return 0;
    }

    private static string ResolveImportManifestDirectory()
    {
        var candidates = ResolveManifestDirectoryCandidates();
        foreach (var candidate in candidates)
        {
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException($"manifest directory not found; tried: {string.Join(", ", candidates)}");
    }

    private static string ResolveManifestDirectory(string? userProvidedPath)
    {
        if (!string.IsNullOrWhiteSpace(userProvidedPath))
        {
            return Path.GetFullPath(ExpandHomePath(userProvidedPath));
        }

        var candidates = ResolveManifestDirectoryCandidates();
        foreach (var candidate in candidates)
        {
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        return candidates[0];
    }

    private static string[] ResolveManifestDirectoryCandidates()
    {
        var candidates = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        static void AddCandidate(ICollection<string> target, ISet<string> seenSet, string? path)
        {
            if (string.IsNullOrWhiteSpace(path))
            {
                return;
            }

            var fullPath = Path.GetFullPath(path);
            if (seenSet.Add(fullPath))
            {
                target.Add(fullPath);
            }
        }

        var installRoot = InstallMetadata.ResolveInstallDirectory();
        AddCandidate(candidates, seen, Path.Combine(installRoot, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(installRoot, "src", "manifests"));

        var appBase = Path.GetFullPath(AppContext.BaseDirectory);
        AddCandidate(candidates, seen, Path.Combine(appBase, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", "manifests"));
        AddCandidate(candidates, seen, Path.Combine(appBase, "..", "..", "..", "manifests"));

        var current = Directory.GetCurrentDirectory();
        AddCandidate(candidates, seen, Path.Combine(current, "manifests"));
        AddCandidate(candidates, seen, Path.Combine(current, "src", "manifests"));

        AddCandidate(candidates, seen, "/opt/containai/manifests");
        return candidates.ToArray();
    }

    private async Task<int> ConfigListAsync(string configPath, CancellationToken cancellationToken)
    {
        var parseResult = await RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (parseResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync(parseResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        await stdout.WriteLineAsync(parseResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> ConfigGetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key))
        {
            await stderr.WriteLineAsync("config get requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        if (!parsed.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            var wsResult = await RunTomlAsync(
                () => TomlCommandProcessor.GetWorkspace(configPath, workspaceScope.Workspace),
                cancellationToken).ConfigureAwait(false);
            if (wsResult.ExitCode != 0)
            {
                return 1;
            }

            using var wsJson = JsonDocument.Parse(wsResult.StandardOutput);
            if (wsJson.RootElement.ValueKind == JsonValueKind.Object &&
                wsJson.RootElement.TryGetProperty(parsed.Key, out var wsValue))
            {
                await stdout.WriteLineAsync(wsValue.ToString()).ConfigureAwait(false);
                return 0;
            }

            return 1;
        }

        var getResult = await RunTomlAsync(
            () => TomlCommandProcessor.GetKey(configPath, normalizedKey),
            cancellationToken).ConfigureAwait(false);

        if (getResult.ExitCode != 0)
        {
            return 1;
        }

        await stdout.WriteLineAsync(getResult.StandardOutput.Trim()).ConfigureAwait(false);
        return 0;
    }

    private async Task<int> ConfigSetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key) || parsed.Value is null)
        {
            await stderr.WriteLineAsync("config set requires <key> <value>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        ProcessResult setResult;
        if (!parsed.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            setResult = await RunTomlAsync(
                () => TomlCommandProcessor.SetWorkspaceKey(configPath, workspaceScope.Workspace, parsed.Key, parsed.Value),
                cancellationToken).ConfigureAwait(false);
        }
        else
        {
            setResult = await RunTomlAsync(
                () => TomlCommandProcessor.SetKey(configPath, normalizedKey, parsed.Value),
                cancellationToken).ConfigureAwait(false);
        }

        if (setResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync(setResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> ConfigUnsetAsync(string configPath, ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(parsed.Key))
        {
            await stderr.WriteLineAsync("config unset requires <key>").ConfigureAwait(false);
            return 1;
        }

        var normalizedKey = NormalizeConfigKey(parsed.Key);
        var workspaceScope = ResolveWorkspaceScope(parsed, normalizedKey);
        if (workspaceScope.Error is not null)
        {
            await stderr.WriteLineAsync(workspaceScope.Error).ConfigureAwait(false);
            return 1;
        }

        ProcessResult unsetResult;
        if (!parsed.Global && !string.IsNullOrWhiteSpace(workspaceScope.Workspace))
        {
            unsetResult = await RunTomlAsync(
                () => TomlCommandProcessor.UnsetWorkspaceKey(configPath, workspaceScope.Workspace, parsed.Key),
                cancellationToken).ConfigureAwait(false);
        }
        else
        {
            unsetResult = await RunTomlAsync(
                () => TomlCommandProcessor.UnsetKey(configPath, normalizedKey),
                cancellationToken).ConfigureAwait(false);
        }

        if (unsetResult.ExitCode != 0)
        {
            await stderr.WriteLineAsync(unsetResult.StandardError.Trim()).ConfigureAwait(false);
            return 1;
        }

        return 0;
    }

    private async Task<int> ConfigResolveVolumeAsync(ParsedConfigCommand parsed, CancellationToken cancellationToken)
    {
        var workspace = string.IsNullOrWhiteSpace(parsed.Workspace)
            ? Directory.GetCurrentDirectory()
            : Path.GetFullPath(ExpandHomePath(parsed.Workspace));

        var volume = await ResolveDataVolumeAsync(workspace, parsed.Key, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(volume))
        {
            return 1;
        }

        await stdout.WriteLineAsync(volume).ConfigureAwait(false);
        return 0;
    }
}
