using System.Text.Json;
using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Importing.Paths;

internal sealed class ImportAdditionalPathCatalog : CaiRuntimeSupport
    , IImportAdditionalPathCatalog
{
    public ImportAdditionalPathCatalog(TextWriter standardOutput, TextWriter standardError)
        : base(standardOutput, standardError)
    {
    }

    public async Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        string configPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(configPath))
        {
            return [];
        }

        var result = await RunTomlAsync(() => TomlCommandProcessor.GetJson(configPath), cancellationToken).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            if (verbose && !string.IsNullOrWhiteSpace(result.StandardError))
            {
                await stderr.WriteLineAsync(result.StandardError.Trim()).ConfigureAwait(false);
            }

            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(result.StandardOutput);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty("import", out var importElement) ||
                importElement.ValueKind != JsonValueKind.Object ||
                !importElement.TryGetProperty("additional_paths", out var pathsElement))
            {
                return [];
            }

            if (pathsElement.ValueKind != JsonValueKind.Array)
            {
                await stderr.WriteLineAsync("[WARN] [import].additional_paths must be a list; ignoring").ConfigureAwait(false);
                return [];
            }

            var values = new List<ImportAdditionalPath>();
            var seenSources = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in pathsElement.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.String)
                {
                    await stderr.WriteLineAsync($"[WARN] [import].additional_paths item must be a string; got {item.ValueKind}").ConfigureAwait(false);
                    continue;
                }

                var rawPath = item.GetString();
                if (!TryResolveAdditionalImportPath(rawPath, sourceRoot, excludePriv, out var resolved, out var warning))
                {
                    if (!string.IsNullOrWhiteSpace(warning))
                    {
                        await stderr.WriteLineAsync(warning).ConfigureAwait(false);
                    }

                    continue;
                }

                if (!seenSources.Add(resolved.SourcePath))
                {
                    continue;
                }

                values.Add(resolved);
            }

            return values;
        }
        catch (JsonException ex)
        {
            if (verbose)
            {
                await stderr.WriteLineAsync($"[WARN] Failed to parse config JSON for additional paths: {ex.Message}").ConfigureAwait(false);
            }

            return [];
        }
    }

    private static bool TryResolveAdditionalImportPath(
        string? rawPath,
        string sourceRoot,
        bool excludePriv,
        out ImportAdditionalPath resolved,
        out string? warning)
    {
        resolved = default;

        if (!TryValidateAdditionalPathEntry(rawPath, out warning))
        {
            return false;
        }

        var validatedRawPath = rawPath!;
        if (!TryResolveNormalizedAdditionalPath(validatedRawPath, sourceRoot, out var effectiveHome, out var fullPath, out warning))
        {
            return false;
        }

        if (!TryValidateAdditionalPathBoundaries(validatedRawPath, effectiveHome, fullPath, out warning))
        {
            return false;
        }

        var targetRelativePath = MapAdditionalPathTarget(effectiveHome, fullPath);
        if (string.IsNullOrWhiteSpace(targetRelativePath))
        {
            warning = $"[WARN] [import].additional_paths '{validatedRawPath}' resolved to an empty target; skipping";
            return false;
        }

        var isDirectory = Directory.Exists(fullPath);
        var applyPrivFilter = excludePriv && IsBashrcDirectoryPath(effectiveHome, fullPath);
        resolved = new ImportAdditionalPath(fullPath, targetRelativePath, isDirectory, applyPrivFilter);
        warning = null;
        return true;
    }

    private static bool TryValidateAdditionalPathEntry(string? rawPath, out string? warning)
    {
        warning = null;

        if (string.IsNullOrWhiteSpace(rawPath))
        {
            warning = "[WARN] [import].additional_paths entry is empty; skipping";
            return false;
        }

        if (rawPath.Contains(':', StringComparison.Ordinal))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' contains ':'; skipping";
            return false;
        }

        return true;
    }

    private static bool TryResolveNormalizedAdditionalPath(
        string rawPath,
        string sourceRoot,
        out string effectiveHome,
        out string fullPath,
        out string? warning)
    {
        effectiveHome = Path.GetFullPath(sourceRoot);
        fullPath = string.Empty;
        warning = null;

        var expandedPath = ExpandHomeRelativePath(rawPath, effectiveHome);
        if (rawPath.StartsWith('~') && !rawPath.StartsWith("~/", StringComparison.Ordinal) && !rawPath.StartsWith("~\\", StringComparison.Ordinal))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' uses unsupported user-home expansion; use ~/...";
            return false;
        }

        if (!Path.IsPathRooted(expandedPath))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' must be ~/... or absolute under HOME";
            return false;
        }

        fullPath = Path.GetFullPath(expandedPath);
        return true;
    }

    private static bool TryValidateAdditionalPathBoundaries(
        string rawPath,
        string effectiveHome,
        string fullPath,
        out string? warning)
    {
        warning = null;

        if (!IsPathWithinDirectory(fullPath, effectiveHome))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' escapes HOME; skipping";
            return false;
        }

        if (!File.Exists(fullPath) && !Directory.Exists(fullPath))
        {
            return false;
        }

        if (ContainsSymlinkComponent(effectiveHome, fullPath))
        {
            warning = $"[WARN] [import].additional_paths '{rawPath}' contains symlink components; skipping";
            return false;
        }

        return true;
    }

    private static string ExpandHomeRelativePath(string rawPath, string effectiveHome)
    {
        if (!rawPath.StartsWith('~'))
        {
            return rawPath;
        }

        return rawPath.Length == 1
            ? effectiveHome
            : rawPath[1] switch
            {
                '/' or '\\' => Path.Combine(effectiveHome, rawPath[2..]),
                _ => rawPath,
            };
    }

    private static string MapAdditionalPathTarget(string homeDirectory, string fullPath)
    {
        var relative = Path.GetRelativePath(homeDirectory, fullPath).Replace('\\', '/');
        if (string.Equals(relative, ".", StringComparison.Ordinal))
        {
            return string.Empty;
        }

        var segments = relative.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0)
        {
            return string.Empty;
        }

        var first = segments[0];
        if (first.StartsWith('.'))
        {
            first = first.TrimStart('.');
        }

        if (string.IsNullOrWhiteSpace(first))
        {
            return string.Empty;
        }

        segments[0] = first;
        return string.Join('/', segments);
    }

    private static bool IsBashrcDirectoryPath(string homeDirectory, string fullPath)
    {
        var normalized = Path.GetFullPath(fullPath);
        var bashrcDirectory = Path.Combine(Path.GetFullPath(homeDirectory), ".bashrc.d");
        return IsPathWithinDirectory(normalized, bashrcDirectory);
    }

    private static bool IsPathWithinDirectory(string path, string directory)
    {
        var normalizedDirectory = Path.GetFullPath(directory)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var normalizedPath = Path.GetFullPath(path)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (string.Equals(normalizedPath, normalizedDirectory, StringComparison.Ordinal))
        {
            return true;
        }

        return normalizedPath.StartsWith(
            normalizedDirectory + Path.DirectorySeparatorChar,
            StringComparison.Ordinal);
    }

    private static bool ContainsSymlinkComponent(string baseDirectory, string fullPath)
    {
        var relative = Path.GetRelativePath(baseDirectory, fullPath);
        if (relative.StartsWith("..", StringComparison.Ordinal))
        {
            return true;
        }

        var current = Path.GetFullPath(baseDirectory);
        var segments = relative.Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries);
        foreach (var segment in segments)
        {
            current = Path.Combine(current, segment);
            if (!File.Exists(current) && !Directory.Exists(current))
            {
                continue;
            }

            if (IsSymbolicLinkPath(current))
            {
                return true;
            }
        }

        return false;
    }
}
