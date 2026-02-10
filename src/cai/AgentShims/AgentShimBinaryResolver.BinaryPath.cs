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
}
