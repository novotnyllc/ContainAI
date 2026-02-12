using ContainAI.Cli.Host.Importing.Symlinks;

namespace ContainAI.Cli.Host.Importing.Transfer;

internal sealed class ImportManifestPostCopyTransferOperations : IImportManifestPostCopyTransferOperations
{
    private readonly IImportPostCopyOperations postCopyOperations;
    private readonly IImportSymlinkRelinker symlinkRelinker;

    public ImportManifestPostCopyTransferOperations(
        IImportPostCopyOperations importPostCopyOperations,
        IImportSymlinkRelinker importSymlinkRelinker)
        => (postCopyOperations, symlinkRelinker) = (
            importPostCopyOperations ?? throw new ArgumentNullException(nameof(importPostCopyOperations)),
            importSymlinkRelinker ?? throw new ArgumentNullException(nameof(importSymlinkRelinker)));

    public async Task<int> ApplyManifestPostCopyAsync(
        string volume,
        ManifestEntry entry,
        ManifestImportPlan importPlan,
        bool dryRun,
        bool verbose,
        CancellationToken cancellationToken)
    {
        var postCopyCode = await postCopyOperations.ApplyManifestPostCopyRulesAsync(
            volume,
            entry,
            dryRun,
            verbose,
            cancellationToken).ConfigureAwait(false);
        if (postCopyCode != 0)
        {
            return postCopyCode;
        }

        if (!importPlan.IsDirectory)
        {
            return 0;
        }

        return await symlinkRelinker.RelinkImportedDirectorySymlinksAsync(
            volume,
            importPlan.SourceAbsolutePath,
            importPlan.NormalizedTarget,
            cancellationToken).ConfigureAwait(false);
    }
}
