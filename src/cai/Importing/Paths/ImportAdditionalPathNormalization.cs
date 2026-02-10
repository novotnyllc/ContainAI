namespace ContainAI.Cli.Host.Importing.Paths;

internal static class ImportAdditionalPathNormalization
{
    internal static bool TryResolveNormalizedAdditionalPath(
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
}
