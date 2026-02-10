namespace ContainAI.Cli.Host.Importing.Symlinks;

internal sealed class PosixPathService : IPosixPathService
{
    public bool IsPathWithinDirectory(string path, string directory)
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

    public string NormalizePosixPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return "/";
        }

        var normalized = path.Replace('\\', '/');
        normalized = normalized.Replace("//", "/", StringComparison.Ordinal);
        return string.IsNullOrWhiteSpace(normalized) ? "/" : normalized;
    }

    public string ComputeRelativePosixPath(string fromDirectory, string toPath)
    {
        var fromParts = NormalizePosixPath(fromDirectory).Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        var toParts = NormalizePosixPath(toPath).Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries);
        var maxShared = Math.Min(fromParts.Length, toParts.Length);
        var shared = 0;
        while (shared < maxShared && string.Equals(fromParts[shared], toParts[shared], StringComparison.Ordinal))
        {
            shared++;
        }

        var segments = new List<string>();
        for (var index = shared; index < fromParts.Length; index++)
        {
            segments.Add("..");
        }

        for (var index = shared; index < toParts.Length; index++)
        {
            segments.Add(toParts[index]);
        }

        return segments.Count == 0 ? "." : string.Join('/', segments);
    }
}
