namespace ContainAI.Cli.Host.AgentShims;

internal interface IAgentShimBinaryPathResolver
{
    string? Resolve(string binary, IReadOnlyList<string> shimDirectories, string currentExecutablePath);
}
