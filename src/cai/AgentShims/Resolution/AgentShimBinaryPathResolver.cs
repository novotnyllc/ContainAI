namespace ContainAI.Cli.Host.AgentShims;

internal interface IAgentShimBinaryPathResolver
{
    string? Resolve(string binary, IReadOnlyList<string> shimDirectories, string currentExecutablePath);
}

internal sealed class AgentShimBinaryPathResolver : IAgentShimBinaryPathResolver
{
    private readonly IAgentShimPathCandidateFilter pathCandidateFilter;

    public AgentShimBinaryPathResolver(IAgentShimPathCandidateFilter pathCandidateFilter)
        => this.pathCandidateFilter = pathCandidateFilter ?? throw new ArgumentNullException(nameof(pathCandidateFilter));

    public string? Resolve(string binary, IReadOnlyList<string> shimDirectories, string currentExecutablePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(binary);
        ArgumentNullException.ThrowIfNull(shimDirectories);

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
            if (pathCandidateFilter.ShouldInclude(resolvedCandidate, shimDirectories, currentExecutablePath))
            {
                return resolvedCandidate;
            }
        }

        return null;
    }
}
