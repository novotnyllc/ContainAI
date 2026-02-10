namespace ContainAI.Cli.Host.AgentShims;

internal interface IAgentShimBinaryResolver
{
    string ResolveCurrentExecutablePath();

    string[] ResolveShimDirectories();

    string? ResolveBinaryPath(string binary, IReadOnlyList<string> shimDirectories, string currentExecutablePath);
}
