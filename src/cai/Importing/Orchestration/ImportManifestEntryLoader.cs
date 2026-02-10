namespace ContainAI.Cli.Host;

internal sealed class ImportManifestEntryLoader
{
    private readonly IManifestTomlParser manifestTomlParser;
    private readonly IImportManifestCatalog manifestCatalog;

    public ImportManifestEntryLoader(
        IManifestTomlParser manifestTomlParser,
        IImportManifestCatalog manifestCatalog)
    {
        this.manifestTomlParser = manifestTomlParser ?? throw new ArgumentNullException(nameof(manifestTomlParser));
        this.manifestCatalog = manifestCatalog ?? throw new ArgumentNullException(nameof(manifestCatalog));
    }

    public ManifestEntry[] LoadManifestEntries()
    {
        var manifestDirectory = manifestCatalog.ResolveDirectory();
        return manifestTomlParser.Parse(manifestDirectory, includeDisabled: false, includeSourceFile: false)
            .Where(static entry => string.Equals(entry.Type, "entry", StringComparison.Ordinal))
            .Where(static entry => !string.IsNullOrWhiteSpace(entry.Source))
            .Where(static entry => !entry.Flags.Contains('G', StringComparison.Ordinal))
            .ToArray();
    }
}
