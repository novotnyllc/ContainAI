namespace ContainAI.Cli.Host.Manifests.Apply;

internal sealed class ManifestApplier : IManifestApplier
{
    private readonly IManifestContainerLinkApplier containerLinkApplier;
    private readonly IManifestInitDirectoryApplier initDirectoryApplier;
    private readonly IManifestAgentShimApplier agentShimApplier;

    public ManifestApplier(IManifestTomlParser manifestTomlParser)
        : this(
            new ManifestContainerLinkApplier(manifestTomlParser),
            new ManifestInitDirectoryApplier(manifestTomlParser),
            new ManifestAgentShimApplier(manifestTomlParser))
    {
    }

    internal ManifestApplier(
        IManifestContainerLinkApplier containerLinkApplier,
        IManifestInitDirectoryApplier initDirectoryApplier,
        IManifestAgentShimApplier agentShimApplier)
    {
        this.containerLinkApplier = containerLinkApplier ?? throw new ArgumentNullException(nameof(containerLinkApplier));
        this.initDirectoryApplier = initDirectoryApplier ?? throw new ArgumentNullException(nameof(initDirectoryApplier));
        this.agentShimApplier = agentShimApplier ?? throw new ArgumentNullException(nameof(agentShimApplier));
    }

    public int ApplyContainerLinks(string manifestPath, string homeDirectory, string dataDirectory)
        => containerLinkApplier.Apply(manifestPath, homeDirectory, dataDirectory);

    public int ApplyInitDirs(string manifestPath, string dataDirectory)
        => initDirectoryApplier.Apply(manifestPath, dataDirectory);

    public int ApplyAgentShims(string manifestPath, string shimDirectory, string caiExecutablePath)
        => agentShimApplier.Apply(manifestPath, shimDirectory, caiExecutablePath);
}
