namespace ContainAI.Cli.Host.AgentShims;

internal interface IAgentShimDefinitionResolver
{
    ManifestAgentEntry? Resolve(string invocationName);
}
