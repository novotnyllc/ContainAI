namespace ContainAI.Cli.Host;

internal sealed class ManifestTomlParser : IManifestTomlParser
{
    public IReadOnlyList<ManifestEntry> Parse(
        string manifestPath,
        bool includeDisabled,
        bool includeSourceFile)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(manifestPath);

        var manifestFiles = ManifestTomlFileResolver.Resolve(manifestPath);
        var entries = new List<ManifestEntry>();
        foreach (var manifestFile in manifestFiles)
        {
            var document = ManifestTomlDocumentLoader.Parse(manifestFile);
            if (document is null)
            {
                continue;
            }

            ManifestTomlEntryCollector.AddSectionEntries(document.Entries, "entry", manifestFile, includeDisabled, includeSourceFile, entries);
            ManifestTomlEntryCollector.AddSectionEntries(document.ContainerSymlinks, "symlink", manifestFile, includeDisabled, includeSourceFile, entries);
        }

        return entries;
    }

    public IReadOnlyList<ManifestAgentEntry> ParseAgents(string manifestPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(manifestPath);

        var manifestFiles = ManifestTomlFileResolver.Resolve(manifestPath);
        var entries = new List<ManifestAgentEntry>();
        foreach (var manifestFile in manifestFiles)
        {
            var document = ManifestTomlDocumentLoader.Parse(manifestFile);
            if (document?.Agent is null)
            {
                continue;
            }

            var name = ManifestTomlValueReader.ReadString(document.Agent.Name);
            var binary = ManifestTomlValueReader.ReadString(document.Agent.Binary);
            var defaultArgs = ManifestTomlValueReader.ReadStringArray(document.Agent.DefaultArgs);
            var aliases = ManifestTomlValueReader.ReadStringArray(document.Agent.Aliases);
            var optional = document.Agent.Optional;

            if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(binary) || defaultArgs.Count == 0)
            {
                continue;
            }

            entries.Add(new ManifestAgentEntry(
                Name: name,
                Binary: binary,
                DefaultArgs: defaultArgs,
                Aliases: aliases,
                Optional: optional,
                SourceFile: manifestFile));
        }

        return entries;
    }
}
