namespace ContainAI.Cli.Host;

internal interface IManifestTomlParser
{
    IReadOnlyList<ManifestEntry> Parse(string manifestPath, bool includeDisabled, bool includeSourceFile);

    IReadOnlyList<ManifestAgentEntry> ParseAgents(string manifestPath);
}

internal sealed partial class ManifestTomlParser : IManifestTomlParser
{
    public IReadOnlyList<ManifestEntry> Parse(
        string manifestPath,
        bool includeDisabled,
        bool includeSourceFile)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(manifestPath);

        var manifestFiles = ResolveManifestFiles(manifestPath);
        var entries = new List<ManifestEntry>();
        foreach (var manifestFile in manifestFiles)
        {
            var document = ParseManifestFile(manifestFile);
            if (document is null)
            {
                continue;
            }

            AddSectionEntries(document.Entries, "entry", manifestFile, includeDisabled, includeSourceFile, entries);
            AddSectionEntries(document.ContainerSymlinks, "symlink", manifestFile, includeDisabled, includeSourceFile, entries);
        }

        return entries;
    }

    public IReadOnlyList<ManifestAgentEntry> ParseAgents(string manifestPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(manifestPath);

        var manifestFiles = ResolveManifestFiles(manifestPath);
        var entries = new List<ManifestAgentEntry>();
        foreach (var manifestFile in manifestFiles)
        {
            var document = ParseManifestFile(manifestFile);
            if (document?.Agent is null)
            {
                continue;
            }

            var name = ReadString(document.Agent.Name);
            var binary = ReadString(document.Agent.Binary);
            var defaultArgs = ReadStringArray(document.Agent.DefaultArgs);
            var aliases = ReadStringArray(document.Agent.Aliases);
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
