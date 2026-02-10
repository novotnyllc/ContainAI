namespace ContainAI.Cli.Host.Importing.Paths;

internal static class ImportAdditionalPathTargetMapping
{
    internal static bool TryMapAdditionalPathTarget(
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

    private static string NormalizeTargetRootSegment(string segment) => segment.StartsWith('.') ? segment.TrimStart('.') : segment;
}
