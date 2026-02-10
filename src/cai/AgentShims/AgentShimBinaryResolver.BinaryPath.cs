namespace ContainAI.Cli.Host.AgentShims;

internal sealed partial class AgentShimBinaryResolver
{
    public string? ResolveBinaryPath(string binary, IReadOnlyList<string> shimDirectories, string currentExecutablePath)
    {
        var pathValue = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathValue))
        {
            return null;
        }

        foreach (var rawDirectory in pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (string.IsNullOrWhiteSpace(rawDirectory))
            {
                continue;
            }

            var candidate = Path.Combine(rawDirectory, binary);
            if (!File.Exists(candidate))
            {
                continue;
            }

            var resolvedCandidate = Path.GetFullPath(candidate);
            if (IsInShimDirectory(resolvedCandidate, shimDirectories))
            {
                continue;
            }

            if (PointsToPath(resolvedCandidate, currentExecutablePath))
            {
                continue;
            }

            return resolvedCandidate;
        }

        return null;
    }

    private static bool IsInShimDirectory(string candidate, IReadOnlyList<string> shimDirectories)
    {
        foreach (var shimDirectory in shimDirectories)
        {
            if (string.Equals(candidate, shimDirectory, StringComparison.Ordinal))
            {
                return true;
            }

            if (candidate.StartsWith(shimDirectory + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private static bool PointsToPath(string path, string expectedPath)
    {
        if (string.IsNullOrWhiteSpace(expectedPath))
        {
            return false;
        }

        if (string.Equals(path, expectedPath, StringComparison.Ordinal))
        {
            return true;
        }

        var info = new FileInfo(path);
        if (string.IsNullOrWhiteSpace(info.LinkTarget))
        {
            return false;
        }

        var linkTarget = info.LinkTarget;
        var resolved = Path.IsPathRooted(linkTarget)
            ? Path.GetFullPath(linkTarget)
            : Path.GetFullPath(Path.Combine(Path.GetDirectoryName(path) ?? "/", linkTarget));
        return string.Equals(resolved, expectedPath, StringComparison.Ordinal);
    }
}
