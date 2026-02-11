using ContainAI.Cli.Host.RuntimeSupport.Paths;

namespace ContainAI.Cli.Host.Importing.Paths;

internal static class ImportAdditionalPathBoundaryChecks
{
    internal static bool TryValidateAdditionalPathBoundaries(
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

    internal static bool IsPathWithinDirectory(string path, string directory)
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

    private static bool PathExists(string fullPath) => File.Exists(fullPath) || Directory.Exists(fullPath);

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
