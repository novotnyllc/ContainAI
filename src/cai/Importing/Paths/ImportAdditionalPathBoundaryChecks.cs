namespace ContainAI.Cli.Host.Importing.Paths;

internal static class ImportAdditionalPathBoundaryChecks
{
    internal static bool TryValidateAdditionalPathBoundaries(
        string rawPath,
        string effectiveHome,
        string fullPath,
        out string? warning)
    {
        if (!ImportAdditionalPathHomeBoundaryValidator.TryValidate(rawPath, fullPath, effectiveHome, out warning))
        {
            return false;
        }

        if (!PathExists(fullPath))
        {
            warning = null;
            return false;
        }

        if (!ImportAdditionalPathSymlinkBoundaryValidator.TryValidate(rawPath, effectiveHome, fullPath, out warning))
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

    private static bool PathExists(string fullPath) => File.Exists(fullPath) || Directory.Exists(fullPath);
}
