namespace ContainAI.Cli.Host.AgentShims;

internal sealed partial class AgentShimDefinitionResolver
{
    public ManifestAgentEntry? Resolve(string invocationName)
    {
        foreach (var manifestDirectory in ResolveManifestDirectories())
        {
            IReadOnlyList<ManifestAgentEntry> agents;
            try
            {
                agents = manifestTomlParser.ParseAgents(manifestDirectory);
            }
            catch (IOException)
            {
                continue;
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }
            catch (ArgumentException)
            {
                continue;
            }
            catch (InvalidOperationException)
            {
                continue;
            }

            foreach (var agent in agents)
            {
                if (MatchesInvocation(agent, invocationName))
                {
                    return agent;
                }
            }
        }

        return null;
    }
}
