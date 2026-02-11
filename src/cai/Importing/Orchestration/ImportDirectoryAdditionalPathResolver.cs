namespace ContainAI.Cli.Host;

internal sealed class ImportDirectoryAdditionalPathResolver
{
    private readonly IImportPathOperations pathOperations;

    public ImportDirectoryAdditionalPathResolver(IImportPathOperations importPathOperations)
        => pathOperations = importPathOperations ?? throw new ArgumentNullException(nameof(importPathOperations));

    public Task<IReadOnlyList<ImportAdditionalPath>> ResolveAsync(
        string workspace,
        string? explicitConfigPath,
        bool excludePriv,
        string sourcePath,
        bool verbose,
        CancellationToken cancellationToken)
        => pathOperations.ResolveAdditionalImportPathsAsync(
            workspace,
            explicitConfigPath,
            excludePriv,
            sourcePath,
            verbose,
            cancellationToken);
}
