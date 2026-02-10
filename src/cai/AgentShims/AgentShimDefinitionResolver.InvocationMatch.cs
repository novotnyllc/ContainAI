namespace ContainAI.Cli.Host.AgentShims;

internal sealed partial class AgentShimDefinitionResolver
{
    private static bool MatchesInvocation(ManifestAgentEntry entry, string invocationName)
    {
        if (string.Equals(entry.Name, invocationName, StringComparison.Ordinal))
        {
            return true;
        }

        if (string.Equals(entry.Binary, invocationName, StringComparison.Ordinal))
        {
            return true;
        }

        return entry.Aliases.Any(alias => string.Equals(alias, invocationName, StringComparison.Ordinal));
    }
}
