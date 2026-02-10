namespace ContainAI.Cli.Host.Importing.Paths;

internal static partial class ImportAdditionalPathBoundaryChecks
{
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
}
