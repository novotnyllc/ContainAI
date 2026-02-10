using ContainAI.Cli.Host;

namespace ContainAI.Cli.Host.Importing.Paths;

internal interface IImportAdditionalPathCatalog
{
    Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        string configPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken);
}
