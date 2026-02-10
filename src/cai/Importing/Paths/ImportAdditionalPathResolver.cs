namespace ContainAI.Cli.Host.Importing.Paths;

internal static class ImportAdditionalPathResolver
{
    internal static bool TryResolveAdditionalImportPath(
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

        if (!TryMapAdditionalPathTarget(validatedRawPath, effectiveHome, fullPath, out var targetRelativePath, out warning))
        {
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
        if (!TryValidatePathWithinHome(rawPath, fullPath, effectiveHome, out warning))
        {
            return false;
        }

        if (!PathExists(fullPath))
        {
            warning = null;
            return false;
        }

        if (!TryValidateNoSymlinkComponents(rawPath, effectiveHome, fullPath, out warning))
        {
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

    private static bool TryMapAdditionalPathTarget(
        string rawPath,
        string homeDirectory,
        string fullPath,
        out string targetRelativePath,
        out string? warning)
    {
        targetRelativePath = MapAdditionalPathTarget(homeDirectory, fullPath);
        if (!string.IsNullOrWhiteSpace(targetRelativePath))
        {
            warning = null;
            return true;
        }

        warning = $"[WARN] [import].additional_paths '{rawPath}' resolved to an empty target; skipping";
        return false;
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
        first = NormalizeTargetRootSegment(first);

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

            if (CaiRuntimePathHelpers.IsSymbolicLinkPath(current))
            {
                return true;
            }
        }

        return false;
    }

    private static bool TryValidatePathWithinHome(
        string rawPath,
        string fullPath,
        string effectiveHome,
        out string? warning)
    {
        if (IsPathWithinDirectory(fullPath, effectiveHome))
        {
            warning = null;
            return true;
        }

        warning = $"[WARN] [import].additional_paths '{rawPath}' escapes HOME; skipping";
        return false;
    }

    private static bool TryValidateNoSymlinkComponents(
        string rawPath,
        string effectiveHome,
        string fullPath,
        out string? warning)
    {
        if (!ContainsSymlinkComponent(effectiveHome, fullPath))
        {
            warning = null;
            return true;
        }

        warning = $"[WARN] [import].additional_paths '{rawPath}' contains symlink components; skipping";
        return false;
    }

    private static bool PathExists(string fullPath) => File.Exists(fullPath) || Directory.Exists(fullPath);

    private static string NormalizeTargetRootSegment(string segment) => segment.StartsWith('.') ? segment.TrimStart('.') : segment;
}
