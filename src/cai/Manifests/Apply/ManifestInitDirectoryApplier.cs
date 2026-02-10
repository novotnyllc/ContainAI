namespace ContainAI.Cli.Host.Manifests.Apply;

internal sealed class ManifestInitDirectoryApplier : IManifestInitDirectoryApplier
{
    private readonly IManifestTomlParser manifestTomlParser;

    public ManifestInitDirectoryApplier(IManifestTomlParser manifestTomlParser)
        => this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));

    public int Apply(string manifestPath, string dataDirectory)
    {
        var dataRoot = Path.GetFullPath(dataDirectory);
        Directory.CreateDirectory(dataRoot);

        var parsed = manifestTomlParser.Parse(manifestPath, includeDisabled: true, includeSourceFile: false);
        var applied = 0;

        foreach (var entry in parsed.Where(static entry => string.Equals(entry.Type, "entry", StringComparison.Ordinal)))
        {
            if (string.IsNullOrWhiteSpace(entry.Target) || entry.Flags.Contains('G', StringComparison.Ordinal))
            {
                continue;
            }

            if (entry.Flags.Contains('f', StringComparison.Ordinal) && string.IsNullOrWhiteSpace(entry.ContainerLink))
            {
                continue;
            }

            var fullPath = ManifestApplyPathOperations.CombineUnderRoot(dataRoot, entry.Target, "target");
            if (entry.Flags.Contains('d', StringComparison.Ordinal))
            {
                ManifestApplyPathOperations.EnsureDirectory(fullPath);
                if (entry.Flags.Contains('s', StringComparison.Ordinal))
                {
                    ManifestApplyPathOperations.SetUnixModeIfSupported(
                        fullPath,
                        UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
                }

                applied++;
                continue;
            }

            if (!entry.Flags.Contains('f', StringComparison.Ordinal))
            {
                continue;
            }

            ManifestApplyPathOperations.EnsureFile(fullPath, initializeJson: entry.Flags.Contains('j', StringComparison.Ordinal));
            if (entry.Flags.Contains('s', StringComparison.Ordinal))
            {
                ManifestApplyPathOperations.SetUnixModeIfSupported(fullPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            }

            applied++;
        }

        foreach (var entry in parsed.Where(static entry => string.Equals(entry.Type, "symlink", StringComparison.Ordinal)))
        {
            if (string.IsNullOrWhiteSpace(entry.Target) || !entry.Flags.Contains('f', StringComparison.Ordinal))
            {
                continue;
            }

            var fullPath = ManifestApplyPathOperations.CombineUnderRoot(dataRoot, entry.Target, "target");
            ManifestApplyPathOperations.EnsureFile(fullPath, initializeJson: entry.Flags.Contains('j', StringComparison.Ordinal));
            applied++;
        }

        return applied;
    }
}
