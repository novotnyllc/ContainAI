using ContainAI.Cli.Host.RuntimeSupport.Docker;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestCopyOperations
{
    Task<int> CopyManifestEntryAsync(
        string volume,
        string sourceRoot,
        ManifestEntry entry,
        bool excludePriv,
        bool noExcludes,
        ManifestImportPlan importPlan,
        CancellationToken cancellationToken);
}
