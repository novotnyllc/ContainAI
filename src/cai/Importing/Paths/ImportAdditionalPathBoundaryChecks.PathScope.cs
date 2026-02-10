namespace ContainAI.Cli.Host.Importing.Paths;

internal static partial class ImportAdditionalPathBoundaryChecks
{
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
}
