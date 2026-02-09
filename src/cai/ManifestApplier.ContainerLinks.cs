namespace ContainAI.Cli.Host;

internal static partial class ManifestApplier
{
    public static int ApplyContainerLinks(string manifestPath, string homeDirectory, string dataDirectory)
    {
        var homeRoot = Path.GetFullPath(homeDirectory);
        var dataRoot = Path.GetFullPath(dataDirectory);

        var entries = ManifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false)
            .Where(static entry => !string.IsNullOrWhiteSpace(entry.ContainerLink))
            .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
            .ToArray();

        var applied = 0;
        foreach (var entry in entries)
        {
            var linkPath = CombineUnderRoot(homeRoot, entry.ContainerLink, "container_link");
            var targetPath = CombineUnderRoot(dataRoot, entry.Target, "target");
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

        if (IsSymbolicLink(linkPath))
        {
            var currentTarget = ResolveLinkTarget(linkPath);
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
