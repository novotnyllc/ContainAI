namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportPathOperations
{
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
}
