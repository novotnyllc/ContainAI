namespace ContainAI.Cli.Host.AgentShims;

internal sealed partial class AgentShimDefinitionResolver : IAgentShimDefinitionResolver
{
    private readonly IManifestTomlParser manifestTomlParser;

    public AgentShimDefinitionResolver(IManifestTomlParser manifestTomlParser)
        => this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
}
