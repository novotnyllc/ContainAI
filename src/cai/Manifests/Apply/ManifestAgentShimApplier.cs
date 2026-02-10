namespace ContainAI.Cli.Host.Manifests.Apply;

internal sealed class ManifestAgentShimApplier : IManifestAgentShimApplier
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

    private static (string ShimRoot, string CaiPath) ValidateAndResolvePaths(string shimDirectory, string caiExecutablePath)
    {
        if (!Path.IsPathRooted(shimDirectory))
        {
            throw new InvalidOperationException($"shim directory must be absolute: {shimDirectory}");
        }

        if (!Path.IsPathRooted(caiExecutablePath))
        {
            throw new InvalidOperationException($"cai executable path must be absolute: {caiExecutablePath}");
        }

        return (Path.GetFullPath(shimDirectory), Path.GetFullPath(caiExecutablePath));
    }

    private static HashSet<string> BuildCommandNames(ManifestAgentEntry agent)
    {
        var names = new HashSet<string>(StringComparer.Ordinal)
        {
            agent.Name,
            agent.Binary,
        };
        foreach (var alias in agent.Aliases)
        {
            names.Add(alias);
        }

        return names;
    }

    private static void ValidateCommandName(string commandName, string sourceFile)
    {
        if (!ManifestAgentShimRegex.CommandName().IsMatch(commandName))
        {
            throw new InvalidOperationException($"invalid agent command name '{commandName}' in {sourceFile}");
        }
    }
}
