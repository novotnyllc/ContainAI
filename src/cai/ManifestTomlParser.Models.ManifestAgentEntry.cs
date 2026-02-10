namespace ContainAI.Cli.Host;

internal readonly record struct ManifestAgentEntry(
    string Name,
    string Binary,
    IReadOnlyList<string> DefaultArgs,
    IReadOnlyList<string> Aliases,
    bool Optional,
    string SourceFile);
