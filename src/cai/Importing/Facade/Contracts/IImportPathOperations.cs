using ContainAI.Cli.Host.Importing.Paths;

namespace ContainAI.Cli.Host;

internal interface IImportPathOperations
{
    Task<bool> ResolveImportExcludePrivAsync(string workspace, string? explicitConfigPath, CancellationToken cancellationToken);

    Task<IReadOnlyList<ImportAdditionalPath>> ResolveAdditionalImportPathsAsync(
        string workspace,
        string? explicitConfigPath,
        bool excludePriv,
        string sourceRoot,
        bool verbose,
        CancellationToken cancellationToken);

    Task<int> ImportAdditionalPathAsync(
        string volume,
        ImportAdditionalPath additionalPath,
        bool noExcludes,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}
