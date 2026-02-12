using ContainAI.Cli.Host.Importing.Symlinks;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal interface IImportManifestPostCopyTransferOperations
{
    Task<int> ApplyManifestPostCopyAsync(
        string volume,
        ManifestEntry entry,
        ManifestImportPlan importPlan,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken);
}
