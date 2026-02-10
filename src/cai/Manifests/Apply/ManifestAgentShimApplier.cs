namespace ContainAI.Cli.Host.Manifests.Apply;

internal sealed partial class ManifestAgentShimApplier : IManifestAgentShimApplier
{
    private readonly IManifestTomlParser manifestTomlParser;
    private readonly IManifestAgentShimBinaryResolver binaryResolver;
    private readonly IManifestAgentShimLinkWriter linkWriter;

    public ManifestAgentShimApplier(IManifestTomlParser manifestTomlParser)
        : this(
            manifestTomlParser,
            new ManifestAgentShimBinaryResolver(),
            new ManifestAgentShimLinkWriter())
    {
    }

    internal ManifestAgentShimApplier(
        IManifestTomlParser manifestTomlParser,
        IManifestAgentShimBinaryResolver binaryResolver,
        IManifestAgentShimLinkWriter linkWriter)
    {
        this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
        this.binaryResolver = binaryResolver ?? throw new ArgumentNullException(nameof(binaryResolver));
        this.linkWriter = linkWriter ?? throw new ArgumentNullException(nameof(linkWriter));
    }

    public int Apply(string manifestPath, string shimDirectory, string caiExecutablePath)
    {
        var (shimRoot, caiPath) = ValidateAndResolvePaths(shimDirectory, caiExecutablePath);
        Directory.CreateDirectory(shimRoot);

        var agents = manifestTomlParser.ParseAgents(manifestPath);
        var applied = 0;
        foreach (var agent in agents)
        {
            var resolvedBinary = binaryResolver.ResolveBinaryPath(agent.Binary, shimRoot, caiPath);
            if (agent.Optional && resolvedBinary is null)
            {
                continue;
            }

            foreach (var commandName in BuildCommandNames(agent))
            {
                ValidateCommandName(commandName, agent.SourceFile);
                var shimPath = Path.Combine(shimRoot, commandName);
                if (linkWriter.EnsureShimLink(shimPath, caiPath))
                {
                    applied++;
                }
            }
        }

        return applied;
    }
}
