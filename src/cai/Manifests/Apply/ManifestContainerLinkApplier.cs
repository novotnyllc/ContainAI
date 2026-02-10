namespace ContainAI.Cli.Host.Manifests.Apply;

internal sealed class ManifestContainerLinkApplier : IManifestContainerLinkApplier
{
    private readonly IManifestTomlParser manifestTomlParser;

    public ManifestContainerLinkApplier(IManifestTomlParser manifestTomlParser)
        => this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));

    public int Apply(string manifestPath, string homeDirectory, string dataDirectory)
    {
        var homeRoot = Path.GetFullPath(homeDirectory);
        var dataRoot = Path.GetFullPath(dataDirectory);

        var entries = manifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false)
            .Where(static entry => !string.IsNullOrWhiteSpace(entry.ContainerLink))
            .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
            .ToArray();

        var applied = 0;
        foreach (var entry in entries)
        {
            var linkPath = ManifestApplyPathOperations.CombineUnderRoot(homeRoot, entry.ContainerLink, "container_link");
            var targetPath = ManifestApplyPathOperations.CombineUnderRoot(dataRoot, entry.Target, "target");
            ApplyLink(linkPath, targetPath, entry.Flags.Contains('R', StringComparison.Ordinal));
            applied++;
        }

        return applied;
    }

    private static void ApplyLink(string linkPath, string targetPath, bool removeFirst)
    {
        var parent = Path.GetDirectoryName(linkPath);
        if (!string.IsNullOrWhiteSpace(parent))
        {
            Directory.CreateDirectory(parent);
        }

        if (ManifestApplyPathOperations.IsSymbolicLink(linkPath))
        {
            var currentTarget = ManifestApplyPathOperations.ResolveLinkTarget(linkPath);
            if (string.Equals(currentTarget, targetPath, StringComparison.Ordinal))
            {
                return;
            }

            File.Delete(linkPath);
        }
        else if (Directory.Exists(linkPath))
        {
            if (!removeFirst)
            {
                throw new InvalidOperationException($"cannot replace directory without R flag: {linkPath}");
            }

            Directory.Delete(linkPath, recursive: true);
        }
        else if (File.Exists(linkPath))
        {
            File.Delete(linkPath);
        }

        File.CreateSymbolicLink(linkPath, targetPath);
    }
}
