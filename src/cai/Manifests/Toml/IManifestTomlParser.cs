namespace ContainAI.Cli.Host;

internal interface IManifestTomlParser
{
    IReadOnlyList<ManifestEntry> Parse(string manifestPath, bool includeDisabled, bool includeSourceFile);

    IReadOnlyList<ManifestAgentEntry> ParseAgents(string manifestPath);
}
