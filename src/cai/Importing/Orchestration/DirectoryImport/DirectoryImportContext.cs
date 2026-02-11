using ContainAI.Cli.Abstractions;

namespace ContainAI.Cli.Host;

internal sealed class DirectoryImportContext
{
    public DirectoryImportContext(
        ImportCommandOptions options,
        string workspace,
        string? explicitConfigPath,
        string sourcePath,
        string volume,
        bool excludePriv,
        ManifestEntry[] manifestEntries)
    {
        Options = options;
        Workspace = workspace;
        ExplicitConfigPath = explicitConfigPath;
        SourcePath = sourcePath;
        Volume = volume;
        ExcludePriv = excludePriv;
        ManifestEntries = manifestEntries;
    }

    public ImportCommandOptions Options { get; }

    public string Workspace { get; }

    public string? ExplicitConfigPath { get; }

    public string SourcePath { get; }

    public string Volume { get; }

    public bool ExcludePriv { get; }

    public ManifestEntry[] ManifestEntries { get; }

    public IReadOnlyList<ImportAdditionalPath> AdditionalImportPaths { get; private set; } = Array.Empty<ImportAdditionalPath>();

    public void SetAdditionalImportPaths(IReadOnlyList<ImportAdditionalPath> additionalImportPaths)
        => AdditionalImportPaths = additionalImportPaths ?? throw new ArgumentNullException(nameof(additionalImportPaths));
}
