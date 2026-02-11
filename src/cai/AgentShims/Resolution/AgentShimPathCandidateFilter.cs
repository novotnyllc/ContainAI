namespace ContainAI.Cli.Host.AgentShims;

internal interface IAgentShimPathCandidateFilter
{
    bool ShouldInclude(string candidatePath, IReadOnlyList<string> shimDirectories, string currentExecutablePath);
}

internal sealed class AgentShimPathCandidateFilter : IAgentShimPathCandidateFilter
{
    public bool ShouldInclude(string candidatePath, IReadOnlyList<string> shimDirectories, string currentExecutablePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(candidatePath);
        ArgumentNullException.ThrowIfNull(shimDirectories);

        if (IsInShimDirectory(candidatePath, shimDirectories))
        {
            return false;
        }

        return !PointsToPath(candidatePath, currentExecutablePath);
    }

    private static bool IsInShimDirectory(string candidatePath, IReadOnlyList<string> shimDirectories)
    {
        foreach (var shimDirectory in shimDirectories)
        {
            if (string.Equals(candidatePath, shimDirectory, StringComparison.Ordinal))
            {
                return true;
            }

            if (candidatePath.StartsWith(shimDirectory + Path.DirectorySeparatorChar, StringComparison.Ordinal))
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
