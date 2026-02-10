namespace ContainAI.Cli.Host.AgentShims;

internal sealed partial class AgentShimBinaryResolver
{
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
}
