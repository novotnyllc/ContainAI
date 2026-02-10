namespace ContainAI.Cli.Abstractions;

public sealed record ManifestParseCommandOptions(
    bool IncludeDisabled,
    bool EmitSourceFile,
    string ManifestPath);

public sealed record ManifestGenerateCommandOptions(
    string Kind,
    string ManifestPath,
    string? OutputPath);

public sealed record ManifestApplyCommandOptions(
    string Kind,
    string ManifestPath,
    string? DataDir,
    string? HomeDir,
    string? ShimDir,
    string? CaiBinary);

public sealed record ManifestCheckCommandOptions(
    string? ManifestDir);
