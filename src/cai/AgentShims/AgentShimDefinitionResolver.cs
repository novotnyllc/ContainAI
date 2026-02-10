namespace ContainAI.Cli.Host.AgentShims;

internal sealed class AgentShimDefinitionResolver : IAgentShimDefinitionResolver
{
    private readonly IManifestTomlParser manifestTomlParser;

    public AgentShimDefinitionResolver(IManifestTomlParser manifestTomlParser)
        => this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));

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

    private static string[] ResolveManifestDirectories()
    {
        var candidates = new List<string>();

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrWhiteSpace(home))
        {
            candidates.Add(Path.Combine(home, ".config", "containai", "manifests"));
        }

        candidates.Add("/mnt/agent-data/containai/manifests");

        var installRoot = InstallMetadata.ResolveInstallDirectory();
        if (!string.IsNullOrWhiteSpace(installRoot))
        {
            candidates.Add(Path.Combine(installRoot, "manifests"));
        }

        candidates.Add("/opt/containai/manifests");
        candidates.Add(Path.Combine(Directory.GetCurrentDirectory(), "src", "manifests"));

        return candidates
            .Where(Directory.Exists)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }
}
