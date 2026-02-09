namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportPathOperations
{
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
