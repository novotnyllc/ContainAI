namespace ContainAI.Cli.Host.AgentShims;

internal interface IAgentShimPathCandidateFilter
{
    bool ShouldInclude(string candidatePath, IReadOnlyList<string> shimDirectories, string currentExecutablePath);
}
