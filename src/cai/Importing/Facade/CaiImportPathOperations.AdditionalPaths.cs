using ContainAI.Cli.Host.Importing.Paths;

namespace ContainAI.Cli.Host;

internal sealed partial class CaiImportPathOperations
{
    public Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        string workspace,
        string? explicitConfigPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var configPath = ResolveImportConfigPath(workspace, explicitConfigPath);
        return additionalPathCatalog.ResolveAdditionalImportPathsAsync(configPath, excludePriv, sourceRoot, verbose, cancellationToken);
    }

    public Task<int> ImportAdditionalPathAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
        => additionalPathTransferOperations.ImportAdditionalPathAsync(volume, additionalPath, noExcludes, dryRun, verbose, cancellationToken);
}
